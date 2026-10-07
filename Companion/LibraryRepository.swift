import AVFoundation
import Foundation
import OSLog
import ZIPFoundation

struct SavedLibrary: Codable, Sendable {
    let directory: String
    let manifest: LibraryManifest
}

actor LibraryRepository {
    typealias TitleReader = @Sendable (URL) async throws -> String

    private let root: URL
    private let readTitle: TitleReader
    private let maximumTrackBytes: UInt64
    private let maximumTotalBytes: UInt64
    private var importInProgress = false
    private let logger = Logger(subsystem: "com.dalemyers.GaelicCompanion", category: "Library")

    /// Uses a private application-support directory; injectable limits/readers support deterministic tests.
    init(
        root: URL,
        maximumTrackBytes: UInt64 = 512 * 1_024 * 1_024,
        maximumTotalBytes: UInt64 = 3 * 1_024 * 1_024 * 1_024,
        readTitle: @escaping TitleReader = LibraryRepository.audioTitle
    ) {
        self.root = root
        self.maximumTrackBytes = maximumTrackBytes
        self.maximumTotalBytes = maximumTotalBytes
        self.readTitle = readTitle
    }

    /// Validates real audio and reads its ID3 title, rejecting missing titles and non-playable files.
    static func audioTitle(at url: URL) async throws -> String {
        let asset = AVURLAsset(url: url)
        let (playable, duration, metadata) = try await asset.load(.isPlayable, .duration, .commonMetadata)
        guard playable, duration.seconds.isFinite, duration.seconds > 0 else {
            throw CompanionError.invalidArchive("\(url.lastPathComponent) is not playable audio.")
        }
        let titles = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierTitle)
        for item in titles {
            if let title = try await item.load(.stringValue),
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return title
            }
        }
        throw CompanionError.invalidArchive("\(url.lastPathComponent) has no Title metadata.")
    }

    /// Reads only a validated committed generation. Missing/corrupt audio produces a recoverable UI error.
    func load(mapping: TrackMapping) throws -> SavedLibrary? {
        let pointer = root.appendingPathComponent("Current.json")
        guard FileManager.default.fileExists(atPath: pointer.path) else {
            removeObsoleteGenerations(keeping: nil)
            return nil
        }
        let saved = try JSONDecoder().decode(SavedLibrary.self, from: Data(contentsOf: pointer))
        guard UUID(uuidString: saved.directory) != nil, saved.manifest.schemaVersion == 1,
              !saved.manifest.tracks.isEmpty else {
            throw CompanionError.invalidLibrary("The library manifest is invalid. Import the ZIP again.")
        }
        _ = try Catalog.groups(mapping: mapping, imported: saved.manifest.tracks)
        for track in saved.manifest.tracks {
            guard Catalog.trackID(filename: track.filename) == track.id else {
                throw CompanionError.invalidLibrary("An audio filename is invalid.")
            }
            let url = root.appendingPathComponent(saved.directory).appendingPathComponent(track.filename)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) > 0 else {
                throw CompanionError.invalidLibrary("Audio for track \(track.id) is missing or invalid.")
            }
        }
        removeObsoleteGenerations(keeping: saved)
        return saved
    }

    /// Extracts matching MP3s into a fresh generation, then atomically publishes the manifest.
    /// A failed or cancelled import cannot overwrite the user's existing library.
    func importZIP(
        at source: URL,
        mapping: TrackMapping,
        progress: @Sendable (Int, Int) async -> Void
    ) async throws -> SavedLibrary {
        guard !importInProgress else {
            throw CompanionError.invalidArchive("Another import is already in progress.")
        }
        importInProgress = true
        defer { importInProgress = false }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var excludedRoot = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedRoot.setResourceValues(values)

        let archive = try Archive(url: source, accessMode: .read)
        let mappedIDs = Set(mapping.tracks.map(\.id))
        var candidates: [(Entry, Int, String)] = []
        var seen = Set<Int>()
        var declaredBytes: UInt64 = 0
        for entry in archive {
            try Task.checkCancellation()
            let components = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            if components.contains("__MACOSX") { continue }
            guard let filename = components.last.map(String.init),
                  let id = Catalog.trackID(filename: filename), id != 1 else { continue }
            guard entry.type == .file, !entry.path.hasPrefix("/"), !entry.path.contains("\\"),
                  !components.contains("..") else {
                throw CompanionError.invalidArchive("Unsafe audio entry: \(filename).")
            }
            guard seen.insert(id).inserted else {
                throw CompanionError.invalidArchive("More than one MP3 has track ID \(id).")
            }
            guard mappedIDs.contains(id) else {
                throw CompanionError.invalidArchive("Track \(id) is not in the editable metadata mapping.")
            }
            guard entry.uncompressedSize > 0, entry.uncompressedSize <= maximumTrackBytes,
                  entry.uncompressedSize <= maximumTotalBytes - declaredBytes else {
                throw CompanionError.invalidArchive("Audio exceeds the import size limit.")
            }
            declaredBytes += entry.uncompressedSize
            candidates.append((entry, id, filename))
        }
        guard !candidates.isEmpty else {
            throw CompanionError.invalidArchive("No matching individual MP3 tracks were found.")
        }
        candidates.sort { $0.1 < $1.1 }
        let generation = UUID().uuidString
        let directory = root.appendingPathComponent(generation, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            var tracks: [ImportedTrack] = []
            var totalBytes: UInt64 = 0
            for (entry, id, filename) in candidates {
                try Task.checkCancellation()
                let destination = directory.appendingPathComponent(filename)
                guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let handle = try FileHandle(forWritingTo: destination)
                do {
                    var written: UInt64 = 0
                    let checksum = try archive.extract(entry) { data in
                        try Task.checkCancellation()
                        let count = UInt64(data.count)
                        guard count <= self.maximumTrackBytes - written,
                              count <= self.maximumTotalBytes - totalBytes else {
                            throw CompanionError.invalidArchive("Decompressed audio exceeds the import size limit.")
                        }
                        try handle.write(contentsOf: data)
                        written += count
                        totalBytes += count
                    }
                    try handle.close()
                    guard checksum == entry.checksum, written == entry.uncompressedSize else {
                        throw CompanionError.invalidArchive("Track \(id) failed its integrity check.")
                    }
                } catch {
                    do { try handle.close() } catch {
                        logger.error("Closing extraction file failed: \(error.localizedDescription)")
                    }
                    throw error
                }
                let title = try await readTitle(destination)
                guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CompanionError.invalidArchive("Track \(id) has no Title metadata.")
                }
                tracks.append(ImportedTrack(id: id, filename: filename, metadataTitle: title))
                await progress(tracks.count, candidates.count)
            }
            try Task.checkCancellation()
            let saved = SavedLibrary(
                directory: generation, manifest: LibraryManifest(schemaVersion: 1, tracks: tracks)
            )
            let data = try JSONEncoder().encode(saved)
            try data.write(to: root.appendingPathComponent("Current.json"), options: .atomic)
            return saved
        } catch {
            do { try FileManager.default.removeItem(at: directory) } catch {
                logger.error("Removing incomplete import failed: \(error.localizedDescription)")
            }
            throw error
        }
    }

    /// Removes only obsolete app-created generations after playback has released the previous library.
    func removeObsoleteGenerations(keeping saved: SavedLibrary?) {
        guard !importInProgress, FileManager.default.fileExists(atPath: root.path) else { return }
        do {
            let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            for child in children where child.lastPathComponent != saved?.directory {
                guard UUID(uuidString: child.lastPathComponent) != nil else { continue }
                try FileManager.default.removeItem(at: child)
            }
        } catch {
            logger.error("Removing obsolete library generations failed: \(error.localizedDescription)")
        }
    }
}
