#if DEBUG
import SwiftUI
import UniformTypeIdentifiers

struct MappingReviewDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    /// Wraps an export snapshot, not the live mutable draft.
    init(data: Data) {
        self.data = data
    }

    /// Reads JSON without interpreting its schema; validation belongs to the review store.
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    /// Writes exactly the validated snapshot selected for export.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct MappingReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let library: LibraryModel
    @State private var store: MappingReviewStore
    @State private var selectedID: Int?
    @State private var fields: MappingReviewFields?
    @State private var filter = ReviewFilter.unconfirmed
    @State private var showingTracks = false
    @State private var pendingAction: PendingAction?
    @State private var showingDiscard = false
    @State private var showingReset = false
    @State private var exportDocument: MappingReviewDocument?
    @State private var exportName = "TrackMapping"
    @State private var showingExporter = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var attemptedLoad = false
    @FocusState private var focusedField: EditorField?

    private enum EditorField: Hashable {
        case lesson, section, subsection, title, note
    }

    private enum PendingAction {
        case select(Int)
        case close
    }

    private enum ReviewFilter: String, CaseIterable {
        case unconfirmed = "Unconfirmed"
        case all = "All"
        case incorrect = "Incorrect"
        case confirmed = "Confirmed"
    }

    /// Opens the persistent DEBUG draft while leaving the normal library's mapping unchanged.
    init(mapping: TrackMapping, library: LibraryModel) {
        self.library = library
        _store = State(initialValue: MappingReviewStore(source: mapping, url: library.mappingReviewURL))
    }

    private var filteredIDs: [Int] {
        store.orderedIDs.filter { id in
            switch filter {
            case .all: true
            case .unconfirmed: store.decision(id) != .confirmed
            case .incorrect: store.decision(id) == .incorrect
            case .confirmed: store.decision(id) == .confirmed
            }
        }
    }

    private var isDirty: Bool {
        guard let selectedID, let fields else { return false }
        return fields != store.fields(selectedID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Review progress") {
                    Text("\(store.confirmedCount) of \(store.orderedIDs.count) confirmed; \(store.incorrectCount) incorrect")
                        .accessibilityIdentifier("reviewProgress")
                    Text("Edits stay in this DEBUG draft. Export the mapping to update the repository. "
                         + "Review playback does not mark recordings listened.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let notice {
                        Text(notice).font(.footnote).accessibilityIdentifier("reviewNotice")
                    }
                }
                if store.isReady {
                    selectionControls
                    if let id = selectedID, let fields {
                        editor(id: id, fields: fields)
                    }
                } else {
                    Section {
                        Text("The saved review could not be loaded. Export a backup before resetting it.")
                        Button("Export saved review backup") { export(backup: true) }
                    }
                }
                Section {
                    Button("Export corrected TrackMapping.json", systemImage: "square.and.arrow.up") {
                        export(backup: false)
                    }
                    .disabled(!store.isReady || isDirty)
                    .accessibilityIdentifier("exportMapping")
                    if store.isReady {
                        Button("Export saved review backup") { export(backup: true) }
                            .disabled(store.records.isEmpty)
                    }
                    if isDirty { Text("Save or confirm your changes before exporting.").font(.footnote) }
                    Button("Reset review draft", role: .destructive) { showingReset = true }
                        .accessibilityIdentifier("resetMappingReview")
                        .alert("Reset all review decisions and corrections?", isPresented: $showingReset) {
                            Button("Reset review draft", role: .destructive) {
                                do {
                                    try store.reset()
                                    select(store.orderedIDs.first)
                                    notice = "Review draft reset. Audio and listened progress were not changed."
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }.accessibilityIdentifier("confirmResetMappingReview")
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This discards saved and unsaved review edits. Export a backup first if needed.")
                        }
                }
            }
            .accessibilityIdentifier("reviewForm")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PlaybackView(player: library.player)
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Mapping review")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { request(.close) }.accessibilityIdentifier("closeMappingReview")
                        .alert("Discard unsaved changes?", isPresented: $showingDiscard) {
                            Button("Discard changes", role: .destructive) {
                                if let pendingAction { perform(pendingAction) }
                                pendingAction = nil
                            }.accessibilityIdentifier("discardReviewChanges")
                            Button("Keep editing", role: .cancel) { pendingAction = nil }
                                .accessibilityIdentifier("keepReviewEditing")
                        }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done editing") { focusedField = nil }
                        .accessibilityIdentifier("finishReviewEditing")
                }
            }
        }
        .interactiveDismissDisabled(isDirty)
        .task {
            guard !attemptedLoad else { return }
            attemptedLoad = true
            do {
                try store.load()
                select(store.orderedIDs.first { store.decision($0) != .confirmed } ?? store.orderedIDs.first)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingTracks) { trackPicker }
        .fileExporter(
            isPresented: $showingExporter, document: exportDocument,
            contentType: .json, defaultFilename: exportName
        ) { result in
            switch result {
            case .success: notice = "Export saved. No audio was included."
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .alert("Mapping review", isPresented: Binding(
            get: { errorMessage != nil || library.player.errorMessage != nil },
            set: { if !$0 { errorMessage = nil; library.player.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil; library.player.errorMessage = nil }
        } message: {
            Text(errorMessage ?? library.player.errorMessage ?? "")
        }
    }

    private var selectionControls: some View {
        Section("Choose a recording") {
            Picker("Show", selection: $filter) {
                ForEach(ReviewFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.accessibilityIdentifier("reviewFilter")
            Button("Choose track (\(filteredIDs.count) shown)") { showingTracks = true }
                .accessibilityIdentifier("chooseReviewTrack")
            HStack {
                Button("Previous", systemImage: "chevron.left") {
                    if let id = adjacentID(forward: false) { request(.select(id)) }
                }
                .disabled(adjacentID(forward: false) == nil)
                .accessibilityIdentifier("previousReviewTrack")
                Spacer()
                Button("Next", systemImage: "chevron.right") {
                    if let id = adjacentID(forward: true) { request(.select(id)) }
                }
                .disabled(adjacentID(forward: true) == nil)
                .accessibilityIdentifier("nextReviewTrack")
            }.buttonStyle(.borderless)
        }
    }

    /// Shows source metadata alongside editable mapping fields; absent imports remain reviewable but not playable.
    @ViewBuilder
    private func editor(id: Int, fields: MappingReviewFields) -> some View {
        let imported = library.saved?.manifest.tracks.first { $0.id == id }
        Section("Track \(String(format: "%03d", id))") {
            LabeledContent("Decision", value: store.decision(id).label)
                .accessibilityIdentifier("reviewDecision")
            LabeledContent("Filename", value: imported?.filename ?? "Not imported")
            Text("MP3 Title: \(imported?.metadataTitle ?? "Import audio to read its Title metadata")")
                .textSelection(.enabled)
                .accessibilityIdentifier("reviewSourceTitle")
            if let original = store.source.tracks.first(where: { $0.id == id }) {
                Text("Bundled: \(location(original)) - \(original.title)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Play this recording", systemImage: "play.circle") {
                Task {
                    guard selectedID == id, let track = store.track(id) else { return }
                    do { try await library.playForMappingReview(track) } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .disabled(imported == nil || library.player.isPreparing)
            .accessibilityIdentifier("playReviewTrack")
        }
        Section("Correct the mapping") {
            Picker("Group", selection: field(\.group, fallback: fields.group)) {
                Text("Lesson").tag(MappedTrack.Group.lesson)
                Text("Appendices").tag(MappedTrack.Group.appendices)
                Text("Reading Practice").tag(MappedTrack.Group.readingPractice)
            }.accessibilityIdentifier("reviewGroup")
            if fields.group == .lesson {
                TextField("Lesson (1–12)", text: field(\.lesson, fallback: fields.lesson))
                    .keyboardType(.numberPad).accessibilityIdentifier("reviewLesson")
                    .focused($focusedField, equals: .lesson)
                TextField("Section (blank for conversation)", text: field(\.section, fallback: fields.section))
                    .keyboardType(.numberPad).accessibilityIdentifier("reviewSection")
                    .focused($focusedField, equals: .section)
                TextField("Subsection (e.g. a; blank for main)", text: field(\.subsection, fallback: fields.subsection))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("reviewSubsection")
                    .focused($focusedField, equals: .subsection)
            }
            TextField("Title", text: field(\.title, fallback: fields.title), axis: .vertical)
                .accessibilityIdentifier("reviewTitle")
                .focused($focusedField, equals: .title)
            TextField("Review note (optional)", text: field(\.note, fallback: fields.note), axis: .vertical)
                .accessibilityIdentifier("reviewNote")
                .focused($focusedField, equals: .note)
        }
        Section {
            Button("Confirm & next", systemImage: "checkmark.circle") { save(.confirmed, advance: true) }
                .accessibilityIdentifier("confirmReviewTrack")
            Button("Save correction for review", systemImage: "square.and.arrow.down") { save(.unreviewed) }
                .accessibilityIdentifier("saveReviewCorrection")
            Button("Mark incorrect", systemImage: "xmark.circle") { save(.incorrect) }
                .accessibilityIdentifier("rejectReviewTrack")
            Text("Confirm clears needsReview. Save correction or Incorrect keeps it set. "
                 + "Notes are included in the review backup, not TrackMapping.json.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Confirming a section-number change shifts later unconfirmed numbered recordings "
                 + "by the same amount, across all lessons. Saved corrections wait until confirmation. "
                 + "Confirmed tracks, unnumbered recordings and titles stay unchanged.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var trackPicker: some View {
        NavigationStack {
            List(filteredIDs, id: \.self) { id in
                if let track = store.track(id) {
                    Button {
                        showingTracks = false
                        request(.select(id))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(String(format: "%03d", id)) - \(track.title)")
                            Text("\(location(track)) · \(store.decision(id).label)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("review-track-\(id)")
                }
            }
            .navigationTitle("Choose track")
            .overlay {
                if filteredIDs.isEmpty { ContentUnavailableView("No matching tracks", systemImage: "checklist") }
            }
            .toolbar { Button("Done") { showingTracks = false } }
        }
    }

    /// Binds value-type form fields without mutating the saved draft until an explicit save.
    private func field<Value>(_ keyPath: WritableKeyPath<MappingReviewFields, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { fields?[keyPath: keyPath] ?? fallback }, set: { fields?[keyPath: keyPath] = $0 })
    }

    /// Finds the adjacent filtered ID without wrapping or silently skipping a pending edit.
    private func adjacentID(forward: Bool) -> Int? {
        guard let selectedID else { return filteredIDs.first }
        return forward ? filteredIDs.first { $0 > selectedID } : filteredIDs.last { $0 < selectedID }
    }

    /// Replaces the editor and stops the preceding recording so visible metadata always matches the audition.
    private func select(_ id: Int?) {
        focusedField = nil
        library.player.stop()
        selectedID = id
        fields = id.flatMap { store.fields($0) }
    }

    /// Requires a discard decision before navigating away from unsaved corrections.
    private func request(_ action: PendingAction) {
        if case .select(let id) = action, id == selectedID { return }
        focusedField = nil
        guard !isDirty else {
            pendingAction = action
            showingDiscard = true
            return
        }
        perform(action)
    }

    /// Executes navigation only after any unsaved changes have been addressed.
    private func perform(_ action: PendingAction) {
        switch action {
        case .select(let id): select(id)
        case .close: dismiss()
        }
    }

    /// Commits a decision before advancing; a failed validation/write leaves the editor intact.
    private func save(_ decision: MappingReviewDecision, advance: Bool = false) {
        guard let selectedID, let fields else { return }
        do {
            let result = try store.save(id: selectedID, fields: fields, decision: decision)
            let confirmation = "Track \(String(format: "%03d", selectedID)): \(decision.label.lowercased())."
            if result.shiftedTrackCount > 0 {
                let delta = result.sectionDelta > 0 ? "+\(result.sectionDelta)" : "\(result.sectionDelta)"
                notice = "\(confirmation) Shifted \(result.shiftedTrackCount) later unconfirmed recordings by \(delta)."
            } else {
                notice = confirmation
            }
            select(advance ? adjacentID(forward: true) ?? selectedID : selectedID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Exports a stable saved snapshot, preserving the app's no-audio-distribution boundary.
    private func export(backup: Bool) {
        do {
            exportDocument = MappingReviewDocument(data: try backup ? store.exportBackup() : store.exportMapping())
            exportName = backup ? "MappingReview-backup" : "TrackMapping"
            showingExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Describes the complete hierarchy even when a row has no numbered main section.
    private func location(_ track: MappedTrack) -> String {
        switch track.group {
        case .lesson:
            let section = track.section.map { "Section \($0)\(track.subsection ?? "")" } ?? "Unnumbered recording"
            return "Lesson \(track.lesson.map(String.init) ?? "?"), \(section)"
        case .appendices: return "Appendices"
        case .readingPractice: return "Reading Practice"
        }
    }
}
#endif
