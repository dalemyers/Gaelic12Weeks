import Foundation

enum CompanionError: LocalizedError {
    case invalidMapping(String)
    case invalidArchive(String)
    case invalidLibrary(String)

    var errorDescription: String? {
        switch self {
        case .invalidMapping(let detail): "The track mapping is invalid. \(detail)"
        case .invalidArchive(let detail): "The ZIP could not be imported. \(detail)"
        case .invalidLibrary(let detail): "The saved library could not be loaded. \(detail)"
        }
    }
}

struct TrackMapping: Codable, Sendable {
    let schemaVersion: Int
    let tracks: [MappedTrack]

    /// Resolves all mapped recordings in a group or numbered section, including audio not yet imported.
    func trackIDs(for group: LibraryGroup, section: Int? = nil) -> Set<Int> {
        guard let first = group.tracks.first else { return [] }
        return Set(tracks.filter {
            $0.group == first.mapping.group && $0.lesson == first.mapping.lesson
                && (section == nil || $0.section == section)
        }.map(\.id))
    }

    /// Loads and validates the editable mapping bundled with the app.
    static func load(bundle: Bundle = .main) throws -> TrackMapping {
        guard let url = bundle.url(forResource: "TrackMapping", withExtension: "json") else {
            throw CompanionError.invalidMapping("TrackMapping.json is missing.")
        }
        return try decode(Data(contentsOf: url))
    }

    /// Decodes the mapping, rejecting ambiguous identifiers and invalid hierarchy fields.
    static func decode(_ data: Data) throws -> TrackMapping {
        let mapping = try JSONDecoder().decode(TrackMapping.self, from: data)
        guard mapping.schemaVersion == 1, !mapping.tracks.isEmpty else {
            throw CompanionError.invalidMapping("Expected schemaVersion 1 and at least one track.")
        }
        var ids = Set<Int>()
        for track in mapping.tracks {
            guard (2...999).contains(track.id), ids.insert(track.id).inserted,
                  !track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CompanionError.invalidMapping("Invalid or duplicate track ID/title: \(track.id).")
            }
            if track.group == .lesson {
                guard let lesson = track.lesson, (1...12).contains(lesson) else {
                    throw CompanionError.invalidMapping("Track \(track.id) needs a lesson between 1 and 12.")
                }
            } else if track.lesson != nil || track.section != nil || track.subsection != nil {
                throw CompanionError.invalidMapping("Bonus track \(track.id) must not have lesson or section fields.")
            }
            if let section = track.section, section < 1 {
                throw CompanionError.invalidMapping("Track \(track.id) has an invalid section.")
            }
            if let seconds = track.introEndSeconds, !seconds.isFinite || seconds < 0 {
                throw CompanionError.invalidMapping("Track \(track.id) has an invalid intro end time.")
            }
            if let subsection = track.subsection,
               track.section == nil || subsection.range(of: "^[a-z]+$", options: .regularExpression) == nil {
                throw CompanionError.invalidMapping("Track \(track.id) has an invalid subsection.")
            }
        }
        return mapping
    }
}

struct MappedTrack: Codable, Identifiable, Sendable, Equatable {
    enum Group: String, Codable, Sendable {
        case lesson
        case appendices
        case readingPractice
    }

    let id: Int
    let lesson: Int?
    let section: Int?
    let subsection: String?
    let group: Group
    let title: String
    let needsReview: Bool
    var introEndSeconds: Double? = nil

    var label: String {
        guard let section else { return title }
        return "Section \(section)\(subsection ?? "")"
    }
}

struct ImportedTrack: Codable, Identifiable, Sendable {
    let id: Int
    let filename: String
    let metadataTitle: String
}

struct LibraryManifest: Codable, Sendable {
    let schemaVersion: Int
    let tracks: [ImportedTrack]
}

struct LibraryTrack: Identifiable, Sendable {
    let mapping: MappedTrack
    let imported: ImportedTrack
    var id: Int { mapping.id }
}

struct LibrarySection: Identifiable {
    let number: Int?
    let tracks: [LibraryTrack]
    var id: String { number.map { "section-\($0)" } ?? "other" }
    var title: String { number.map { "Section \($0)" } ?? "Conversation & other audio" }
}

struct LibraryGroup: Identifiable {
    let id: String
    let title: String
    let tracks: [LibraryTrack]

    var sections: [LibrarySection] {
        let grouped = Dictionary(grouping: tracks, by: \.mapping.section)
        return grouped.keys.sorted { ($0 ?? Int.max) < ($1 ?? Int.max) }.map {
            LibrarySection(number: $0, tracks: grouped[$0, default: []].sorted { $0.id < $1.id })
        }
    }
}

enum Catalog {
    /// Recognizes the publisher's filename format without accepting paths or track zero.
    static func trackID(filename: String) -> Int? {
        guard filename.range(of: #"^[0-9]+_[0-9]{3}\.mp3$"#, options: .regularExpression) != nil,
              let suffix = filename.split(separator: "_").last,
              let id = Int(suffix.prefix(3)), id > 0 else { return nil }
        return id
    }

    /// Joins imported files with the current mapping so mapping edits also apply to existing libraries.
    static func groups(mapping: TrackMapping, imported: [ImportedTrack]) throws -> [LibraryGroup] {
        let byID = Dictionary(uniqueKeysWithValues: mapping.tracks.map { ($0.id, $0) })
        var seen = Set<Int>()
        let tracks = try imported.map { importedTrack in
            guard seen.insert(importedTrack.id).inserted, let entry = byID[importedTrack.id] else {
                throw CompanionError.invalidLibrary("Duplicate or unmapped track \(importedTrack.id).")
            }
            return LibraryTrack(mapping: entry, imported: importedTrack)
        }
        var groups = (1...12).map { (lesson: Int) in
            LibraryGroup(
                id: "lesson-\(lesson)", title: "Lesson \(lesson)",
                tracks: tracks.filter { $0.mapping.group == .lesson && $0.mapping.lesson == lesson }
                    .sorted { $0.id < $1.id }
            )
        }
        groups.append(LibraryGroup(
            id: "appendices", title: "Appendices",
            tracks: tracks.filter { $0.mapping.group == .appendices }.sorted { $0.id < $1.id }
        ))
        groups.append(LibraryGroup(
            id: "reading", title: "Reading Practice",
            tracks: tracks.filter { $0.mapping.group == .readingPractice }.sorted { $0.id < $1.id }
        ))
        return groups.filter { !$0.tracks.isEmpty }
    }
}
