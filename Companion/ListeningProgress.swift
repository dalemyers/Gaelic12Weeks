import Foundation
import Observation

@MainActor
@Observable
final class ListeningProgress {
    private(set) var listenedIDs = Set<Int>()
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var hasLoaded = false

    private struct Snapshot: Codable {
        let schemaVersion: Int
        let listenedIDs: Set<Int>
    }

    /// Keeps completion separate from imported audio so replacing a ZIP preserves listened status.
    init(url: URL) {
        self.url = url
    }

    /// Restores completion, rejecting corrupt data rather than silently overwriting it.
    func load() throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            listenedIDs = []
            hasLoaded = true
            return
        }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        guard snapshot.schemaVersion == 1, snapshot.listenedIDs.allSatisfy({ (2...999).contains($0) }) else {
            throw CompanionError.invalidLibrary("Listening progress is invalid. Reset progress in About & download.")
        }
        listenedIDs = snapshot.listenedIDs
        hasLoaded = true
    }

    /// Returns true only when every mapped recording is complete; an empty group or section is not complete.
    func isListened(_ ids: Set<Int>) -> Bool {
        !ids.isEmpty && ids.isSubset(of: listenedIDs)
    }

    /// Atomically persists a manual or automatic update before publishing it to the UI.
    func setListened(_ listened: Bool, ids: Set<Int>) throws {
        guard hasLoaded else {
            throw CompanionError.invalidLibrary("Listening progress could not be loaded. Reset progress in About & download.")
        }
        guard ids.allSatisfy({ (2...999).contains($0) }) else {
            throw CompanionError.invalidLibrary("Cannot save progress for invalid track IDs.")
        }
        let updated = listened ? listenedIDs.union(ids) : listenedIDs.subtracting(ids)
        try persist(updated)
        listenedIDs = updated
    }

    /// Explicitly resets saved progress, including recovery from a corrupt progress file.
    func reset() throws {
        try persist([])
        listenedIDs = []
        hasLoaded = true
    }

    /// Writes only progress metadata, never audio, to a separate atomic snapshot.
    private func persist(_ ids: Set<Int>) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Snapshot(schemaVersion: 1, listenedIDs: ids))
        try data.write(to: url, options: .atomic)
    }
}
