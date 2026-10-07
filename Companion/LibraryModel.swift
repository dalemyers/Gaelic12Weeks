import Foundation
import Observation

@MainActor
@Observable
final class LibraryModel {
    static let appName = "Unofficial Companion to 'Scottish Gaelic In 12 Weeks'"
    static let downloadURL = URL(string: "https://birlinn.co.uk/scottish-gaelic-in-12-weeks-audio-download/")!

    private(set) var mapping: TrackMapping?
    private(set) var saved: SavedLibrary?
    private(set) var groups: [LibraryGroup] = []
    private(set) var isLoading = true
    private(set) var isImporting = false
    private(set) var completed = 0
    private(set) var total = 0
    var errorMessage: String?
    let player = AudioPlayer()
    let progress: ListeningProgress

    @ObservationIgnored private let root: URL
    @ObservationIgnored private let repository: LibraryRepository
    @ObservationIgnored private var importTask: Task<Void, Never>?

    var importedCount: Int { saved?.manifest.tracks.count ?? 0 }
    var expectedCount: Int { mapping?.tracks.count ?? 0 }
    var hasProvisionalMapping: Bool { groups.flatMap(\.tracks).contains { $0.mapping.needsReview } }

    /// Stores user-imported recordings privately; no audio is included in the application bundle.
    init() {
        root = URL.applicationSupportDirectory.appendingPathComponent("ImportedLibrary", isDirectory: true)
        repository = LibraryRepository(root: root)
        progress = ListeningProgress(url: URL.applicationSupportDirectory.appendingPathComponent("ListeningProgress.json"))
        player.onTrackFinished = { [weak self] id in self?.setListened(true, ids: [id]) }
    }

    /// Loads the editable catalog and previous import, surfacing corruption without hiding the import controls.
    func load() async {
        defer { isLoading = false }
        do {
            try progress.load()
        } catch {
            errorMessage = error.localizedDescription
        }
        do {
            let mapping = try TrackMapping.load()
            self.mapping = mapping
            if let saved = try await repository.load(mapping: mapping) {
                self.groups = try Catalog.groups(mapping: mapping, imported: saved.manifest.tracks)
                self.saved = saved
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Starts one cancellable import and publishes the new library only after the repository commits it.
    func importZIP(_ url: URL) {
        guard !isImporting, let mapping else { return }
        isImporting = true
        completed = 0
        total = 0
        importTask = Task {
            defer {
                isImporting = false
                importTask = nil
            }
            do {
                let imported = try await repository.importZIP(at: url, mapping: mapping) { [weak self] done, total in
                    await self?.updateProgress(completed: done, total: total)
                }
                let groups = try Catalog.groups(mapping: mapping, imported: imported.manifest.tracks)
                player.stop()
                self.saved = imported
                self.groups = groups
                await repository.removeObsoleteGenerations(keeping: imported)
            } catch is CancellationError {
                // Cancellation is an explicit user action; the previous library remains available.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Cancels extraction; the repository removes the incomplete generation.
    func cancelImport() {
        importTask?.cancel()
    }

    /// Plays a track from the currently committed generation.
    func play(_ track: LibraryTrack) {
        guard let saved else { return }
        let url = root.appendingPathComponent(saved.directory).appendingPathComponent(track.imported.filename)
        Task {
            guard self.saved?.directory == saved.directory else { return }
            await player.play(track, at: url)
        }
    }

    /// Uses the full mapped group or section, not just imported tracks, when calculating completion.
    func trackIDs(for group: LibraryGroup, section: Int? = nil) -> Set<Int> {
        mapping?.trackIDs(for: group, section: section) ?? []
    }

    /// Persists listened/unlistened state for both manual toggles and successful playback completion.
    func setListened(_ listened: Bool, ids: Set<Int>) {
        do { try progress.setListened(listened, ids: ids) } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Clears progress only following an explicit confirmation in the UI.
    func resetProgress() {
        do { try progress.reset() } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Bridges actor-isolated extraction progress to the observable UI.
    private func updateProgress(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }
}
