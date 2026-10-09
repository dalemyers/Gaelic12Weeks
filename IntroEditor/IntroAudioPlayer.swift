import AVFoundation
import Observation

@MainActor
@Observable
final class IntroAudioPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    private(set) var isPlaying = false
    private(set) var isLoaded = false
    var errorMessage: String?
    @ObservationIgnored private var audio: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    deinit { ticker?.cancel() }

    func load(url: URL) throws {
        reset()
        let audio = try AVAudioPlayer(contentsOf: url)
        guard audio.duration.isFinite, audio.duration > 0, audio.prepareToPlay() else {
            throw IntroEditorError.invalid("This recording could not be prepared for playback.")
        }
        audio.delegate = self
        self.audio = audio
        duration = audio.duration
        isLoaded = true
    }

    func reset() {
        ticker?.cancel()
        ticker = nil
        audio?.stop()
        audio = nil
        position = 0
        duration = 0
        isPlaying = false
        isLoaded = false
        errorMessage = nil
    }

    func pause() {
        if isPlaying { position = audio?.currentTime ?? position }
        audio?.pause()
        isPlaying = false
        ticker?.cancel()
        ticker = nil
    }

    func play() {
        guard let audio else { return }
        if position >= duration { seek(to: 0) }
        guard audio.play() else {
            errorMessage = "Playback could not start. Try reopening the audio folder."
            return
        }
        isPlaying = true
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
                guard let self else { return }
                if let audio = self.audio, audio.isPlaying {
                    self.position = min(audio.currentTime, self.duration)
                }
            }
        }
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, let audio else { return }
        let target = min(max(0, seconds), duration)
        if target >= duration { pause() }
        audio.currentTime = target
        position = target
    }

    func nudge(by seconds: Double) {
        pause()
        seek(to: position + seconds)
    }

    /// Capture the audio clock itself, not the last display refresh.
    func capturePosition() -> Double {
        if isPlaying { position = min(audio?.currentTime ?? position, duration) }
        return position
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let audio = self.audio, ObjectIdentifier(audio) == identity else { return }
            self.ticker?.cancel()
            self.ticker = nil
            self.isPlaying = false
            self.position = self.duration
            if !flag { self.errorMessage = "Playback stopped before the recording finished successfully." }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let identity = ObjectIdentifier(player)
        let message = error?.localizedDescription ?? "The recording could not be decoded."
        Task { @MainActor [weak self] in
            guard let self, let audio = self.audio, ObjectIdentifier(audio) == identity else { return }
            self.pause()
            self.errorMessage = message
        }
    }
}
