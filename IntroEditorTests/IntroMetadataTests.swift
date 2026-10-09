import XCTest
@testable import GaelicIntroEditor

@MainActor
final class IntroMetadataTests: XCTestCase {
    private func fixture() throws -> (URL, URL, Data) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("TrackMapping.json")
        let data = Data("""
        {"schemaVersion":1,"custom":{"keep":true},"tracks":[
          {"id":2,"lesson":1,"section":4,"subsection":"a","group":"lesson",
           "title":"Synthetic title","needsReview":false,"extra":"preserve"},
          {"id":3,"lesson":1,"section":null,"subsection":null,"group":"lesson",
           "title":"Conversation","needsReview":false}
        ]}
        """.utf8)
        try data.write(to: url)
        return (folder, url, data)
    }

    func testSaveReloadClearAndUnknownFields() throws {
        let (folder, url, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try IntroMetadataStore(url: url)
        XCTAssertNil(store.mapping.tracks[0].introEndSeconds)
        try store.save(trackID: 2, seconds: 2.375, duration: 10)
        let backup = try XCTUnwrap(store.backupURL)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        let reloaded = try IntroMetadataStore(url: url)
        XCTAssertEqual(reloaded.mapping.tracks[0].introEndSeconds, 2.375)
        XCTAssertNil(reloaded.mapping.tracks[1].introEndSeconds)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual((raw["custom"] as? [String: Bool])?["keep"], true)
        XCTAssertEqual((raw["tracks"] as? [[String: Any]])?[0]["extra"] as? String, "preserve")
        try store.save(trackID: 3, seconds: 0, duration: 10)
        XCTAssertEqual(store.mapping.tracks[1].introEndSeconds, 0)
        XCTAssertEqual(store.backupURL, backup)
        try store.save(trackID: 2, seconds: nil, duration: 0)
        XCTAssertNil(try IntroMetadataStore(url: url).mapping.tracks[0].introEndSeconds)
        XCTAssertEqual(try Data(contentsOf: backup), original)
    }

    func testInvalidOffsetsAndUnknownTracksNeverWrite() throws {
        let (folder, url, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try IntroMetadataStore(url: url)
        for seconds in [-1, 10, 11, Double.nan, .infinity] {
            XCTAssertThrowsError(try store.save(trackID: 2, seconds: seconds, duration: 10))
        }
        XCTAssertThrowsError(try store.save(trackID: 2, seconds: 0, duration: 0))
        XCTAssertThrowsError(try store.save(trackID: 999, seconds: 1, duration: 10))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertNil(store.backupURL)
    }

    func testExternalEditConflictAndReload() throws {
        let (folder, url, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try IntroMetadataStore(url: url)
        let other = try IntroMetadataStore(url: url)
        try other.save(trackID: 3, seconds: 0, duration: 10)
        let externalData = try Data(contentsOf: url)
        XCTAssertThrowsError(try store.save(trackID: 2, seconds: 2, duration: 10))
        XCTAssertEqual(try Data(contentsOf: url), externalData)
        XCTAssertNil(store.backupURL)
        try store.reload()
        try store.save(trackID: 2, seconds: 2, duration: 10)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.backupURL)), externalData)
        XCTAssertEqual(store.mapping.tracks[1].introEndSeconds, 0)
    }

    func testMissingFileIsNotRecreatedOnSave() throws {
        let (folder, url, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try IntroMetadataStore(url: url)
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try store.save(trackID: 2, seconds: 1, duration: 10))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testNestedAudioIndexIgnoresAggregateAndRejectsDuplicates() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let nested = folder.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        for name in ["123_001.mp3", "123_002.mp3", "other.mp3"] {
            try Data().write(to: nested.appendingPathComponent(name))
        }
        XCTAssertEqual(try IntroAudioFiles.index(folder: folder).keys.sorted(), [2])
        try Data().write(to: folder.appendingPathComponent("456_002.mp3"))
        XCTAssertThrowsError(try IntroAudioFiles.index(folder: folder))
        XCTAssertThrowsError(try IntroAudioFiles.index(folder: folder.appendingPathComponent("absent")))
    }
}
