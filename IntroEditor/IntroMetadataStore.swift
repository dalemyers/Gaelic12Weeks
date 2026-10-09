import Foundation

enum IntroEditorError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}

@MainActor
final class IntroMetadataStore {
    let url: URL
    private(set) var mapping: TrackMapping
    private(set) var backupURL: URL?
    private var originalData: Data

    init(url: URL) throws {
        let data = try Data(contentsOf: url)
        mapping = try TrackMapping.decode(data)
        originalData = data
        self.url = url
    }

    func reload() throws {
        let data = try Data(contentsOf: url)
        let mapping = try TrackMapping.decode(data)
        originalData = data
        self.mapping = mapping
        backupURL = nil
    }

    /// Retains unknown JSON fields and refuses to overwrite edits made since the last load/save.
    func save(trackID: Int, seconds: Double?, duration: Double) throws {
        if let seconds {
            guard duration.isFinite, duration > 0, seconds.isFinite, seconds >= 0, seconds < duration else {
                throw IntroEditorError.invalid("The intro end must be within the recording, before its end.")
            }
        }
        guard var document = try JSONSerialization.jsonObject(with: originalData) as? [String: Any],
              var rows = document["tracks"] as? [[String: Any]],
              let index = rows.firstIndex(where: { ($0["id"] as? Int) == trackID }) else {
            throw IntroEditorError.invalid("Track \(trackID) is not in this metadata file.")
        }
        if let seconds {
            rows[index]["introEndSeconds"] = seconds
        } else {
            rows[index].removeValue(forKey: "introEndSeconds")
        }
        document["tracks"] = rows
        var data = try JSONSerialization.data(
            withJSONObject: document, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        let updatedMapping = try TrackMapping.decode(data)
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { destination in
            do {
                guard try Data(contentsOf: destination) == originalData else {
                    throw IntroEditorError.invalid(
                        "The metadata file changed outside this app. Reload Metadata before saving; nothing was overwritten."
                    )
                }
                if backupURL == nil {
                    let backup = destination.deletingLastPathComponent().appendingPathComponent(
                        "\(destination.lastPathComponent).backup-\(UUID().uuidString)"
                    )
                    try originalData.write(to: backup, options: .withoutOverwriting)
                    backupURL = backup
                }
                try data.write(to: destination, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
        originalData = data
        mapping = updatedMapping
    }
}

enum IntroAudioFiles {
    static func index(folder: URL) throws -> [Int: URL] {
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles], errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            throw IntroEditorError.invalid("The audio folder could not be read.")
        }
        var files: [Int: URL] = [:]
        for case let url as URL in enumerator {
            guard let id = Catalog.trackID(filename: url.lastPathComponent), id != 1,
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            guard files[id] == nil else {
                throw IntroEditorError.invalid(
                    "More than one audio file has track ID \(id). Choose a folder with one copy of each recording."
                )
            }
            files[id] = url
        }
        if let enumerationError { throw enumerationError }
        guard !files.isEmpty else {
            throw IntroEditorError.invalid("No numbered MP3 recordings were found in this folder.")
        }
        return files
    }
}
