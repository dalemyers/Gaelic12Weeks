import AVFoundation
import XCTest
@testable import GaelicCompanion

@MainActor
final class AudioPlayerTests: XCTestCase {
    /// Generates an original silent WAV fixture for deterministic playback tests.
    private func makeAudio(in directory: URL, seconds: UInt32 = 1) throws -> URL {
        let url = directory.appendingPathComponent("silence.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let frames = 8_000 * seconds
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData)
        samples[0].initialize(repeating: 0, count: Int(frames))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    /// Playback start and pause do not mark completion; a successful finish does so exactly once.
    func testCompletionOnlyOnSuccessfulFinish() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeAudio(in: directory)
        let track = try XCTUnwrap(TrackMapping.load().tracks.first)
        let player = AudioPlayer()
        defer { player.stop() }
        let completion = expectation(description: "Successful recording completion")
        completion.assertForOverFulfill = true
        var finishedIDs: [Int] = []
        player.onTrackFinished = { id in
            finishedIDs.append(id)
            completion.fulfill()
        }
        await player.play(LibraryTrack(
            mapping: track, imported: ImportedTrack(id: track.id, filename: "123_002.mp3", metadataTitle: track.title)
        ), at: url)
        XCTAssertNil(player.errorMessage)
        XCTAssertTrue(player.isPlaying)
        XCTAssertTrue(finishedIDs.isEmpty)
        player.pause()
        XCTAssertTrue(finishedIDs.isEmpty)
        XCTAssertFalse(player.isPlaying)
        player.seek(to: -50)
        XCTAssertEqual(player.position, 0)
        await player.toggle()
        await fulfillment(of: [completion], timeout: 5)
        XCTAssertEqual(finishedIDs, [2])
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.position, player.duration)
    }

    /// Broken audio must show an error and must not mark the track listened.
    func testPlaybackFailureDoesNotComplete() async throws {
        let track = try XCTUnwrap(TrackMapping.load().tracks.first)
        let player = AudioPlayer()
        var finishedIDs: [Int] = []
        player.onTrackFinished = { finishedIDs.append($0) }
        await player.play(LibraryTrack(
            mapping: track, imported: ImportedTrack(id: track.id, filename: "123_002.mp3", metadataTitle: track.title)
        ), at: URL(fileURLWithPath: "/nonexistent-audio-\(UUID().uuidString).mp3"))
        XCTAssertNotNil(player.errorMessage)
        XCTAssertFalse(player.isPlaying)
        XCTAssertTrue(finishedIDs.isEmpty)
    }

    /// The built application must actually declare background audio, not merely a project setting.
    func testBackgroundAudioCapability() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String], ["audio"])
    }

    /// Failed replacement and callbacks from an unrelated/old player cannot alter the active recording.
    func testFailedReplacementAndStaleCallbacksPreservePlayback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeAudio(in: directory)
        let mapping = try TrackMapping.load()
        let first = LibraryTrack(
            mapping: mapping.tracks[0],
            imported: ImportedTrack(id: 2, filename: "123_002.mp3", metadataTitle: "First")
        )
        let second = LibraryTrack(
            mapping: mapping.tracks[1],
            imported: ImportedTrack(id: 3, filename: "123_003.mp3", metadataTitle: "Second")
        )
        let player = AudioPlayer()
        defer { player.stop() }
        var finished: [Int] = []
        player.onTrackFinished = { finished.append($0) }
        await player.play(first, at: url)
        await player.play(second, at: directory.appendingPathComponent("missing.mp3"))
        XCTAssertEqual(player.currentTrack?.id, 2)
        XCTAssertTrue(player.isPlaying)
        XCTAssertNotNil(player.errorMessage)
        player.errorMessage = nil
        let stale = try AVAudioPlayer(contentsOf: url)
        player.handleCompletion(from: ObjectIdentifier(stale), successfully: true)
        player.handleDecodeError(from: ObjectIdentifier(stale), message: "Stale failure")
        XCTAssertTrue(finished.isEmpty)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.currentTrack?.id, 2)
        XCTAssertNil(player.errorMessage)
        player.stop()
        player.handleCompletion(from: ObjectIdentifier(stale), successfully: true)
        player.handleDecodeError(from: ObjectIdentifier(stale), message: "Stale failure")
        XCTAssertTrue(finished.isEmpty)
        XCTAssertNil(player.currentTrack)
        XCTAssertNil(player.errorMessage)
    }

    /// Stopping during a suspended activation prevents that earlier request from starting audio later.
    func testStopInvalidatesPendingPlayback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeAudio(in: directory)
        let began = expectation(description: "Activation requested")
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let controller = AudioSessionController { active in
            if active {
                began.fulfill()
                for await _ in stream { break }
            }
        }
        let player = AudioPlayer(session: controller)
        let entry = try XCTUnwrap(TrackMapping.load().tracks.first)
        let track = LibraryTrack(
            mapping: entry, imported: ImportedTrack(id: entry.id, filename: "123_002.mp3", metadataTitle: entry.title)
        )
        let pending = Task { await player.play(track, at: url) }
        await fulfillment(of: [began], timeout: 5)
        XCTAssertTrue(player.isPreparing)
        player.stop()
        continuation.yield()
        continuation.finish()
        await pending.value
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isPreparing)
        XCTAssertNil(player.currentTrack)
        XCTAssertNil(player.errorMessage)
    }

    /// Mini-player skips move exactly five seconds, clamp at both ends and do not mark a track listened.
    func testFiveSecondSkips() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeAudio(in: directory, seconds: 20)
        let entry = try XCTUnwrap(TrackMapping.load().tracks.first)
        let player = AudioPlayer()
        defer { player.stop() }
        var completed = false
        player.onTrackFinished = { _ in completed = true }
        player.skipBackward()
        player.skipForward()
        XCTAssertEqual(player.position, 0)
        await player.play(LibraryTrack(
            mapping: entry, imported: ImportedTrack(id: entry.id, filename: "123_002.mp3", metadataTitle: entry.title)
        ), at: url)
        XCTAssertNil(player.errorMessage)
        player.pause()
        player.seek(to: 10)
        player.skipBackward()
        XCTAssertEqual(player.position, 5)
        player.skipForward()
        XCTAssertEqual(player.position, 10)
        player.seek(to: 2)
        player.skipBackward()
        XCTAssertEqual(player.position, 0)
        player.seek(to: 18)
        player.skipForward()
        XCTAssertEqual(player.position, 20, accuracy: 0.001)
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(completed)
    }
}
