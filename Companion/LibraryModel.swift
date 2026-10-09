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
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var importTask: Task<Void, Never>?
#if DEBUG
    private(set) var isReviewingMapping = false
    let mappingReviewURL: URL
#endif

    var importedCount: Int { saved?.manifest.tracks.count ?? 0 }
    var expectedCount: Int { mapping?.tracks.count ?? 0 }
    var hasProvisionalMapping: Bool { groups.flatMap(\.tracks).contains { $0.mapping.needsReview } }

    var skipSpokenIntroductions: Bool {
        get { player.skipSpokenIntroductions }
        set {
            userDefaults.set(newValue, forKey: "skipSpokenIntroductions")
            player.skipSpokenIntroductions = newValue
        }
    }

    /// Stores user-imported recordings privately; no audio is included in the application bundle.
    init(applicationSupportURL: URL = .applicationSupportDirectory, userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        root = applicationSupportURL.appendingPathComponent("ImportedLibrary", isDirectory: true)
        repository = LibraryRepository(root: root)
        progress = ListeningProgress(url: applicationSupportURL.appendingPathComponent("ListeningProgress.json"))
#if DEBUG
        mappingReviewURL = applicationSupportURL.appendingPathComponent("MappingReview.json")
#endif
        player.onTrackFinished = { [weak self] id in self?.recordPlaybackCompletion(id) }
        player.skipSpokenIntroductions = userDefaults.bool(forKey: "skipSpokenIntroductions")
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
#if DEBUG
        guard !isReviewingMapping else { return }
#endif
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
#if DEBUG
            guard !self.isReviewingMapping else { return }
#endif
            await player.play(track, at: url)
        }
    }

    /// Review listening is intentionally not learning progress.
    private func recordPlaybackCompletion(_ id: Int) {
#if DEBUG
        guard !isReviewingMapping else { return }
#endif
        setListened(true, ids: [id])
    }

#if DEBUG
    /// Supplies metadata-only canvas fixtures with fresh, isolated storage for every preview.
    static func preview(imported: Bool = true) -> LibraryModel {
        let directory = URL.temporaryDirectory
            .appendingPathComponent("GaelicCompanion-Preview-\(UUID().uuidString)", isDirectory: true)
        guard let defaults = UserDefaults(suiteName: directory.lastPathComponent) else {
            fatalError("Unable to create isolated preview preferences.")
        }
        let library = LibraryModel(applicationSupportURL: directory, userDefaults: defaults)
        do {
            let mapping = try TrackMapping.load()
            library.mapping = mapping
            try library.progress.load()
            if imported {
                let tracks = mapping.tracks.map {
                    ImportedTrack(
                        id: $0.id, filename: "1_\(String(format: "%03d", $0.id)).mp3", metadataTitle: $0.title
                    )
                }
                library.saved = SavedLibrary(
                    directory: UUID().uuidString, manifest: LibraryManifest(schemaVersion: 1, tracks: tracks)
                )
                library.groups = try Catalog.groups(mapping: mapping, imported: tracks)
            }
            library.isLoading = false
            return library
        } catch {
            fatalError("Unable to create preview library: \(error.localizedDescription)")
        }
    }

    /// Reuses the single shared player without allowing ordinary completion callbacks to mark review audio listened.
    func beginMappingReview() throws {
        guard !isImporting, mapping != nil else {
            throw MappingReviewError.invalid("Wait for the library to finish loading or importing.")
        }
        player.stop()
        isReviewingMapping = true
    }

    /// Invalidates pending playback before re-enabling normal listened-state updates.
    func endMappingReview() {
        player.stop()
        isReviewingMapping = false
    }

    /// Auditions an edited row using the original imported recording; no review audio is bundled or downloaded.
    func playForMappingReview(_ track: MappedTrack) async throws {
        guard isReviewingMapping, let saved,
              let imported = saved.manifest.tracks.first(where: { $0.id == track.id }) else {
            throw MappingReviewError.invalid("Import the audio for this track before playing it.")
        }
        let url = root.appendingPathComponent(saved.directory).appendingPathComponent(imported.filename)
        await player.play(LibraryTrack(mapping: track, imported: imported), at: url, allowingIntroSkipping: false)
    }
#endif

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
