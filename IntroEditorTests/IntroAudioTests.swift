import AVFoundation
import XCTest
@testable import GaelicIntroEditor

@MainActor
final class IntroAudioTests: XCTestCase {
    func testTimeFormattingHandlesLongManuallyEditedOffsets() {
        XCTAssertEqual(IntroEditorModel.time(65.5), "01:05.500")
        XCTAssertFalse(IntroEditorModel.time(1e100).isEmpty)
    }

    private func makeAudio(in folder: URL, duration: Double = 3, name: String = "sample.wav") throws -> URL {
        let url = folder.appendingPathComponent(name)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 2))
        let frames = AVAudioFrameCount((duration * format.sampleRate).rounded())
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channels = try XCTUnwrap(buffer.floatChannelData)
        for frame in 0..<Int(frames) {
            channels[0][frame] = frame < 800 ? 0 : 0.001
            channels[1][frame] = frame < 800 ? 0 : -0.002
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testWaveformIncludesSilenceAndBothChannels() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try makeAudio(in: folder, duration: 1.005)
        let waveform = try AudioWaveform.load(url: url)
        XCTAssertEqual(waveform.duration, 1.005, accuracy: 0.0001)
        XCTAssertEqual(waveform.secondsPerPeak, 0.01, accuracy: 0.0001)
        XCTAssertEqual(waveform.peaks.count, 101)
        XCTAssertTrue(waveform.peaks.prefix(10).allSatisfy { $0 == 0 })
        XCTAssertEqual(try XCTUnwrap(waveform.peaks.last), 0.002, accuracy: 0.0001)
    }

    func testWaveformRejectsInvalidAudioAndHonorsCancellation() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let invalid = folder.appendingPathComponent("invalid.mp3")
        try Data("not audio".utf8).write(to: invalid)
        XCTAssertThrowsError(try AudioWaveform.load(url: invalid))
        let url = try makeAudio(in: folder)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try AudioWaveform.load(url: url)
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled waveform must not finish.")
        } catch is CancellationError {
            // Expected cancellation.
        }
    }

    func testPlayerFineSeekingPlaybackAndEndClamping() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let player = IntroAudioPlayer()
        defer { player.reset() }
        try player.load(url: makeAudio(in: folder))
        XCTAssertTrue(player.isLoaded)
        XCTAssertEqual(player.duration, 3, accuracy: 0.01)
        player.seek(to: 1)
        player.nudge(by: 0.1)
        XCTAssertEqual(player.position, 1.1, accuracy: 0.0001)
        player.nudge(by: -0.1)
        XCTAssertEqual(player.position, 1, accuracy: 0.0001)
        player.play()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(player.isPlaying)
        XCTAssertGreaterThan(player.position, 1.1)
        player.nudge(by: 0.1)
        XCTAssertFalse(player.isPlaying)
        let paused = player.position
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(player.position, paused)
        player.seek(to: 10)
        XCTAssertEqual(player.position, 3)
        player.nudge(by: -0.1)
        XCTAssertEqual(player.position, 2.9, accuracy: 0.0001)
        player.seek(to: -10)
        XCTAssertEqual(player.position, 0)
        player.seek(to: .nan)
        XCTAssertEqual(player.position, 0)
        player.seek(to: 2.85)
        player.play()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.position, player.duration)
        player.play()
        XCTAssertTrue(player.isPlaying)
        XCTAssertLessThan(player.position, 0.1)
        player.reset()
        XCTAssertFalse(player.isLoaded)
    }

    func testModelMarksAdvancesReloadsAndKeepsWaveformSelectionConsistent() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let audio = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "synthetic", withExtension: "mp3"))
        try FileManager.default.copyItem(at: audio, to: folder.appendingPathComponent("123_002.mp3"))
        try FileManager.default.copyItem(at: audio, to: folder.appendingPathComponent("123_003.mp3"))
        let tracks = (2...4).map {
            MappedTrack(id: $0, lesson: 1, section: $0, subsection: nil, group: .lesson,
                        title: "Synthetic \($0)", needsReview: false)
        }
        let metadata = folder.appendingPathComponent("TrackMapping.json")
        try JSONEncoder().encode(TrackMapping(schemaVersion: 1, tracks: tracks)).write(to: metadata)
        let model = IntroEditorModel()
        defer { model.select(id: nil) }
        model.openMetadata(url: metadata)
        XCTAssertFalse(model.canSave)
        model.openAudioFolder(url: folder)
        XCTAssertTrue(model.canSave)
        let deadline = ContinuousClock.now + .seconds(5)
        while model.isLoadingWaveform, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(model.waveform)
        XCTAssertEqual(try XCTUnwrap(model.waveform).duration, model.player.duration, accuracy: 0.05)
        XCTAssertNil(model.errorMessage)
        model.player.seek(to: 1.25)
        model.mark(advance: true)
        XCTAssertEqual(model.selectedID, 3)
        XCTAssertEqual(try IntroMetadataStore(url: metadata).mapping.tracks[0].introEndSeconds, 1.25)
        XCTAssertNotNil(model.backupURL)
        model.save(seconds: 0)
        XCTAssertEqual(model.reviewedCount, 2)
        model.move(offset: -1)
        model.reloadMetadata()
        XCTAssertEqual(model.selectedTrack?.introEndSeconds, 1.25)
        model.previewMark(preroll: 1)
        XCTAssertTrue(model.player.isPlaying)
        XCTAssertEqual(model.player.position, 0.25, accuracy: 0.001)
        model.player.pause()
        model.save(seconds: nil)
        XCTAssertEqual(model.reviewedCount, 1)
        model.select(id: 3)
        model.select(id: 2)
        model.select(id: 4)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.selectedID, 4)
        XCTAssertNil(model.waveform)
        XCTAssertFalse(model.isLoadingWaveform)
        XCTAssertFalse(model.player.isLoaded)
        XCTAssertNil(model.errorMessage)
    }

    func testFailedSaveDoesNotAdvanceOrChangeModel() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let tracks = (2...3).map {
            MappedTrack(id: $0, lesson: 1, section: $0, subsection: nil, group: .lesson,
                        title: "Synthetic \($0)", needsReview: false)
        }
        let url = folder.appendingPathComponent("TrackMapping.json")
        try JSONEncoder().encode(TrackMapping(schemaVersion: 1, tracks: tracks)).write(to: url)
        let model = IntroEditorModel()
        model.openMetadata(url: url)
        model.mark(advance: true)
        XCTAssertEqual(model.selectedID, 2)
        XCTAssertEqual(model.reviewedCount, 0)
        XCTAssertNotNil(model.errorMessage)
    }
}
