import SwiftUI

@main
struct IntroEditorApp: App {
    @State private var model: IntroEditorModel

    init() {
#if DEBUG
        if let suite = ProcessInfo.processInfo.environment["INTRO_EDITOR_TEST_PREFERENCES_SUITE"] {
            guard let defaults = UserDefaults(suiteName: suite) else {
                fatalError("Unable to create isolated test preferences.")
            }
            _model = State(initialValue: IntroEditorModel(userDefaults: defaults))
            return
        }
#endif
        _model = State(initialValue: IntroEditorModel())
    }

    var body: some Scene {
        Window("Gaelic Intro Editor", id: "intro-editor") {
            IntroEditorView(model: model)
                .task { model.restoreLastLocations() }
        }
        .defaultSize(width: 1120, height: 880)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Metadata…") { model.chooseMetadata() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Open Audio Folder…") { model.chooseAudioFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}
