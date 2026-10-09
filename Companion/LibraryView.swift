import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var library: LibraryModel
    @State private var showingImporter = false
    @State private var showingInstructions = false
    @State private var confirmingReplacement = false
    @State private var requestingReplacement = false
    @State private var confirmingProgressReset = false
#if DEBUG
    @State private var showingMappingReview = false
#endif

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                Group {
                    if library.isLoading {
                        ProgressView("Loading library")
                    } else if library.groups.isEmpty {
                        welcome
                    } else {
                        lessons
                    }
                }
                .navigationTitle("Gaelic Companion")
                .toolbar {
                    if library.saved != nil {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("About & download", systemImage: "info.circle") { showingInstructions = true }
                                .accessibilityIdentifier("aboutAudio")
                        }
                    }
                }
            }
            .id(library.saved?.directory ?? "empty-library")
            VStack(spacing: 0) {
                if library.isImporting { importProgress }
                if library.saved != nil {
                    PlaybackView(player: library.player)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .fileImporter(
            isPresented: $showingImporter, allowedContentTypes: [.zip], allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    library.errorMessage = "No ZIP file was selected."
                    return
                }
                library.importZIP(url)
            case .failure(let error):
                library.errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog("Replace imported audio?", isPresented: $confirmingReplacement, titleVisibility: .visible) {
            Button("Choose replacement ZIP") { showingImporter = true }
        } message: {
            Text("Your current library stays available unless the new ZIP imports successfully.")
        }
        .sheet(isPresented: $showingInstructions, onDismiss: {
            guard requestingReplacement else { return }
            requestingReplacement = false
            confirmingReplacement = true
        }) {
            VStack(spacing: 0) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Skip spoken introductions", isOn: $library.skipSpokenIntroductions)
                                    .accessibilityIdentifier("skipSpokenIntroductions")
                                Text("Start recordings at their marked intro end. Recordings without a valid mark "
                                     + "play from the beginning. Pausing and resuming keeps your place, and you can "
                                     + "still seek back into an introduction.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            instructions
                            if library.saved != nil {
                                Button("Replace imported audio", systemImage: "square.and.arrow.down") {
                                    // Wait for About to dismiss before presenting the root confirmation and picker.
                                    requestingReplacement = true
                                    showingInstructions = false
                                }
                                .disabled(library.isLoading || library.isImporting || library.mapping == nil)
                                .accessibilityIdentifier("replaceAudio")
                            }
#if DEBUG
                            Button("Review audio mapping (DEBUG)", systemImage: "checklist") {
                                do {
                                    try library.beginMappingReview()
                                    showingMappingReview = true
                                } catch {
                                    library.errorMessage = error.localizedDescription
                                }
                            }
                            .disabled(library.mapping == nil || library.isLoading || library.isImporting)
                            .accessibilityIdentifier("reviewMapping")
#endif
                            Text("A lesson is marked listened after every mapped recording finishes. "
                                 + "Use the lesson menu or swipe a row to mark it manually. "
                                 + "Replacing the ZIP keeps your progress.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Reset all listening progress", role: .destructive) {
                                confirmingProgressReset = true
                            }
                        }.padding(24)
                    }
                    .accessibilityIdentifier("aboutScroll")
                    .navigationTitle("About & download")
                    .toolbar { Button("Done") { showingInstructions = false } }
                    .confirmationDialog("Reset all listening progress?", isPresented: $confirmingProgressReset) {
                        Button("Reset progress", role: .destructive) { library.resetProgress() }
                    } message: {
                        Text("All lessons and recordings will be marked unlistened. Your audio will not be removed.")
                    }
                }
                PlaybackView(player: library.player)
                    .fixedSize(horizontal: false, vertical: true)
            }
#if DEBUG
            .sheet(isPresented: $showingMappingReview, onDismiss: library.endMappingReview) {
                if let mapping = library.mapping {
                    MappingReviewView(mapping: mapping, library: library)
                }
            }
#endif
        }
        .alert("Unable to complete action", isPresented: Binding(
            get: { library.errorMessage != nil || library.player.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil; library.player.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { library.errorMessage = nil; library.player.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? library.player.errorMessage ?? "")
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                instructions
                Button {
                    showingImporter = true
                } label: {
                    Label("Import downloaded ZIP", systemImage: "folder")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(library.isImporting || library.mapping == nil)
                .accessibilityIdentifier("welcomeImport")
            }.padding(24).frame(maxWidth: 650, alignment: .leading).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("welcomeScroll")
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "headphones")
                    .font(.system(size: 52)).foregroundStyle(.teal)
                    .accessibilityHidden(true)
                Text(LibraryModel.appName).font(.headline)
            }
            Text("An independent listening companion. Not affiliated with or endorsed by the book's authors or publisher.")
                .foregroundStyle(.secondary)
            Text("1. Open the publisher's audio page and download the ZIP yourself.")
            Link(destination: LibraryModel.downloadURL) {
                Label("Open publisher's download page", systemImage: "arrow.up.right.square")
            }.accessibilityIdentifier("publisherLink")
            Text("2. Save the ZIP in Files. If your browser extracts it automatically, keep or download the original ZIP.")
            Text(library.saved == nil
                 ? "3. Return here and choose Import downloaded ZIP, then select the ZIP."
                 : "3. Choose Replace imported audio in About & download, then select the new ZIP.")
            Text("No recordings are bundled or downloaded automatically. Import only audio you are entitled to use. "
                 + "Imported recordings stay on this device and are excluded from the app's cloud backup.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var lessons: some View {
        List {
            if library.hasProvisionalMapping || library.importedCount < library.expectedCount {
                Section {
                    if library.hasProvisionalMapping {
                        Label("Some lesson and section assignments are provisional.", systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if library.importedCount < library.expectedCount {
                        Text("Only imported recordings are shown. Use About & download to import a complete ZIP.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                ForEach(library.groups) { group in
                    NavigationLink {
                        GroupView(group: group, library: library)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: group.id.hasPrefix("lesson-") ? "book.closed" : "text.book.closed")
                                .foregroundStyle(.teal).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.title).font(.headline)
                                Text("\(group.tracks.count) recordings").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if library.progress.isListened(library.trackIDs(for: group)) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.teal).accessibilityLabel("Listened")
                            }
                        }.padding(.vertical, 5)
                    }
                    .accessibilityIdentifier(group.id)
                    .swipeActions {
                        let ids = library.trackIDs(for: group)
                        let listened = library.progress.isListened(ids)
                        Button(listened ? "Mark unlistened" : "Mark listened",
                               systemImage: listened ? "circle" : "checkmark.circle") {
                            library.setListened(!listened, ids: ids)
                        }.tint(.teal)
                    }
                }
            }
        }.accessibilityIdentifier("libraryList")
    }

    private var importProgress: some View {
        VStack(spacing: 12) {
            if library.total > 0 {
                ProgressView(value: Double(library.completed), total: Double(library.total))
                Text("Importing \(library.completed) of \(library.total) recordings").font(.subheadline)
            } else {
                ProgressView("Inspecting ZIP")
            }
            Button("Cancel import", role: .cancel) { library.cancelImport() }
        }.padding().frame(maxWidth: .infinity).background(.regularMaterial)
    }
}

private struct GroupView: View {
    let group: LibraryGroup
    let library: LibraryModel

    var body: some View {
        List(group.tracks) { track in
            TrackRow(track: track, library: library)
        }
        .accessibilityIdentifier("groupList")
        .navigationTitle(group.title)
        .toolbar {
            Menu {
                let ids = library.trackIDs(for: group)
                let listened = library.progress.isListened(ids)
                Button(listened ? "Mark unlistened" : "Mark listened",
                       systemImage: listened ? "circle" : "checkmark.circle") {
                    library.setListened(!listened, ids: ids)
                }.accessibilityIdentifier("toggleLessonListened")
            } label: {
                Label("Lesson actions", systemImage: "ellipsis.circle")
            }.accessibilityIdentifier("lessonActions")
        }
    }
}

private struct TrackRow: View {
    let track: LibraryTrack
    let library: LibraryModel

    var body: some View {
        Button {
            library.play(track)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: library.player.currentTrack?.id == track.id ? "speaker.wave.2.fill" : "play.circle")
                    .foregroundStyle(library.player.currentTrack?.id == track.id ? Color.teal : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    if track.mapping.section != nil {
                        Text(track.mapping.label).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(track.mapping.title).foregroundStyle(.primary)
                    if track.mapping.needsReview {
                        Text("Provisional mapping").font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
                if library.progress.isListened([track.id]) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.teal).accessibilityLabel("Listened")
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play \(track.mapping.label), \(track.mapping.title)")
        .accessibilityIdentifier("track-\(track.id)")
        .accessibilityValue(library.progress.isListened([track.id]) ? "Listened" : "Unlistened")
        .swipeActions {
            let listened = library.progress.isListened([track.id])
            Button(listened ? "Mark unlistened" : "Mark listened") {
                library.setListened(!listened, ids: [track.id])
            }.tint(.teal)
        }
    }
}

struct PlaybackView: View {
    @Bindable var player: AudioPlayer

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.mapping.title ?? "Select a recording")
                        .font(.subheadline.bold()).lineLimit(2)
                    Text("\(time(player.position)) / \(time(player.duration))")
                        .monospacedDigit().font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { player.skipBackward() } label: {
                    Image(systemName: "gobackward.5").font(.title2)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back 5 seconds")
                .accessibilityIdentifier("skipBackward")
                Button { Task { await player.toggle() } } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.largeTitle).frame(width: 44, height: 44)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("togglePlayback")
                Button { player.skipForward() } label: {
                    Image(systemName: "goforward.5").font(.title2)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Forward 5 seconds")
                .accessibilityIdentifier("skipForward")
            }
            .buttonStyle(.borderless)
            Slider(value: Binding(get: { player.position }, set: { player.seek(to: $0) }),
                   in: 0...max(player.duration, 0.01))
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(time(player.position)) of \(time(player.duration))")
                .accessibilityIdentifier("playbackPosition")
        }
        .disabled(player.currentTrack == nil || player.isPreparing)
        .padding(.horizontal)
        .padding(.top, 8)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("miniPlayer")
    }

    /// Formats finite audio durations for the elapsed and total time labels.
    private func time(_ value: TimeInterval) -> String {
        let seconds = Int(max(0, value))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

#if DEBUG
#Preview("Onboarding") {
    LibraryView(library: LibraryModel.preview(imported: false))
        .tint(.teal)
}

#Preview("Imported library") {
    LibraryView(library: LibraryModel.preview())
        .tint(.teal)
}

#Preview("Lesson sections and subsections") {
    let library = LibraryModel.preview()
    NavigationStack {
        GroupView(group: library.groups[0], library: library)
    }
    .tint(.teal)
}

#Preview("Recording row", traits: .sizeThatFitsLayout) {
    let library = LibraryModel.preview()
    List {
        TrackRow(track: library.groups[0].tracks[0], library: library)
    }
    .frame(height: 140)
    .tint(.teal)
}

#Preview("Player", traits: .sizeThatFitsLayout) {
    PlaybackView(player: AudioPlayer())
        .tint(.teal)
}
#endif
