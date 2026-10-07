import AVFoundation
import Combine
import MediaPlayer
import Observation

@MainActor
@Observable
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var currentTrack: LibraryTrack?
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isPreparing = false
    var errorMessage: String?
    @ObservationIgnored var onTrackFinished: ((Int) -> Void)?

    @ObservationIgnored private var audio: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var notifications = Set<AnyCancellable>()
    @ObservationIgnored private var remoteTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private let session: AudioSessionController

    /// Registers system playback controls and audio-session interruption handling.
    init(session: AudioSessionController = .shared) {
        self.session = session
        super.init()
        observeSession()
        registerRemoteCommands()
    }

    /// Starts an imported track; decoding/session failures are shown to the user.
    func play(_ track: LibraryTrack, at url: URL) async {
        revision += 1
        let request = revision
        isPreparing = true
        defer { if revision == request { isPreparing = false } }
        do {
            try await session.enqueue(active: true).value
            guard revision == request else { return }
            let next = try await Self.prepareAudio(at: url)
            guard revision == request else {
                if audio == nil && !isPreparing { stop() }
                return
            }
            next.delegate = self
            guard next.play() else { throw PlaybackError.cannotPlay }
            audio?.stop()
            audio = next
            currentTrack = track
            duration = next.duration
            position = 0
            isPlaying = true
            startTicker()
            updateNowPlaying()
        } catch {
            guard revision == request else { return }
            if audio == nil { stop() }
            errorMessage = error.localizedDescription
        }
    }

    /// Pauses or resumes the selected recording, restarting a completed track from the beginning.
    func toggle() async {
        guard let audio else { return }
        if isPlaying {
            pause()
            return
        }
        revision += 1
        let request = revision
        isPreparing = true
        defer { if revision == request { isPreparing = false } }
        do {
            try await session.enqueue(active: true).value
            guard revision == request else { return }
            if position >= duration { audio.currentTime = 0 }
            guard audio.play() else { throw PlaybackError.cannotPlay }
            isPlaying = true
            position = audio.currentTime
            startTicker()
            updateNowPlaying()
        } catch {
            guard revision == request else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Pauses playback without discarding the selected track or its position.
    func pause() {
        revision += 1
        isPreparing = false
        resumeAfterInterruption = false
        audio?.pause()
        isPlaying = false
        ticker?.cancel()
        position = audio?.currentTime ?? position
        updateNowPlaying()
    }

    /// Seeks within the recording, clamping remote and UI requests to its duration.
    func seek(to time: TimeInterval) {
        guard let audio, time.isFinite else { return }
        position = min(max(0, time), duration)
        audio.currentTime = position
        updateNowPlaying()
    }

    /// Releases the current audio before a replacement library removes old files.
    func stop() {
        revision += 1
        let request = revision
        isPreparing = false
        resumeAfterInterruption = false
        ticker?.cancel()
        audio?.stop()
        audio = nil
        currentTrack = nil
        isPlaying = false
        position = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        let deactivation = session.enqueue(active: false)
        Task { [weak self] in
            do { try await deactivation.value } catch {
                guard let self, self.revision == request else { return }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Refreshes elapsed time while playback is active without retaining the owner between ticks.
    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.position = self?.audio?.currentTime ?? 0
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            }
        }
    }

    /// Transfers a freshly prepared player to MainActor; preparation can implicitly activate its audio session.
    nonisolated private static func prepareAudio(at url: URL) async throws -> sending AVAudioPlayer {
        let player = try AVAudioPlayer(contentsOf: url)
        guard player.prepareToPlay() else { throw PlaybackError.cannotPlay }
        return player
    }

    /// Publishes track identity and elapsed time to the lock screen.
    private func updateNowPlaying() {
        guard let currentTrack else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: currentTrack.mapping.title,
            MPMediaItemPropertyAlbumTitle: currentTrack.mapping.lesson.map { "Lesson \($0)" } ?? "Bonus audio",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }

    /// Pauses on headphone removal and resumes only when an interruption explicitly permits it.
    private func observeSession() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self,
                          let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                          let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                    if type == .began {
                        let wasPlaying = self.isPlaying
                        self.pause()
                        self.resumeAfterInterruption = wasPlaying
                    } else {
                        let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
                        if self.resumeAfterInterruption,
                           AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume),
                           !self.isPlaying {
                            let request = self.revision
                            Task {
                                guard self.revision == request else { return }
                                await self.toggle()
                            }
                        }
                        self.resumeAfterInterruption = false
                    }
                }
            }.store(in: &notifications)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                MainActor.assumeIsolated { self?.pause() }
            }.store(in: &notifications)
    }

    /// Installs lock-screen play, pause and seek handlers on the main actor.
    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        let play = center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if let self, !self.isPlaying { await self.toggle() } }
            return .success
        }
        let pause = center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        let seek = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            Task { @MainActor in self?.seek(to: time) }
            return .success
        }
        remoteTargets = [(center.playCommand, play), (center.pauseCommand, pause),
                         (center.changePlaybackPositionCommand, seek)]
    }

    /// Handles natural completion without automatically starting unrelated lesson content.
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            self?.handleCompletion(from: identity, successfully: flag)
        }
    }

    /// Surfaces asynchronous decoder errors instead of leaving the UI in a playing state.
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let message = error?.localizedDescription ?? PlaybackError.cannotPlay.localizedDescription
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            self?.handleDecodeError(from: identity, message: message)
        }
    }

    /// Discards completion callbacks queued by an old player after a track/library replacement.
    func handleCompletion(from identity: ObjectIdentifier, successfully flag: Bool) {
        guard let audio, ObjectIdentifier(audio) == identity else { return }
        isPlaying = false
        ticker?.cancel()
        position = duration
        updateNowPlaying()
        if flag, let id = currentTrack?.id {
            onTrackFinished?(id)
        } else {
            errorMessage = PlaybackError.cannotPlay.localizedDescription
        }
    }

    /// Ignores decoder errors belonging to recordings that are no longer selected.
    func handleDecodeError(from identity: ObjectIdentifier, message: String) {
        guard let audio, ObjectIdentifier(audio) == identity else { return }
        pause()
        errorMessage = message
    }
}

private enum PlaybackError: LocalizedError {
    case cannotPlay
    var errorDescription: String? { "This recording could not be played. Try importing the ZIP again." }
}
