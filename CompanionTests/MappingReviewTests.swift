#if DEBUG
import XCTest
@testable import GaelicCompanion

@MainActor
final class MappingReviewTests: XCTestCase {
    func testIntroMarkersSurviveReviewEditsShiftsAndExport() throws {
        var tracks = sectionShiftMapping().tracks
        for index in tracks.indices { tracks[index].introEndSeconds = Double(tracks[index].id) / 2 }
        let (directory, store) = try makeStore(source: TrackMapping(schemaVersion: 1, tracks: tracks))
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.load()
        var fields = try XCTUnwrap(store.fields(2))
        fields.section = "12"
        try store.save(id: 2, fields: fields, decision: .confirmed)
        let exported = try TrackMapping.decode(store.exportMapping())
        for track in exported.tracks {
            XCTAssertEqual(track.introEndSeconds, Double(track.id) / 2)
        }
    }

    /// Creates a review store outside the application's real data container.
    private func makeStore(source: TrackMapping? = nil) throws -> (URL, MappingReviewStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (directory, MappingReviewStore(
            source: try source ?? TrackMapping.load(), url: directory.appendingPathComponent("review.json")
        ))
    }

    /// Provides deliberately unsorted IDs, shared sections, later lessons, confirmed rows and unnumbered audio.
    private func sectionShiftMapping() -> TrackMapping {
        let sections: [Int: Int] = [2: 10, 3: 10, 4: 11, 5: 12, 7: 13, 8: 14, 9: 15, 12: 16]
        let tracks = (2...12).reversed().map { id in
            MappedTrack(
                id: id, lesson: id == 10 || id == 11 ? nil : (id < 5 ? 1 : 2),
                section: sections[id], subsection: id == 3 ? "a" : nil,
                group: id == 10 ? .appendices : (id == 11 ? .readingPractice : .lesson),
                title: "Original title \(id)", needsReview: id != 7
            )
        }
        return TrackMapping(schemaVersion: 1, tracks: tracks)
    }

    /// Writes a version-one draft, including records that omit the new optional pending-offset field.
    private func writeDraft(_ records: [MappingReviewRecord], to directory: URL) throws {
        let rows = try JSONSerialization.jsonObject(with: JSONEncoder().encode(records))
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "records": rows])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("review.json"))
    }

    /// Confirmation shifts later proposals across lessons, but preserves confirmed and unnumbered recordings.
    func testSectionIncreaseShiftsOnlyLaterUnconfirmedNumberedTracks() throws {
        let (directory, store) = try makeStore(source: sectionShiftMapping())
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.load()
        try store.save(id: 8, fields: XCTUnwrap(store.fields(8)), decision: .confirmed)
        var incorrect = try XCTUnwrap(store.fields(9))
        incorrect.note = "Still needs checking."
        incorrect.title = "Keep my custom title"
        try store.save(id: 9, fields: incorrect, decision: .incorrect)
        var fields = try XCTUnwrap(store.fields(2))
        fields.section = "12"
        let result = try store.save(id: 2, fields: fields, decision: .confirmed)
        XCTAssertEqual(result.sectionDelta, 2)
        XCTAssertEqual(result.shiftedTrackCount, 5)
        XCTAssertEqual(store.track(3)?.section, 12)
        XCTAssertEqual(store.track(3)?.subsection, "a")
        XCTAssertEqual(store.track(4)?.section, 13)
        XCTAssertEqual(store.track(5)?.lesson, 2)
        XCTAssertEqual(store.track(5)?.section, 14)
        XCTAssertEqual(store.track(12)?.section, 18)
        XCTAssertEqual(store.track(7)?.section, 13, "Bundled confirmations must also be protected.")
        XCTAssertEqual(store.track(8)?.section, 14)
        XCTAssertEqual(store.decision(9), .incorrect)
        XCTAssertEqual(store.fields(9)?.note, incorrect.note)
        XCTAssertEqual(store.track(9)?.title, incorrect.title)
        for id in [6, 10, 11] {
            XCTAssertEqual(store.track(id), store.source.tracks.first { $0.id == id })
        }
        XCTAssertEqual(store.confirmedCount, 2, "Shifted proposals must not become confirmed.")
        let exported = try TrackMapping.decode(store.exportMapping())
        let restored = MappingReviewStore(source: exported, url: directory.appendingPathComponent("review.json"))
        try restored.load()
        XCTAssertEqual(try TrackMapping.decode(restored.exportMapping()).tracks, exported.tracks)
        let unchanged = try restored.save(id: 3, fields: XCTUnwrap(restored.fields(3)), decision: .confirmed)
        XCTAssertEqual(unchanged.shiftedTrackCount, 0, "Confirming an automatically shifted proposal must not shift again.")
        XCTAssertEqual(restored.track(4)?.section, 13)
    }

    /// Saving a tentative correction defers its offset, including across relaunches, until explicit confirmation.
    func testSavedSectionCorrectionPropagatesOnceOnConfirmation() throws {
        let (directory, store) = try makeStore(source: sectionShiftMapping())
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.load()
        var fields = try XCTUnwrap(store.fields(2))
        fields.section = "13"
        let saved = try store.save(id: 2, fields: fields, decision: .unreviewed)
        XCTAssertEqual(saved.shiftedTrackCount, 0)
        XCTAssertEqual(store.track(4)?.section, 11)
        let restored = MappingReviewStore(source: store.source, url: directory.appendingPathComponent("review.json"))
        try restored.load()
        let confirmed = try restored.save(id: 2, fields: XCTUnwrap(restored.fields(2)), decision: .confirmed)
        XCTAssertEqual(confirmed.sectionDelta, 3)
        XCTAssertEqual(restored.track(4)?.section, 14)
        let repeated = try restored.save(id: 2, fields: XCTUnwrap(restored.fields(2)), decision: .confirmed)
        XCTAssertEqual(repeated.shiftedTrackCount, 0)
        try restored.save(id: 4, fields: XCTUnwrap(restored.fields(4)), decision: .confirmed)
        fields.section = "14"
        let revised = try restored.save(id: 2, fields: fields, decision: .confirmed)
        XCTAssertEqual(revised.sectionDelta, 1)
        XCTAssertEqual(restored.track(3)?.section, 14)
        XCTAssertEqual(restored.track(4)?.section, 14, "A confirmed later track must stay fixed.")
    }

    /// Cascading a proposal keeps its separate pending manual correction for that track's later confirmation.
    func testShiftPreservesPendingCorrectionsOnFollowingTracks() throws {
        let (directory, store) = try makeStore(source: sectionShiftMapping())
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.load()
        var later = try XCTUnwrap(store.fields(5))
        later.section = "15"
        try store.save(id: 5, fields: later, decision: .incorrect)
        var earlier = try XCTUnwrap(store.fields(2))
        earlier.section = "12"
        try store.save(id: 2, fields: earlier, decision: .confirmed)
        XCTAssertEqual(store.track(5)?.section, 17)
        let result = try store.save(id: 5, fields: XCTUnwrap(store.fields(5)), decision: .confirmed)
        XCTAssertEqual(result.sectionDelta, 3)
        XCTAssertEqual(store.track(9)?.section, 20)
        XCTAssertEqual(store.track(4)?.section, 13, "Earlier filename IDs never shift.")
    }

    /// Decrements propagate too; removing or adding a numbered section does not invent a numeric offset.
    func testSectionDecreaseAndUnnumberedTransitions() throws {
        let (directory, store) = try makeStore(source: sectionShiftMapping())
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.load()
        var fields = try XCTUnwrap(store.fields(2))
        fields.section = "8"
        let result = try store.save(id: 2, fields: fields, decision: .confirmed)
        XCTAssertEqual(result.sectionDelta, -2)
        XCTAssertEqual(store.track(3)?.section, 8)
        XCTAssertEqual(store.track(5)?.section, 10)
        fields.section = ""
        XCTAssertEqual(try store.save(id: 2, fields: fields, decision: .confirmed).shiftedTrackCount, 0)
        try store.save(id: 2, fields: fields, decision: .unreviewed)
        fields.section = "3"
        XCTAssertEqual(try store.save(id: 2, fields: fields, decision: .confirmed).shiftedTrackCount, 0)
        XCTAssertEqual(store.track(3)?.section, 8)
        fields.group = .appendices
        XCTAssertEqual(try store.save(id: 2, fields: fields, decision: .confirmed).shiftedTrackCount, 0)
        XCTAssertNil(store.track(2)?.section)
    }

    /// A zero/negative result or integer overflow rejects the whole operation without changing disk or memory.
    func testInvalidCascadeIsAtomic() throws {
        for lastSection in [1, Int.max] {
            let base = sectionShiftMapping()
            let source = TrackMapping(schemaVersion: 1, tracks: base.tracks.map { track in
                guard track.id == 12 else { return track }
                return MappedTrack(
                    id: track.id, lesson: track.lesson, section: lastSection, subsection: track.subsection,
                    group: track.group, title: track.title, needsReview: track.needsReview
                )
            })
            let (directory, store) = try makeStore(source: source)
            defer { try? FileManager.default.removeItem(at: directory) }
            try store.load()
            try store.save(id: 8, fields: XCTUnwrap(store.fields(8)), decision: .confirmed)
            let before = try store.exportMapping()
            let backup = try store.exportBackup()
            var fields = try XCTUnwrap(store.fields(2))
            fields.section = lastSection == 1 ? "8" : "12"
            XCTAssertThrowsError(try store.save(id: 2, fields: fields, decision: .confirmed))
            XCTAssertEqual(try store.exportMapping(), before)
            XCTAssertEqual(try store.exportBackup(), backup)
            XCTAssertEqual(store.decision(2), .unreviewed)
        }
    }

    /// A failed multi-track write cannot publish the selected confirmation or any of its automatic shifts.
    func testCascadeWriteFailurePreservesAllProposals() throws {
        let (directory, store) = try makeStore(source: sectionShiftMapping())
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.load()
        let before = try store.exportMapping()
        try Data([1]).write(to: directory)
        var fields = try XCTUnwrap(store.fields(2))
        fields.section = "12"
        XCTAssertThrowsError(try store.save(id: 2, fields: fields, decision: .confirmed))
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertEqual(try store.exportMapping(), before)
    }

    /// Drafts from before automatic shifts retain tentative offsets, but never replay old confirmed corrections.
    func testLegacyDraftSectionCorrections() throws {
        let source = sectionShiftMapping()
        let (directory, store) = try makeStore(source: source)
        defer { try? FileManager.default.removeItem(at: directory) }
        var legacy: [MappingReviewRecord] = []
        for (id, section, decision) in [(2, "13", MappingReviewDecision.unreviewed), (8, "18", .confirmed)] {
            let original = try XCTUnwrap(source.tracks.first { $0.id == id })
            var fields = MappingReviewFields(track: original)
            fields.section = section
            legacy.append(MappingReviewRecord(
                original: original, edited: try fields.track(id: id, decision: decision),
                decision: decision, note: "", pendingSectionDelta: nil
            ))
        }
        try writeDraft(legacy, to: directory)
        try store.load()
        let appliedSource = try TrackMapping.decode(store.exportMapping())
        let restored = MappingReviewStore(source: appliedSource, url: directory.appendingPathComponent("review.json"))
        try restored.load()
        XCTAssertEqual(try restored.save(id: 8, fields: XCTUnwrap(restored.fields(8)), decision: .confirmed).sectionDelta, 0)
        XCTAssertEqual(try restored.save(id: 2, fields: XCTUnwrap(restored.fields(2)), decision: .confirmed).sectionDelta, 3)
        XCTAssertEqual(restored.track(8)?.section, 18)
        XCTAssertEqual(restored.track(9)?.section, 18)
    }

    /// Old original rows are validated before delta arithmetic, and overflowing pending offsets fail atomically.
    func testMalformedBaselineAndPendingOffsetOverflow() throws {
        let (directory, store) = try makeStore(source: sectionShiftMapping())
        defer { try? FileManager.default.removeItem(at: directory) }
        let track = try XCTUnwrap(store.source.tracks.first { $0.id == 2 })
        let invalidOriginal = MappedTrack(
            id: track.id, lesson: track.lesson, section: Int.min, subsection: nil,
            group: track.group, title: track.title, needsReview: true
        )
        try writeDraft([MappingReviewRecord(
            original: invalidOriginal, edited: track, decision: .unreviewed, note: "", pendingSectionDelta: nil
        )], to: directory)
        XCTAssertThrowsError(try store.load())
        XCTAssertFalse(store.isReady)
        try writeDraft([MappingReviewRecord(
            original: track, edited: track, decision: .unreviewed, note: "", pendingSectionDelta: Int.max
        )], to: directory)
        try store.load()
        let before = try store.exportBackup()
        var fields = try XCTUnwrap(store.fields(2))
        fields.section = "11"
        XCTAssertThrowsError(try store.save(id: 2, fields: fields, decision: .confirmed))
        XCTAssertEqual(try store.exportBackup(), before)
        XCTAssertEqual(store.track(2), track)
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
        XCTAssertFalse(String(decoding: try store.exportMapping(), as: UTF8.self).contains("\"pendingSectionDelta\""))
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
        model.player.skipSpokenIntroductions = true
        let completion = try XCTUnwrap(model.player.onTrackFinished)
        let finished = expectation(description: "Review audition completed")
        model.player.onTrackFinished = { id in
            completion(id)
            finished.fulfill()
        }
        try model.beginMappingReview()
        var track = try XCTUnwrap(model.mapping?.tracks.first { $0.id == 2 })
        track.introEndSeconds = 1
        try await model.playForMappingReview(track)
        XCTAssertNil(model.player.errorMessage)
        XCTAssertTrue(model.player.isPlaying)
        XCTAssertLessThan(model.player.position, 0.2, "Mapping auditions must bypass the enabled skip preference.")
        model.player.seek(to: max(0, model.player.duration - 0.2))
        await fulfillment(of: [finished], timeout: 10)
        XCTAssertFalse(model.progress.isListened([2]))
    }
}
#endif
