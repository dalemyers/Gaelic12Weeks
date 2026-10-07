#if DEBUG
import XCTest
@testable import GaelicCompanion

@MainActor
final class MappingReviewTests: XCTestCase {
    /// Creates a review store outside the application's real data container.
    private func makeStore() throws -> (URL, MappingReviewStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (directory, MappingReviewStore(
            source: try TrackMapping.load(), url: directory.appendingPathComponent("review.json")
        ))
    }

    /// Untouched rows export unchanged, and confirmation preserves the full catalog while clearing its flag.
    func testConfirmAndExportCompleteMapping() throws {
        let (directory, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.load()
        let initial = try TrackMapping.decode(store.exportMapping())
        XCTAssertEqual(initial.tracks, store.source.tracks.sorted { $0.id < $1.id })
        XCTAssertEqual(store.confirmedCount, 0)
        XCTAssertEqual(store.decision(2), .unreviewed)
        var fields = try XCTUnwrap(store.fields(7))
        fields.lesson = "2"
        fields.section = "14"
        fields.subsection = "b"
        fields.title = "Corrected Gaelic title"
        try store.save(id: 7, fields: fields, decision: .confirmed)
        let exported = try TrackMapping.decode(store.exportMapping())
        XCTAssertEqual(exported.tracks.count, 150)
        XCTAssertEqual(exported.tracks.map(\.id), Array(2...151))
        let corrected = try XCTUnwrap(exported.tracks.first { $0.id == 7 })
        XCTAssertEqual(corrected.lesson, 2)
        XCTAssertEqual(corrected.section, 14)
        XCTAssertEqual(corrected.subsection, "b")
        XCTAssertEqual(corrected.title, fields.title)
        XCTAssertFalse(corrected.needsReview)
        XCTAssertEqual(store.confirmedCount, 1)
        XCTAssertFalse(String(decoding: try store.exportMapping(), as: UTF8.self).contains("\"note\""))
    }

    /// Incorrect decisions, notes and draft corrections survive reload without pretending to be confirmed.
    func testIncorrectAndCorrectionPersistence() throws {
        let (directory, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.load()
        var fields = try XCTUnwrap(store.fields(2))
        fields.note = "Check the book's section boundary."
        fields.section = "3"
        try store.save(id: 2, fields: fields, decision: .incorrect)
        XCTAssertTrue(try XCTUnwrap(store.track(2)).needsReview)
        let restored = MappingReviewStore(source: store.source, url: directory.appendingPathComponent("review.json"))
        try restored.load()
        XCTAssertEqual(restored.decision(2), .incorrect)
        XCTAssertEqual(restored.fields(2), fields)
        XCTAssertEqual(restored.incorrectCount, 1)
        try restored.save(id: 2, fields: fields, decision: .unreviewed)
        XCTAssertEqual(restored.decision(2), .unreviewed)
        XCTAssertEqual(restored.incorrectCount, 0)
        XCTAssertTrue(try XCTUnwrap(restored.track(2)).needsReview)
        XCTAssertTrue(String(decoding: try restored.exportBackup(), as: UTF8.self).contains(fields.note))
    }

    /// Invalid field input cannot mutate memory or overwrite a valid on-disk decision.
    func testInvalidCorrectionsPreserveSavedState() throws {
        let (directory, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.load()
        let valid = try XCTUnwrap(store.fields(7))
        try store.save(id: 7, fields: valid, decision: .confirmed)
        let before = try store.exportBackup()
        var invalid = valid
        invalid.lesson = "13"
        XCTAssertThrowsError(try store.save(id: 7, fields: invalid, decision: .confirmed))
        invalid = valid
        invalid.section = "no"
        XCTAssertThrowsError(try store.save(id: 7, fields: invalid, decision: .confirmed))
        invalid = valid
        invalid.section = ""
        XCTAssertThrowsError(try store.save(id: 7, fields: invalid, decision: .confirmed))
        invalid = valid
        invalid.subsection = "4a"
        XCTAssertThrowsError(try store.save(id: 7, fields: invalid, decision: .confirmed))
        invalid = valid
        invalid.title = "   "
        XCTAssertThrowsError(try store.save(id: 7, fields: invalid, decision: .confirmed))
        XCTAssertThrowsError(try store.save(id: 1, fields: valid, decision: .confirmed))
        XCTAssertEqual(try store.exportBackup(), before)
        XCTAssertEqual(store.decision(7), .confirmed)
        XCTAssertEqual(store.fields(7), valid)
    }

    /// Conversations and bonus groups export valid nullable fields, without stale lesson/subsection assignments.
    func testConversationAndBonusCorrections() throws {
        let (directory, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.load()
        var fields = try XCTUnwrap(store.fields(7))
        fields.section = ""
        fields.subsection = ""
        try store.save(id: 7, fields: fields, decision: .confirmed)
        XCTAssertNil(store.track(7)?.section)
        fields.group = .readingPractice
        fields.section = "4"
        fields.subsection = "a"
        try store.save(id: 7, fields: fields, decision: .confirmed)
        let entry = try XCTUnwrap(TrackMapping.decode(store.exportMapping()).tracks.first { $0.id == 7 })
        XCTAssertEqual(entry.group, .readingPractice)
        XCTAssertNil(entry.lesson)
        XCTAssertNil(entry.section)
        XCTAssertNil(entry.subsection)
    }

    /// Updating the bundled mapping cannot silently overwrite a newer source row with a stale correction.
    func testStaleDraftBlocksEditsButAllowsBackupAndReset() throws {
        let (directory, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.load()
        let fields = try XCTUnwrap(store.fields(7))
        try store.save(id: 7, fields: fields, decision: .incorrect)
        var newFields = fields
        newFields.title = "New upstream title"
        let changed = try newFields.track(id: 7, decision: .confirmed)
        let source = TrackMapping(schemaVersion: 1, tracks: store.source.tracks.map { $0.id == 7 ? changed : $0 })
        let restored = MappingReviewStore(source: source, url: directory.appendingPathComponent("review.json"))
        XCTAssertThrowsError(try restored.load())
        XCTAssertFalse(restored.isReady)
        XCTAssertThrowsError(try restored.save(id: 7, fields: fields, decision: .confirmed))
        XCTAssertThrowsError(try restored.exportMapping())
        XCTAssertEqual(try restored.exportBackup(), try store.exportBackup())
        try restored.reset()
        XCTAssertEqual(restored.decision(7), .unreviewed)
        XCTAssertEqual(restored.track(7), changed)
    }

    /// Applying an exported mapping to the bundle is an expected update, not a conflicting upstream edit.
    func testReloadAfterExportAppliedToBundle() throws {
        let (directory, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.load()
        var fields = try XCTUnwrap(store.fields(7))
        fields.lesson = "2"
        try store.save(id: 7, fields: fields, decision: .confirmed)
        let corrected = try TrackMapping.decode(store.exportMapping())
        let restored = MappingReviewStore(source: corrected, url: directory.appendingPathComponent("review.json"))
        try restored.load()
        XCTAssertEqual(restored.confirmedCount, 1)
        XCTAssertEqual(restored.fields(7), fields)
    }

    /// Corrupt draft bytes remain available for backup until the user explicitly resets them.
    func testCorruptDraftAndWriteFailure() throws {
        let (directory, store) = try makeStore()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let corrupt = Data("not JSON".utf8)
        try corrupt.write(to: directory.appendingPathComponent("review.json"))
        XCTAssertThrowsError(try store.load())
        XCTAssertFalse(store.isReady)
        XCTAssertEqual(try store.exportBackup(), corrupt)
        try store.reset()
        XCTAssertTrue(store.isReady)
        let blocker = directory.appendingPathComponent("not-a-directory")
        let failing = MappingReviewStore(source: store.source, url: blocker.appendingPathComponent("review.json"))
        try failing.load()
        try Data([1]).write(to: blocker)
        XCTAssertThrowsError(try failing.save(
            id: 2, fields: XCTUnwrap(failing.fields(2)), decision: .confirmed
        ))
        XCTAssertEqual(failing.confirmedCount, 0)
        XCTAssertEqual(failing.decision(2), .unreviewed)
    }

    /// The shared player's wired completion handler ignores review auditions but still records ordinary listening.
    func testReviewPlaybackDoesNotMarkListened() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = LibraryModel(applicationSupportURL: directory)
        defer { model.endMappingReview() }
        XCTAssertThrowsError(try model.beginMappingReview(), "Review cannot start before the mapping loads.")
        await model.load()
        XCTAssertNil(model.errorMessage)
        let completion = try XCTUnwrap(model.player.onTrackFinished)
        try model.beginMappingReview()
        completion(2)
        XCTAssertFalse(model.progress.isListened([2]))
        let entry = try XCTUnwrap(model.mapping?.tracks.first { $0.id == 2 })
        do {
            try await model.playForMappingReview(entry)
            XCTFail("Unimported review recordings must not play.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Import the audio"))
        }
        model.endMappingReview()
        completion(2)
        XCTAssertTrue(model.progress.isListened([2]), "Normal playback completion must still mark recordings listened.")
    }

    /// Auditions a supplied recording through the real player without bundling copyrighted fixtures.
    func testReviewAuditionWhenLocalAudioAvailable() async throws {
        let audio = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Audio")
        guard FileManager.default.fileExists(atPath: audio.path) else {
            throw XCTSkip("Optional local Audio/ fixtures are absent; copyrighted audio is never committed.")
        }
        let source = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: audio, includingPropertiesForKeys: nil)
                .first { Catalog.trackID(filename: $0.lastPathComponent) == 2 }
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let generation = UUID().uuidString
        let root = directory.appendingPathComponent("ImportedLibrary")
        let destination = root.appendingPathComponent(generation)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination.appendingPathComponent(source.lastPathComponent))
        let imported = ImportedTrack(id: 2, filename: source.lastPathComponent, metadataTitle: "Local audio fixture")
        let saved = SavedLibrary(
            directory: generation, manifest: LibraryManifest(schemaVersion: 1, tracks: [imported])
        )
        try JSONEncoder().encode(saved).write(to: root.appendingPathComponent("Current.json"))
        let model = LibraryModel(applicationSupportURL: directory)
        defer { model.endMappingReview() }
        await model.load()
        XCTAssertNil(model.errorMessage)
        let completion = try XCTUnwrap(model.player.onTrackFinished)
        let finished = expectation(description: "Review audition completed")
        model.player.onTrackFinished = { id in
            completion(id)
            finished.fulfill()
        }
        try model.beginMappingReview()
        let track = try XCTUnwrap(model.mapping?.tracks.first { $0.id == 2 })
        try await model.playForMappingReview(track)
        XCTAssertNil(model.player.errorMessage)
        XCTAssertTrue(model.player.isPlaying)
        model.player.seek(to: max(0, model.player.duration - 0.2))
        await fulfillment(of: [finished], timeout: 10)
        XCTAssertFalse(model.progress.isListened([2]))
    }
}
#endif
