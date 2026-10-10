import SwiftUI

struct IntroEditorView: View {
    @Bindable var model: IntroEditorModel
    @State private var search = ""
    @State private var waveformAmplitudeScale: WaveformAmplitudeScale = .linear

    private var filteredTracks: [MappedTrack] {
        guard !search.isEmpty else { return model.tracks }
        return model.tracks.filter {
            "\($0.id) \(IntroEditorModel.location($0)) \($0.title)".localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Recordings").font(.headline)
                    Spacer()
                    Text("\(model.reviewedCount)/\(model.tracks.count) marked").foregroundStyle(.secondary)
                }
                .padding()
                List(selection: Binding(get: { model.selectedID }, set: { model.select(id: $0) })) {
                    ForEach(filteredTracks) { track in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(String(format: "%03d", track.id)).monospacedDigit()
                                Text(IntroEditorModel.location(track)).lineLimit(1)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text(track.title).lineLimit(2)
                            HStack(spacing: 5) {
                                Image(systemName: track.introEndSeconds == nil ? "circle" : "checkmark.circle.fill")
                                Text(track.introEndSeconds.map {
                                    $0 == 0 ? "No intro" : "Split at \(IntroEditorModel.time($0))"
                                } ?? "Unreviewed")
                                if model.audioFolderURL != nil, model.audioFiles[track.id] == nil {
                                    Text("· Audio missing").foregroundStyle(.red)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(track.introEndSeconds == nil ? Color.secondary : .teal)
                        }
                        .padding(.vertical, 4)
                        .tag(track.id)
                        .accessibilityIdentifier("introTrack-\(track.id)")
                    }
                }
                .searchable(text: $search, prompt: "Title, lesson, section or ID")
                .accessibilityIdentifier("introTrackList")
            }
            .navigationSplitViewColumnWidth(min: 260, ideal: 310, max: 420)
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                if let track = model.selectedTrack {
                    ScrollView { detail(track).frame(maxWidth: .infinity, alignment: .leading) }
                } else {
                    ContentUnavailableView {
                        Label("Mark the end of each spoken intro", systemImage: "waveform")
                    } description: {
                        Text("Open TrackMapping.json and the folder containing your extracted MP3s. "
                             + "Listen, position the playhead, then mark the split. Audio files are never changed.")
                    } actions: {
                        Button("Open Metadata…") { model.chooseMetadata() }
                    }
                }
                Spacer(minLength: 0)
                Divider()
                Text(model.status)
                    .font(.callout)
                    .accessibilityIdentifier("introStatus")
                if let url = model.metadataURL {
                    Text("Editing: \(url.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let url = model.audioFolderURL {
                    Text("Audio: \(url.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let backup = model.backupURL {
                    Text("Backup: \(backup.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(minWidth: 650, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .toolbar {
            Button("Open Metadata…", systemImage: "doc") { model.chooseMetadata() }
                .accessibilityIdentifier("openIntroMetadata")
            Button("Open Audio Folder…", systemImage: "folder") { model.chooseAudioFolder() }
                .accessibilityIdentifier("openIntroAudio")
            Button("Reload Metadata", systemImage: "arrow.clockwise") { model.reloadMetadata() }
                .disabled(model.metadataURL == nil)
                .accessibilityIdentifier("reloadIntroMetadata")
        }
        .alert("Unable to complete the action", isPresented: Binding(
            get: { model.errorMessage != nil || model.player.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil; model.player.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil; model.player.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? model.player.errorMessage ?? "")
        }
        .frame(minWidth: 980, minHeight: 760)
    }

    private func detail(_ track: MappedTrack) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("TRACK \(String(format: "%03d", track.id)) · \(IntroEditorModel.location(track))")
                .font(.headline).foregroundStyle(.secondary)
            Text(track.title).font(.largeTitle.bold()).textSelection(.enabled)
                .id(track.id)
                .accessibilityIdentifier("introTrackTitle")
            if let file = model.audioFiles[track.id] {
                Text(file.lastPathComponent).font(.caption).foregroundStyle(.secondary)
            }
            if let waveform = model.waveform {
                WaveformView(
                    waveform: waveform, position: model.player.position,
                    introEnd: track.introEndSeconds, isPlaying: model.player.isPlaying,
                    amplitudeScale: $waveformAmplitudeScale,
                    seek: { model.player.seek(to: $0) }
                )
                .id(track.id)
            } else if model.isLoadingWaveform {
                ProgressView("Decoding waveform…").frame(maxWidth: .infinity, minHeight: 250)
            } else {
                Text(model.player.isLoaded ? "Waveform unavailable. Playback is still available."
                     : "Open the audio folder to load this recording. Missing files cannot be played or marked.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            }
            IntroTransportView(player: model.player)
            Divider()
            HStack {
                Label(
                    track.introEndSeconds.map { $0 == 0 ? "No intro" : "Saved split: \(IntroEditorModel.time($0))" }
                        ?? "No split marked yet",
                    systemImage: "scissors"
                )
                .font(.headline)
                .accessibilityIdentifier("savedIntroMark")
                Spacer()
                Button("Clear mark") { model.save(seconds: nil) }
                    .disabled(track.introEndSeconds == nil)
                    .accessibilityIdentifier("clearIntroMark")
            }
            if let mark = track.introEndSeconds, model.player.isLoaded, mark >= model.player.duration {
                Text("The saved split is outside this audio file. Check that you selected the correct recording.")
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Mark intro end here") { model.mark() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("m", modifiers: [])
                    .accessibilityIdentifier("markIntroEnd")
                Button("Mark & Next") { model.mark(advance: true) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("markIntroAndNext")
                Button("No intro") { model.save(seconds: 0) }
                    .accessibilityIdentifier("markNoIntro")
            }
            .disabled(!model.canSave)
            HStack {
                Button("Play from split") { model.previewMark(preroll: 0) }
                Button("Listen 1s before split") { model.previewMark(preroll: 1) }
            }
            .disabled(!model.player.isLoaded || track.introEndSeconds == nil
                      || (track.introEndSeconds ?? 0) >= model.player.duration)
            HStack {
                Button("Previous recording") { model.move(offset: -1) }
                    .disabled(model.adjacentID(offset: -1) == nil)
                Button("Next recording") { model.move(offset: 1) }
                    .disabled(model.adjacentID(offset: 1) == nil)
                    .accessibilityIdentifier("nextIntroRecording")
                Spacer()
                Text("Marks save immediately. Original audio stays intact.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct IntroTransportView: View {
    @Bindable var player: IntroAudioPlayer

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(IntroEditorModel.time(player.position))
                    .accessibilityIdentifier("introPlayheadTime")
                Slider(
                    value: Binding(get: { player.position }, set: { player.seek(to: $0) }),
                    in: 0...max(0.001, player.duration)
                )
                .accessibilityLabel("Playback position")
                .accessibilityIdentifier("introSeekSlider")
                Text(IntroEditorModel.time(player.duration))
            }
            .font(.body.monospacedDigit())
            HStack(spacing: 12) {
                Button("−1s") { player.nudge(by: -1) }
                    .accessibilityLabel("Back 1 second")
                Button("−0.1s") { player.nudge(by: -0.1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .accessibilityLabel("Back 0.1 seconds")
                    .accessibilityIdentifier("introBackFine")
                Button { player.togglePlayback() } label: {
                    Label(player.isPlaying ? "Pause" : "Play", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 75)
                }
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityIdentifier("introPlayPause")
                Button("+0.1s") { player.nudge(by: 0.1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .accessibilityLabel("Forward 0.1 seconds")
                    .accessibilityIdentifier("introForwardFine")
                Button("+1s") { player.nudge(by: 1) }
                    .accessibilityLabel("Forward 1 second")
                    .accessibilityIdentifier("introForwardSecond")
                Spacer()
                Text("Fine steps pause playback").font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(!player.isLoaded)
    }
}

#if DEBUG
#Preview("Intro editor") { IntroEditorView(model: .preview()) }
#Preview("Open files") { IntroEditorView(model: .preview(empty: true)) }
#Preview("Transport") { IntroTransportView(player: IntroAudioPlayer()).padding().frame(width: 650) }
#endif
