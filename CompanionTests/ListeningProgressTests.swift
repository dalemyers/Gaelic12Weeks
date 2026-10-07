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
}
