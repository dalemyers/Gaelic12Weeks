import SwiftUI

@main
struct CompanionApp: App {
    @State private var library = LibraryModel()

    var body: some Scene {
        WindowGroup {
            LibraryView(library: library)
                .tint(.teal)
                .task { await library.load() }
        }
    }
}
