import SwiftUI

enum AppInformation {
    static let shortName = "Unofficial Gaelic Companion"
    static let fullName = "Unofficial Companion to \"Scottish Gaelic in Twelve Weeks\""
    static let supportURL = URL(string: "https://app.myers.io/gaelic_companion")!
    static let privacyURL = supportURL.appendingPathComponent("privacy")
}

enum AppDocument: String, Identifiable, CaseIterable {
    case privacy = "PrivacyPolicy"
    case acknowledgements = "Acknowledgements"

    var id: String { rawValue }
    var title: String { self == .privacy ? "Privacy policy" : "Acknowledgements" }

    func contents(bundle: Bundle = .main) throws -> String {
        guard let url = bundle.url(forResource: rawValue, withExtension: "txt") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

struct AppInformationLinks: View {
    @State private var document: AppDocument?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Link("Support", destination: AppInformation.supportURL)
                .accessibilityIdentifier("appSupport")
            Button("Privacy policy") { document = .privacy }
                .accessibilityIdentifier("appPrivacy")
            Button("Acknowledgements") { document = .acknowledgements }
                .accessibilityIdentifier("appAcknowledgements")
        }
        .sheet(item: $document) { document in
            AppDocumentView(document: document)
        }
    }
}

private struct AppDocumentView: View {
    let document: AppDocument
    @Environment(\.dismiss) private var dismiss
    @State private var contents: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let contents {
                        Text(contents).textSelection(.enabled)
                            .accessibilityIdentifier("appDocumentContents")
                    } else if let errorMessage {
                        ContentUnavailableView(
                            "Document unavailable", systemImage: "exclamationmark.triangle",
                            description: Text(errorMessage)
                        )
                    } else {
                        ProgressView()
                    }
                    if document == .privacy {
                        Link("Privacy policy online", destination: AppInformation.privacyURL)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .task {
                do {
                    contents = try document.contents()
                } catch {
                    errorMessage = "The bundled document could not be read: \(error.localizedDescription)"
                }
            }
        }
    }
}
