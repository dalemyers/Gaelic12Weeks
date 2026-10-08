#if DEBUG
import Foundation
import Observation

enum MappingReviewError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let detail): "Mapping review: \(detail)"
        }
    }
}

enum MappingReviewDecision: String, Codable, CaseIterable {
    case unreviewed
    case confirmed
    case incorrect

    var label: String {
        switch self {
        case .unreviewed: "Unreviewed"
        case .confirmed: "Confirmed"
        case .incorrect: "Incorrect"
        }
    }
}

struct MappingReviewFields: Equatable {
    var group: MappedTrack.Group
    var lesson: String
    var section: String
    var subsection: String
    var title: String
    var note: String

    /// Populates editable fields without discarding optional sections or the original Unicode title.
    init(track: MappedTrack, note: String = "") {
        group = track.group
        lesson = track.lesson.map(String.init) ?? ""
        section = track.section.map(String.init) ?? ""
        subsection = track.subsection ?? ""
        title = track.title
        self.note = note
    }

    /// Builds a validated mapping row; only an explicit confirmation removes needsReview.
    func track(id: Int, decision: MappingReviewDecision) throws -> MappedTrack {
        let lessonNumber = group == .lesson ? try number(lesson, field: "Lesson") : nil
        let sectionNumber = group == .lesson ? try number(section, field: "Section") : nil
        let suffix = subsection.trimmingCharacters(in: .whitespacesAndNewlines)
        let track = MappedTrack(
            id: id, lesson: lessonNumber, section: sectionNumber,
            subsection: group == .lesson && !suffix.isEmpty ? suffix : nil,
            group: group, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            needsReview: decision != .confirmed
        )
        _ = try TrackMapping.decode(JSONEncoder().encode(TrackMapping(schemaVersion: 1, tracks: [track])))
        return track
    }

    /// Rejects malformed numeric input instead of silently turning it into an absent section.
    private func number(_ value: String, field: String) throws -> Int? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard text.allSatisfy(\.isASCII), text.allSatisfy(\.isNumber), let number = Int(text) else {
            throw MappingReviewError.invalid("\(field) must be a whole number.")
        }
        return number
    }
}

struct MappingReviewRecord: Codable {
    let original: MappedTrack
    let edited: MappedTrack
    let decision: MappingReviewDecision
    let note: String
    let pendingSectionDelta: Int?

    /// Older drafts have no pending delta; confirmed edits must never be propagated retroactively.
    var unappliedSectionDelta: Int {
        if decision == .confirmed { return 0 }
        if let pendingSectionDelta { return pendingSectionDelta }
        guard original.group == .lesson, edited.group == .lesson,
              let originalSection = original.section, let editedSection = edited.section else { return 0 }
        return editedSection - originalSection
    }
}

struct MappingReviewSaveResult {
    let sectionDelta: Int
    let shiftedTrackCount: Int
}

@MainActor
@Observable
final class MappingReviewStore {
    let source: TrackMapping
    private(set) var records: [Int: MappingReviewRecord] = [:]
    private(set) var isReady = false
    private let url: URL

    private struct Snapshot: Codable {
        let schemaVersion: Int
        let records: [MappingReviewRecord]
    }

    var orderedIDs: [Int] { source.tracks.map(\.id).sorted() }
    var confirmedCount: Int { records.values.filter { $0.decision == .confirmed }.count }
    var incorrectCount: Int { records.values.filter { $0.decision == .incorrect }.count }

    /// Keeps review drafts separate from the bundled mapping, audio generations and listening progress.
    init(source: TrackMapping, url: URL) {
        self.source = source
        self.url = url
    }

    /// Restores valid drafts without silently applying edits to a different version of a source row.
    func load() throws {
        isReady = false
        _ = try TrackMapping.decode(JSONEncoder().encode(source))
        guard FileManager.default.fileExists(atPath: url.path) else {
            records = [:]
            isReady = true
            return
        }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        guard snapshot.schemaVersion == 1 else {
            throw MappingReviewError.invalid("Unsupported saved review format. Export a backup or reset the draft.")
        }
        var loaded: [Int: MappingReviewRecord] = [:]
        for record in snapshot.records {
            let id = record.edited.id
            guard let original = source.tracks.first(where: { $0.id == id }),
                  record.original.id == id, loaded[id] == nil else {
                throw MappingReviewError.invalid("Saved review has unknown or duplicate track IDs.")
            }
            guard original == record.original || original == record.edited else {
                throw MappingReviewError.invalid(
                    "Bundled track \(id) changed since this draft was saved. Export a backup before resetting the draft."
                )
            }
            for track in [record.original, record.edited] {
                _ = try TrackMapping.decode(JSONEncoder().encode(TrackMapping(schemaVersion: 1, tracks: [track])))
            }
            guard record.edited.needsReview == (record.decision != .confirmed) else {
                throw MappingReviewError.invalid("Saved decision for track \(id) does not match its review flag.")
            }
            if let pending = record.pendingSectionDelta,
               pending != 0 && (record.decision == .confirmed || record.edited.section == nil) {
                throw MappingReviewError.invalid("Saved section correction for track \(id) is inconsistent.")
            }
            loaded[id] = MappingReviewRecord(
                original: original, edited: record.edited, decision: record.decision, note: record.note,
                pendingSectionDelta: record.unappliedSectionDelta
            )
        }
        records = loaded
        isReady = true
    }

    /// Returns the saved edit or the untouched bundled row.
    func track(_ id: Int) -> MappedTrack? {
        records[id]?.edited ?? source.tracks.first(where: { $0.id == id })
    }

    /// Untouched rows remain explicitly unreviewed, even if the source's needsReview flag is already false.
    func decision(_ id: Int) -> MappingReviewDecision {
        records[id]?.decision ?? .unreviewed
    }

    /// Restores both corrections and review notes for the editor.
    func fields(_ id: Int) -> MappingReviewFields? {
        guard let track = track(id) else { return nil }
        return MappingReviewFields(track: track, note: records[id]?.note ?? "")
    }

    /// Confirms section offsets across later unconfirmed tracks, committing the entire change atomically.
    /// Tentative corrections retain their pending offset until confirmation; invalid shifts throw without saving.
    @discardableResult
    func save(id: Int, fields: MappingReviewFields, decision: MappingReviewDecision) throws -> MappingReviewSaveResult {
        try requireReady()
        guard let original = source.tracks.first(where: { $0.id == id }) else {
            throw MappingReviewError.invalid("Track \(id) is not in the bundled mapping.")
        }
        let edited = try fields.track(id: id, decision: decision)
        let current = records[id]?.edited ?? original
        var pendingDelta = 0
        if let oldSection = current.section, let newSection = edited.section {
            let change = newSection - oldSection
            let (pending, overflow) = (records[id]?.unappliedSectionDelta ?? 0).addingReportingOverflow(change)
            guard !overflow else {
                throw MappingReviewError.invalid("The section correction is too large. No changes were saved.")
            }
            pendingDelta = pending
        }
        let sectionDelta = decision == .confirmed ? pendingDelta : 0
        var updated = records
        updated[id] = MappingReviewRecord(
            original: original, edited: edited, decision: decision, note: fields.note,
            pendingSectionDelta: decision == .confirmed ? 0 : pendingDelta
        )
        let shiftedCount = try shiftFollowingTracks(after: id, by: sectionDelta, in: &updated)
        try persist(updated)
        records = updated
        return MappingReviewSaveResult(sectionDelta: sectionDelta, shiftedTrackCount: shiftedCount)
    }

    /// Moves proposals in filename-ID order, preserving confirmed rows, notes, suffixes and pending manual edits.
    private func shiftFollowingTracks(
        after id: Int, by delta: Int, in updated: inout [Int: MappingReviewRecord]
    ) throws -> Int {
        guard delta != 0 else { return 0 }
        var shiftedCount = 0
        for original in source.tracks where original.id > id {
            let record = updated[original.id]
            let current = record?.edited ?? original
            guard current.group == .lesson, current.needsReview, let section = current.section else { continue }
            let (shiftedSection, overflow) = section.addingReportingOverflow(delta)
            guard !overflow, shiftedSection > 0 else {
                throw MappingReviewError.invalid(
                    "Shifting track \(current.id) would produce an invalid section number. No changes were saved."
                )
            }
            let shifted = MappedTrack(
                id: current.id, lesson: current.lesson, section: shiftedSection, subsection: current.subsection,
                group: current.group, title: current.title, needsReview: current.needsReview
            )
            updated[original.id] = MappingReviewRecord(
                original: original, edited: shifted, decision: record?.decision ?? .unreviewed,
                note: record?.note ?? "", pendingSectionDelta: record?.unappliedSectionDelta ?? 0
            )
            shiftedCount += 1
        }
        return shiftedCount
    }

    /// Exports every mapped ID in numeric order; no audio or review-only fields enter TrackMapping.json.
    func exportMapping() throws -> Data {
        try requireReady()
        let mapping = TrackMapping(
            schemaVersion: source.schemaVersion,
            tracks: source.tracks.map { records[$0.id]?.edited ?? $0 }.sorted { $0.id < $1.id }
        )
        let data = try encoder().encode(mapping)
        _ = try TrackMapping.decode(data)
        return data
    }

    /// Backs up the on-disk draft even when a corrupt/stale draft cannot be loaded into the editor.
    func exportBackup() throws -> Data {
        try Data(contentsOf: url)
    }

    /// Discards saved decisions only after the view obtains explicit confirmation.
    func reset() throws {
        _ = try TrackMapping.decode(JSONEncoder().encode(source))
        try persist([:])
        records = [:]
        isReady = true
    }

    /// Prevents a failed load from being overwritten by an ordinary edit.
    private func requireReady() throws {
        guard isReady else {
            throw MappingReviewError.invalid("The draft could not be loaded. Export a backup or reset it first.")
        }
    }

    /// Stores deterministic, readable review records without altering state when a write fails.
    private func persist(_ records: [Int: MappingReviewRecord]) throws {
        let snapshot = Snapshot(schemaVersion: 1, records: records.values.sorted { $0.edited.id < $1.edited.id })
        let data = try encoder().encode(snapshot)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Uses a stable JSON layout so exported corrections are straightforward to inspect and diff.
    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
#endif
