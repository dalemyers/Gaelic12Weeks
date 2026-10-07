import XCTest
@testable import GaelicCompanion

@MainActor
final class ListeningProgressTests: XCTestCase {
    /// Completion requires every recording, survives relaunch, and can be toggled without listening.
    func testCompletionAndManualTogglePersist() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("progress.json")
        let progress = ListeningProgress(url: url)
        try progress.load()
        let lesson: Set<Int> = [2, 3, 4]
        XCTAssertFalse(progress.isListened(lesson))
        try progress.setListened(true, ids: [2])
        XCTAssertFalse(progress.isListened(lesson))
        try progress.setListened(true, ids: [3, 4])
        XCTAssertTrue(progress.isListened(lesson))
        let reloaded = ListeningProgress(url: url)
        try reloaded.load()
        XCTAssertTrue(reloaded.isListened(lesson))
        try reloaded.setListened(false, ids: lesson)
        XCTAssertFalse(reloaded.isListened(lesson))
        XCTAssertTrue(reloaded.listenedIDs.isEmpty)
        try reloaded.setListened(true, ids: lesson)
        XCTAssertTrue(reloaded.isListened(lesson))
        XCTAssertFalse(reloaded.isListened([]))
    }

    /// An incomplete imported subset must not count as completion of the full mapped lesson.
    func testMissingTracksAndIndependentLessons() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let progress = ListeningProgress(url: directory.appendingPathComponent("progress.json"))
        try progress.load()
        try progress.setListened(true, ids: [2, 3])
        XCTAssertFalse(progress.isListened([2, 3, 4]))
        try progress.setListened(true, ids: [15, 16])
        try progress.setListened(false, ids: [2, 3, 4])
        XCTAssertTrue(progress.isListened([15, 16]))
    }

    /// Corrupt progress cannot be silently replaced; the explicit reset action repairs it.
    func testCorruptProgressRequiresReset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("progress.json")
        try Data("corrupt".utf8).write(to: url)
        let progress = ListeningProgress(url: url)
        XCTAssertThrowsError(try progress.load())
        XCTAssertThrowsError(try progress.setListened(true, ids: [2]))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "corrupt")
        try progress.reset()
        try progress.setListened(true, ids: [2])
        XCTAssertTrue(progress.isListened([2]))
    }

    /// Failed writes leave the observable completion state unchanged.
    func testFailedWriteDoesNotPublishCompletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("file-not-directory")
        let progress = ListeningProgress(url: blocker.appendingPathComponent("progress.json"))
        try progress.load()
        try Data([1]).write(to: blocker)
        XCTAssertThrowsError(try progress.setListened(true, ids: [2]))
        XCTAssertTrue(progress.listenedIDs.isEmpty)
    }

    /// Section status includes its main recording and subsections, survives reload and clears on child changes.
    func testSectionCompletionAndReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("progress.json")
        let progress = ListeningProgress(url: url)
        try progress.load()
        let mapping = try TrackMapping.load()
        let group = try XCTUnwrap(Catalog.groups(mapping: mapping, imported: [6, 7, 8, 9].map {
            ImportedTrack(id: $0, filename: "1_00\($0).mp3", metadataTitle: "Title")
        }).first)
        let ids = mapping.trackIDs(for: group, section: 4)
        XCTAssertEqual(ids, [6, 7, 8])
        XCTAssertFalse(progress.isListened(ids))
        try progress.setListened(true, ids: [7, 8])
        XCTAssertFalse(progress.isListened(ids), "The main recording is also required.")
        try progress.setListened(true, ids: [6])
        XCTAssertTrue(progress.isListened(ids))
        XCTAssertFalse(progress.isListened(mapping.trackIDs(for: group, section: 5)))
        XCTAssertFalse(progress.isListened(mapping.trackIDs(for: group)), "One section does not complete its lesson.")
        let reloaded = ListeningProgress(url: url)
        try reloaded.load()
        XCTAssertTrue(reloaded.isListened(ids))
        try reloaded.setListened(false, ids: [8])
        XCTAssertFalse(reloaded.isListened(ids))
        try reloaded.setListened(true, ids: [8])
        XCTAssertTrue(reloaded.isListened(ids))
    }

    /// Missing imported children still count, while subsection-only sections need no phantom main track.
    func testSectionCompletionUsesMappingRatherThanImportedSubset() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let progress = ListeningProgress(url: directory.appendingPathComponent("progress.json"))
        try progress.load()
        let mapping = try TrackMapping.load()
        let groups = try Catalog.groups(mapping: mapping, imported: [7, 99].map {
            ImportedTrack(id: $0, filename: "1_\(String(format: "%03d", $0)).mp3", metadataTitle: "Title")
        })
        let partialLesson = try XCTUnwrap(groups.first(where: { $0.id == "lesson-1" }))
        let subsectionOnlyLesson = try XCTUnwrap(groups.first(where: { $0.tracks.contains { $0.id == 99 } }))
        let partialSection = mapping.trackIDs(for: partialLesson, section: 4)
        XCTAssertEqual(partialSection, [6, 7, 8])
        try progress.setListened(true, ids: [7])
        XCTAssertFalse(progress.isListened(partialSection))
        let subsectionOnly = mapping.trackIDs(for: subsectionOnlyLesson, section: 67)
        XCTAssertEqual(subsectionOnly, [99])
        XCTAssertFalse(progress.isListened(subsectionOnly))
        try progress.setListened(true, ids: [99])
        XCTAssertTrue(progress.isListened(subsectionOnly))
        XCTAssertTrue(mapping.trackIDs(for: partialLesson, section: 67).isEmpty)
        XCTAssertFalse(progress.isListened(mapping.trackIDs(for: partialLesson, section: 999)))
        XCTAssertTrue(mapping.trackIDs(for: LibraryGroup(id: "empty", title: "Empty", tracks: [])).isEmpty)
    }
}
