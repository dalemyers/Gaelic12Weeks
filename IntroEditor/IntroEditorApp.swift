import SwiftUI

@main
struct IntroEditorApp: App {
    @State private var model = IntroEditorModel()

    var body: some Scene {
        Window("Gaelic Intro Editor", id: "intro-editor") {
            IntroEditorView(model: model)
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
