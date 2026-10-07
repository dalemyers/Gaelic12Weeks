import XCTest
@testable import GaelicCompanion

final class CatalogTests: XCTestCase {
    /// Filename recognition must not confuse archive paths, suffixes, or the aggregate track.
    func testFilenameRecognition() {
        XCTAssertEqual(Catalog.trackID(filename: "9781788856034_002.mp3"), 2)
        XCTAssertEqual(Catalog.trackID(filename: "123_001.mp3"), 1)
        for invalid in ["../123_002.mp3", "123_002.mp3.exe", "123_02.mp3", "x_002.mp3", "1_000.mp3"] {
            XCTAssertNil(Catalog.trackID(filename: invalid))
        }
    }

    /// The editable catalog covers every individual track without embedding the aggregate.
    func testBundledMappingAndUserExamples() throws {
        let mapping = try TrackMapping.load()
        XCTAssertEqual(Set(mapping.tracks.map(\.id)), Set(2...151))
        let byID = Dictionary(uniqueKeysWithValues: mapping.tracks.map { ($0.id, $0) })
        XCTAssertEqual(byID[6]?.section, 4)
        XCTAssertEqual(byID[7]?.subsection, "a")
        XCTAssertEqual(byID[8]?.subsection, "b")
        XCTAssertEqual(byID[9]?.section, 5)
        XCTAssertEqual(byID[99]?.section, 67)
        XCTAssertEqual(byID[99]?.subsection, "a")
        XCTAssertEqual(byID[145]?.group, .appendices)
        XCTAssertEqual(byID[148]?.group, .readingPractice)
        XCTAssertTrue(try XCTUnwrap(byID[15]).needsReview)
    }

    /// Explicit subsection gaps produce a section even when there is no recorded parent track.
    func testGroupingSortingAndSubsectionOnlyParents() throws {
        let mapping = try TrackMapping.load()
        let imports = [99, 9, 8, 7, 6].map {
            ImportedTrack(id: $0, filename: "123_\(String(format: "%03d", $0)).mp3", metadataTitle: "Title")
        }
        let groups = try Catalog.groups(mapping: mapping, imported: imports)
        XCTAssertEqual(groups.first?.title, "Lesson 1")
        XCTAssertEqual(groups.first?.sections.map(\.number), [4, 5])
        XCTAssertEqual(groups.first?.sections.first?.tracks.map(\.id), [6, 7, 8])
        XCTAssertTrue(groups.flatMap(\.sections).contains { $0.number == 67 && $0.tracks.count == 1 })
    }

    /// Invalid manual edits fail visibly rather than silently losing files.
    func testRejectsInvalidMapping() throws {
        let valid = try TrackMapping.load()
        let duplicate = TrackMapping(schemaVersion: 1, tracks: [valid.tracks[0], valid.tracks[0]])
        XCTAssertThrowsError(try TrackMapping.decode(JSONEncoder().encode(duplicate)))
        let unsupported = TrackMapping(schemaVersion: 2, tracks: valid.tracks)
        XCTAssertThrowsError(try TrackMapping.decode(JSONEncoder().encode(unsupported)))
        let invalid = MappedTrack(
            id: 2, lesson: 0, section: 1, subsection: nil, group: .lesson, title: "Title", needsReview: true
        )
        XCTAssertThrowsError(try TrackMapping.decode(
            JSONEncoder().encode(TrackMapping(schemaVersion: 1, tracks: [invalid]))
        ))
    }

    /// Duplicate imported identifiers are rejected before dictionary construction.
    func testRejectsDuplicateAndUnknownImports() throws {
        let mapping = try TrackMapping.load()
        let track = ImportedTrack(id: 2, filename: "123_002.mp3", metadataTitle: "Pronouns")
        XCTAssertThrowsError(try Catalog.groups(mapping: mapping, imported: [track, track]))
        XCTAssertThrowsError(try Catalog.groups(mapping: mapping, imported: [
            ImportedTrack(id: 999, filename: "123_999.mp3", metadataTitle: "Unknown")
        ]))
    }
}
