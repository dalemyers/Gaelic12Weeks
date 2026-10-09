import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class IntroEditorModel {
    private(set) var tracks: [MappedTrack] = []
    private(set) var selectedID: Int?
    private(set) var metadataURL: URL?
    private(set) var audioFolderURL: URL?
    private(set) var audioFiles: [Int: URL] = [:]
    private(set) var waveform: AudioWaveform?
    private(set) var isLoadingWaveform = false
    private(set) var status = "Choose TrackMapping.json and your extracted audio folder to begin."
    var errorMessage: String?
    let player = IntroAudioPlayer()
    @ObservationIgnored private var store: IntroMetadataStore?
    @ObservationIgnored private var waveformTask: Task<Void, Never>?
    @ObservationIgnored private var selectionRevision = UUID()

    var selectedTrack: MappedTrack? { tracks.first { $0.id == selectedID } }
    var reviewedCount: Int { tracks.filter { $0.introEndSeconds != nil }.count }
    var backupURL: URL? { store?.backupURL }
    var canSave: Bool { store != nil && player.isLoaded }

    deinit { waveformTask?.cancel() }

    func chooseMetadata() {
        let panel = NSOpenPanel()
        panel.title = "Choose the metadata file to edit directly"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { openMetadata(url: url) }
    }

    func chooseAudioFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose the folder containing the extracted MP3 recordings"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { openAudioFolder(url: url) }
    }

    func openMetadata(url: URL) {
        do {
            let store = try IntroMetadataStore(url: url)
            self.store = store
            metadataURL = url
            tracks = store.mapping.tracks.sorted { $0.id < $1.id }
            select(id: tracks.first?.id)
            status = "Metadata loaded. Marks are saved directly to \(url.lastPathComponent)."
        } catch { errorMessage = error.localizedDescription }
    }

    func reloadMetadata() {
        do {
            guard let store else { return }
            try store.reload()
            tracks = store.mapping.tracks.sorted { $0.id < $1.id }
            select(id: tracks.contains { $0.id == selectedID } ? selectedID : tracks.first?.id)
            status = "Metadata reloaded from disk."
        } catch { errorMessage = error.localizedDescription }
    }

    func openAudioFolder(url: URL) {
        do {
            let files = try IntroAudioFiles.index(folder: url)
            audioFiles = files
            audioFolderURL = url
            select(id: selectedID)
            let missing = tracks.filter { files[$0.id] == nil }.count
            status = "\(files.count) audio files found. \(missing) mapped recordings missing."
        } catch { errorMessage = error.localizedDescription }
    }

    func select(id: Int?) {
        waveformTask?.cancel()
        selectionRevision = UUID()
        selectedID = id
        waveform = nil
        isLoadingWaveform = false
        player.reset()
        guard let id, let url = audioFiles[id] else { return }
        do { try player.load(url: url) } catch {
            errorMessage = error.localizedDescription
            return
        }
        let revision = selectionRevision
        isLoadingWaveform = true
        waveformTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { try AudioWaveform.load(url: url) }
            do {
                let waveform = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, let self, self.selectionRevision == revision else { return }
                self.waveform = waveform
                self.isLoadingWaveform = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self, self.selectionRevision == revision else { return }
                self.isLoadingWaveform = false
                self.errorMessage = "Waveform: \(error.localizedDescription)"
            }
        }
    }

    func adjacentID(offset: Int) -> Int? {
        guard let index = tracks.firstIndex(where: { $0.id == selectedID }),
              tracks.indices.contains(index + offset) else { return nil }
        return tracks[index + offset].id
    }

    func move(offset: Int) {
        if let id = adjacentID(offset: offset) { select(id: id) }
    }

    func mark(advance: Bool = false) {
        save(seconds: player.capturePosition(), advance: advance)
    }

    func save(seconds: Double?, advance: Bool = false) {
        guard let store, let selectedID else { return }
        do {
            try store.save(trackID: selectedID, seconds: seconds, duration: player.duration)
            tracks = store.mapping.tracks.sorted { $0.id < $1.id }
            status = seconds.map { "Saved track \(selectedID): intro ends at \(Self.time($0))." }
                ?? "Cleared track \(selectedID): unreviewed."
            if advance { move(offset: 1) }
        } catch { errorMessage = error.localizedDescription }
    }

    func previewMark(preroll: Double) {
        guard let mark = selectedTrack?.introEndSeconds, mark < player.duration else { return }
        player.seek(to: max(0, mark - preroll))
        player.play()
    }

    static func time(_ seconds: Double) -> String {
        String(
            format: "%02.0f:%06.3f", (seconds / 60).rounded(.down),
            seconds.truncatingRemainder(dividingBy: 60)
        )
    }

    static func location(_ track: MappedTrack) -> String {
        switch track.group {
        case .lesson:
            let lesson = "Lesson \(track.lesson ?? 0)"
            return track.section.map { "\(lesson) · Section \($0)\(track.subsection ?? "")" }
                ?? "\(lesson) · Conversation / other audio"
        case .appendices: return "Appendices"
        case .readingPractice: return "Reading Practice"
        }
    }

#if DEBUG
    static func preview() -> IntroEditorModel {
        let model = IntroEditorModel()
        model.tracks = [
            MappedTrack(
                id: 2, lesson: 1, section: 1, subsection: nil, group: .lesson,
                title: "Sample recording", needsReview: false, introEndSeconds: 3.25
            ),
            MappedTrack(
                id: 3, lesson: 1, section: nil, subsection: nil, group: .lesson,
                title: "Conversation", needsReview: false
            )
        ]
        model.selectedID = 2
        model.waveform = AudioWaveform(
            peaks: (0..<1_500).map { Float(abs(sin(Double($0) * 0.17)) * 0.7) },
            secondsPerPeak: 0.01, duration: 15
        )
        model.status = "Preview only. No files are opened or modified."
        return model
    }
#endif
}
