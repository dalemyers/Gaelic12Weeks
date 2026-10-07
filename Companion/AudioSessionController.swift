import AVFoundation

@MainActor
final class AudioSessionController {
    static let shared = AudioSessionController()
    private var pending: Task<Void, Error>?
    private let operation: @Sendable (Bool) async throws -> Void

    /// Allows tests to suspend session transitions without using timing-dependent delays.
    init(operation: @escaping @Sendable (Bool) async throws -> Void = AudioSessionController.setActive) {
        self.operation = operation
    }

    /// Serializes activation and deactivation off the UI thread, preserving request order across players.
    func enqueue(active: Bool) -> Task<Void, Error> {
        let previous = pending
        let operation = operation
        let task = Task.detached(priority: .userInitiated) {
            // Each caller handles its own error; later transitions must still run after a failed predecessor.
            if let previous { _ = await previous.result }
            try await operation(active)
        }
        pending = task
        return task
    }

    /// Configures spoken playback only when needed and performs blocking session operations off-main.
    nonisolated private static func setActive(_ active: Bool) async throws {
        let session = AVAudioSession.sharedInstance()
        guard active else {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        if session.category != .playback || session.mode != .spokenAudio {
            try session.setCategory(.playback, mode: .spokenAudio)
        }
        try session.setActive(true)
    }
}
