import AVFoundation
import MediaPlayer
import XCTest
@testable import GaelicCompanion

@MainActor
final class AudioPlayerTests: XCTestCase {
    private func track(introEnd: Double? = nil) -> LibraryTrack {
        LibraryTrack(
            mapping: MappedTrack(
                id: 2, lesson: 1, section: 1, subsection: nil, group: .lesson,
                title: "Synthetic intro recording", needsReview: false, introEndSeconds: introEnd
            ),
            imported: ImportedTrack(id: 2, filename: "123_002.mp3", metadataTitle: "Synthetic intro recording")
        )
    }

    func testIntroSkippingDefaultsOffAndPublishesOriginalTimeline() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeAudio(in: directory, seconds: 20)
        let player = AudioPlayer()
        defer { player.stop() }
        XCTAssertFalse(player.skipSpokenIntroductions)
        await player.play(track(introEnd: 4.25), at: url)
        XCTAssertEqual(player.position, 0, accuracy: 0.1)
        player.skipSpokenIntroductions = true
        await player.play(track(introEnd: 4.25), at: url)
        XCTAssertEqual(player.position, 4.25, accuracy: 0.1)
        XCTAssertEqual(player.duration, 20, accuracy: 0.001)
        let info = try XCTUnwrap(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        XCTAssertEqual(try XCTUnwrap(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double), 4.25, accuracy: 0.1)
        XCTAssertEqual(info[MPMediaItemPropertyPlaybackDuration] as? Double, 20)
        XCTAssertNil(player.errorMessage)
    }

    func testIntroSkippingLeavesResumeAndBackwardSeekingUnchanged() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeAudio(in: directory, seconds: 20)
        let player = AudioPlayer()
        defer { player.stop() }
        var completed = false
        player.onTrackFinished = { _ in completed = true }
        player.skipSpokenIntroductions = true
        await player.play(track(introEnd: 6), at: url)
        player.pause()
        player.seek(to: 6)
        player.skipBackward()
        XCTAssertEqual(player.position, 1, accuracy: 0.001)
        await player.toggle()
        XCTAssertEqual(player.position, 1, accuracy: 0.1, "Resuming inside an intro must not jump forward.")
        player.pause()
        player.seek(to: 0)
        await player.toggle()
        XCTAssertEqual(player.position, 0, accuracy: 0.1)
        player.pause()
        player.seek(to: 10)
        player.skipSpokenIntroductions = false
        player.skipSpokenIntroductions = true
        XCTAssertEqual(player.position, 10)
        await player.toggle()
        XCTAssertEqual(player.position, 10, accuracy: 0.1)
        XCTAssertFalse(completed)
    }

    func testReplayUsesCurrentSettingAndReviewAlwaysStartsAtZero() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeAudio(in: directory, seconds: 1)
        let player = AudioPlayer()
        defer { player.stop() }
        player.skipSpokenIntroductions = true
        let finished = expectation(description: "Content after intro completed")
        player.onTrackFinished = { _ in finished.fulfill() }
        await player.play(track(introEnd: 0.6), at: url)
        await fulfillment(of: [finished], timeout: 5)
        player.onTrackFinished = nil
        XCTAssertEqual(player.position, player.duration)
        player.pause()
        XCTAssertEqual(player.position, player.duration, "Redundant remote pauses must not erase completed state.")
        await player.toggle()
        XCTAssertEqual(player.position, 0.6, accuracy: 0.1)
        player.pause()
        player.seek(to: player.duration)
        player.skipSpokenIntroductions = false
        await player.toggle()
        XCTAssertEqual(player.position, 0, accuracy: 0.1)
        player.skipSpokenIntroductions = true
        await player.play(track(introEnd: 0.6), at: url, allowingIntroSkipping: false)
        XCTAssertEqual(player.position, 0, accuracy: 0.1)
        player.pause()
        player.seek(to: player.duration)
        await player.toggle()
        XCTAssertEqual(player.position, 0, accuracy: 0.1, "Review replay must also include the intro.")
        await player.play(track(introEnd: 0.6), at: url)
        XCTAssertEqual(player.position, 0.6, accuracy: 0.1, "Normal listening after review restores skipping.")
    }

    func testAbsentZeroAndInvalidIntroMarksNeverSkipOrComplete() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeAudio(in: directory, seconds: 20)
        let player = AudioPlayer()
        defer { player.stop() }
        player.skipSpokenIntroductions = true
        var completed = false
        player.onTrackFinished = { _ in completed = true }
        let marks: [Double?] = [nil, 0, -1, 20, 21, .infinity, .nan]
        for mark in marks {
            await player.play(track(introEnd: mark), at: url)
            XCTAssertTrue(player.isPlaying)
            XCTAssertEqual(player.position, 0, accuracy: 0.1)
            XCTAssertFalse(completed)
        }
        XCTAssertNil(player.errorMessage)
    }

    func testSkipPreferencePersistsWithoutMovingCurrentPlayback() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let domain = "IntroPreferenceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let model = LibraryModel(applicationSupportURL: directory, userDefaults: defaults)
        defer { model.player.stop() }
        XCTAssertFalse(model.skipSpokenIntroductions)
        let url = try makeAudio(in: directory, seconds: 20)
        await model.player.play(track(introEnd: 6), at: url)
        model.player.pause()
        model.player.seek(to: 2)
        model.skipSpokenIntroductions = true
        XCTAssertEqual(model.player.position, 2)
        XCTAssertFalse(model.player.isPlaying)
        let restored = LibraryModel(applicationSupportURL: directory, userDefaults: defaults)
        defer { restored.player.stop() }
        XCTAssertTrue(restored.skipSpokenIntroductions)
        XCTAssertTrue(restored.player.skipSpokenIntroductions)
        restored.skipSpokenIntroductions = false
        let disabled = LibraryModel(applicationSupportURL: directory, userDefaults: defaults)
        defer { disabled.player.stop() }
        XCTAssertFalse(disabled.skipSpokenIntroductions)
    }

    func testPreferenceChangeDuringPreparationAppliesWhenPlaybackStarts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeAudio(in: directory, seconds: 20)
        let began = expectation(description: "Activation requested")
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let controller = AudioSessionController { active in
            if active {
                began.fulfill()
                for await _ in stream { break }
            }
        }
        let player = AudioPlayer(session: controller)
        defer { player.stop() }
        let entry = track(introEnd: 6)
        let pending = Task { await player.play(entry, at: url) }
        await fulfillment(of: [began], timeout: 5)
        player.skipSpokenIntroductions = true
        continuation.yield()
        continuation.finish()
        await pending.value
        XCTAssertEqual(player.position, 6, accuracy: 0.1)
        XCTAssertNil(player.errorMessage)
    }

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
        XCTAssertEqual(Bundle.main.bundleIdentifier, "io.myers.GaelicCompanion")
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
