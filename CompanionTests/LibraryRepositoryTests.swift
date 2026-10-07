import Foundation
import XCTest
import ZIPFoundation
@testable import GaelicCompanion

final class LibraryRepositoryTests: XCTestCase {
    private var directory: URL!

    /// Creates an isolated temporary root for every archive test.
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Removes only this test's generated fixtures.
    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    /// Builds copyright-free ZIP fixtures rather than committing publisher audio.
    private func archive(_ entries: [(String, Data)], compression: CompressionMethod = .deflate) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString + ".zip")
        let archive = try Archive(url: url, accessMode: .create)
        for (name, data) in entries {
            try archive.addEntry(
                with: name, type: .file, uncompressedSize: Int64(data.count), compressionMethod: compression
            ) { position, size in
                data.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        return url
    }

    /// Tests nested paths, numeric sorting, aggregate removal, ignored files and persistence.
    func testImportAndReload() async throws {
        let zip = try archive([
            ("folder/123_003.mp3", Data("three".utf8)),
            ("folder/123_001.mp3", Data("aggregate".utf8)),
            ("./folder/123_002.mp3", Data("two".utf8)),
            ("__MACOSX/123_002.mp3", Data("resource fork".utf8)),
            ("notes.txt", Data("not audio".utf8))
        ])
        let root = directory.appendingPathComponent("library")
        let repository = LibraryRepository(root: root, readTitle: { $0.lastPathComponent })
        let mapping = try TrackMapping.load()
        let saved = try await repository.importZIP(at: zip, mapping: mapping) { _, _ in }
        XCTAssertEqual(saved.manifest.tracks.map(\.id), [2, 3])
        let reloaded = try await LibraryRepository(root: root).load(mapping: mapping)
        XCTAssertEqual(reloaded?.directory, saved.directory)
        XCTAssertEqual(reloaded?.manifest.tracks.map(\.metadataTitle), ["123_002.mp3", "123_003.mp3"])
        let files = try FileManager.default.contentsOfDirectory(
            atPath: root.appendingPathComponent(saved.directory).path
        )
        XCTAssertEqual(Set(files), Set(["123_002.mp3", "123_003.mp3"]))
    }

    /// Unsafe, unknown, duplicate, oversized and aggregate-only archives must not produce a library.
    func testRejectsInvalidArchives() async throws {
        let cases: [[(String, Data)]] = [
            [("../123_002.mp3", Data([1]))],
            [("123_002.mp3", Data([1])), ("nested/456_002.mp3", Data([2]))],
            [("123_999.mp3", Data([1]))],
            [("123_001.mp3", Data([1]))],
            [("123_002.mp3", Data(repeating: 0, count: 11))],
            [("123_002.mp3", Data(repeating: 0, count: 8)), ("123_003.mp3", Data(repeating: 0, count: 8))]
        ]
        for entries in cases {
            let zip = try archive(entries)
            let root = directory.appendingPathComponent(UUID().uuidString)
            let repository = LibraryRepository(
                root: root, maximumTrackBytes: 10, maximumTotalBytes: 15, readTitle: { _ in "Title" }
            )
            do {
                _ = try await repository.importZIP(at: zip, mapping: TrackMapping.load()) { _, _ in }
                XCTFail("Invalid archive was accepted: \(entries.map(\.0))")
            } catch {
                XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Current.json").path))
            }
        }
    }

    /// Failed replacement must leave the original committed generation intact.
    func testFailedReplacementPreservesLibrary() async throws {
        let root = directory.appendingPathComponent("library")
        let mapping = try TrackMapping.load()
        let zip = try archive([("123_002.mp3", Data([1, 2, 3]))], compression: .none)
        let repository = LibraryRepository(root: root, readTitle: { _ in "Pronouns" })
        let original = try await repository.importZIP(at: zip, mapping: mapping) { _, _ in }
        let failing = LibraryRepository(root: root, readTitle: { _ in throw CocoaError(.fileReadCorruptFile) })
        do {
            _ = try await failing.importZIP(at: zip, mapping: mapping) { _, _ in }
            XCTFail("Expected metadata failure")
        } catch {
            let saved = try await repository.load(mapping: mapping)
            XCTAssertEqual(saved?.directory, original.directory)
            let generations = try FileManager.default.contentsOfDirectory(atPath: root.path)
                .filter { UUID(uuidString: $0) != nil }
            XCTAssertEqual(generations, [original.directory])
        }
    }

    /// Cancellation rolls back the staged import and cannot publish a manifest.
    func testCancellationBeforeCommit() async throws {
        let zip = try archive([("123_002.mp3", Data([1]))])
        let root = directory.appendingPathComponent("library")
        let repository = LibraryRepository(root: root, readTitle: { _ in throw CancellationError() })
        do {
            _ = try await repository.importZIP(at: zip, mapping: TrackMapping.load()) { _, _ in }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Current.json").path))
        }
    }

    /// A corrupted stored payload must be rejected by the explicit CRC comparison.
    func testChecksumMismatch() async throws {
        let zip = try archive([("123_002.mp3", Data("unique-test-payload".utf8))], compression: .none)
        var data = try Data(contentsOf: zip)
        let range = try XCTUnwrap(data.range(of: Data("unique-test-payload".utf8)))
        data[range.lowerBound] ^= 0xff
        try data.write(to: zip)
        let root = directory.appendingPathComponent("library")
        let repository = LibraryRepository(root: root, readTitle: { _ in "Title" })
        do {
            _ = try await repository.importZIP(at: zip, mapping: TrackMapping.load()) { _, _ in }
            XCTFail("Expected CRC failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("integrity"))
        }
    }

    /// Real media validation cannot accept a file merely because its name ends in MP3.
    func testRejectsNonAudio() async throws {
        let url = directory.appendingPathComponent("123_002.mp3")
        try Data("This is not audio".utf8).write(to: url)
        do {
            _ = try await LibraryRepository.audioTitle(at: url)
            XCTFail("Expected invalid media failure")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    /// Checks every supplied recording through the production metadata reader without bundling any audio.
    func testLocalPublisherAudioWhenAvailable() async throws {
        let audio = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Audio")
        guard FileManager.default.fileExists(atPath: audio.path) else {
            throw XCTSkip("Optional local Audio/ fixtures are not present; copyrighted audio is never committed.")
        }
        let zip = directory.appendingPathComponent("local-audio.zip")
        let archive = try Archive(url: zip, accessMode: .create)
        let files = try FileManager.default.contentsOfDirectory(at: audio, includingPropertiesForKeys: nil)
            .filter { (Catalog.trackID(filename: $0.lastPathComponent) ?? 0) > 1 }
        XCTAssertEqual(files.count, 150)
        for file in files {
            try archive.addEntry(with: file.lastPathComponent, relativeTo: audio, compressionMethod: .none)
        }
        let mapping = try TrackMapping.load()
        let repository = LibraryRepository(root: directory.appendingPathComponent("library"))
        let saved = try await repository.importZIP(at: zip, mapping: mapping) { _, _ in }
        XCTAssertEqual(saved.manifest.tracks.count, 150)
        XCTAssertEqual(saved.manifest.tracks.first?.metadataTitle, "Pronouns")
        XCTAssertTrue(saved.manifest.tracks.allSatisfy { !$0.metadataTitle.isEmpty })
        let groups = try Catalog.groups(mapping: mapping, imported: saved.manifest.tracks)
        XCTAssertEqual(groups.filter { $0.id.hasPrefix("lesson-") }.count, 12)
        XCTAssertEqual(groups.count, 14)
        let loaded = try await repository.load(mapping: mapping)
        XCTAssertEqual(loaded?.manifest.tracks.count, 150)
    }

    /// Files disappearing after import are reported rather than rendered as playable tracks.
    func testMissingImportedFileIsReported() async throws {
        let zip = try archive([("123_002.mp3", Data([1]))])
        let root = directory.appendingPathComponent("library")
        let repository = LibraryRepository(root: root, readTitle: { _ in "Title" })
        let mapping = try TrackMapping.load()
        let saved = try await repository.importZIP(at: zip, mapping: mapping) { _, _ in }
        try FileManager.default.removeItem(
            at: root.appendingPathComponent(saved.directory).appendingPathComponent("123_002.mp3")
        )
        do {
            _ = try await repository.load(mapping: mapping)
            XCTFail("Expected missing file failure")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    /// Symlinks named like tracks must never be followed during extraction.
    func testRejectsSymlinkAudio() async throws {
        let zip = directory.appendingPathComponent("symlink.zip")
        let archive = try Archive(url: zip, accessMode: .create)
        let target = Data("/etc/passwd".utf8)
        try archive.addEntry(with: "123_002.mp3", type: .symlink, uncompressedSize: Int64(target.count)) {
            position, size in
            target.subdata(in: Int(position)..<(Int(position) + size))
        }
        let repository = LibraryRepository(root: directory.appendingPathComponent("library"), readTitle: { _ in "Title" })
        do {
            _ = try await repository.importZIP(at: zip, mapping: TrackMapping.load()) { _, _ in }
            XCTFail("Expected symlink failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Unsafe"))
        }
    }

    /// Startup reclaims both crash-interrupted imports and generations superseded before a process exit.
    func testStartupReclaimsOrphans() async throws {
        let root = directory.appendingPathComponent("library")
        let orphan = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        let repository = LibraryRepository(root: root, readTitle: { _ in "Title" })
        let mapping = try TrackMapping.load()
        let empty = try await repository.load(mapping: mapping)
        XCTAssertNil(empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        let zip = try archive([("123_002.mp3", Data([1]))])
        let original = try await repository.importZIP(at: zip, mapping: mapping) { _, _ in }
        let replacement = try await repository.importZIP(at: zip, mapping: mapping) { _, _ in }
        let reloaded = try await repository.load(mapping: mapping)
        XCTAssertEqual(reloaded?.directory, replacement.directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(original.directory).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(replacement.directory).path))
    }

    /// A reentrant load during progress delivery must not delete the in-flight generation.
    func testLoadDuringImportPreservesStaging() async throws {
        let root = directory.appendingPathComponent("library")
        let mapping = try TrackMapping.load()
        let repository = LibraryRepository(root: root, readTitle: { _ in "Title" })
        let zip = try archive([("123_002.mp3", Data([1]))])
        let saved = try await repository.importZIP(at: zip, mapping: mapping) { _, _ in
            do {
                let uncommitted = try await repository.load(mapping: mapping)
                XCTAssertNil(uncommitted)
            } catch {
                XCTFail("Reentrant load failed: \(error)")
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(saved.directory).appendingPathComponent("123_002.mp3").path
        ))
    }
}
