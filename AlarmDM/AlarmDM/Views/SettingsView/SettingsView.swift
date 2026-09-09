//
//  SettingsView.swift
//  AlarmDM
//
//  The Ostalo tab: what is on disk, where to find the show elsewhere, and how
//  to reach the person who made the app.
//

import SwiftUI
import WebKit

// MARK: - View model

final class SettingsViewModel: ObservableObject {

    @Published private(set) var downloadedCount = 0
    @Published private(set) var downloadedBytes: Int64 = 0
    @Published var deleteFailureMessage: String?

    private let fileService: FileServiceProtocol
    private let repository = PodcastRepository.shared

    init(fileService: FileServiceProtocol = FileService()) {
        self.fileService = fileService
        refresh()
    }

    var hasDownloads: Bool { downloadedCount > 0 }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
    }

    var downloadsSummary: String {
        guard hasDownloads else { return "Nema preuzetih epizoda" }
        let noun: String
        switch downloadedCount % 10 {
        case 1 where downloadedCount % 100 != 11: noun = "epizoda"
        case 2...4 where !(12...14).contains(downloadedCount % 100): noun = "epizode"
        default: noun = "epizoda"
        }
        return "\(downloadedCount) \(noun) · \(formattedSize)"
    }

    func refresh() {
        downloadedCount = fileService.downloadedFiles().count
        downloadedBytes = fileService.downloadedBytes()
    }

    func deleteAllDownloads() {
        switch fileService.deleteAllDownloads() {
        case .success:
            repository.clearAllDownloadReferences()
            deleteFailureMessage = nil
        case .failure(let error):
            deleteFailureMessage = "Brisanje nije uspelo: \(error.localizedDescription)"
        }
        refresh()
    }
}

// MARK: - View

struct SettingsView: View {

    @StateObject private var viewModel = SettingsViewModel()
    @State private var showDeleteConfirmation = false
    @Environment(\.openURL) private var openURL

    private enum Links {
        static let about = URL(string: "https://www.daskoimladja.com/o-nama.php")!
        static let shop = URL(string: "https://daskoimladja.bigcartel.com/")!
        static let authorEmail = "markostajic@gmail.com"
    }

    var body: some View {
        List {
            downloadsSection
            showSection
            appSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Ostalo")
        .onAppear { viewModel.refresh() }
        .confirmationDialog(
            "Obrisati sve preuzete epizode?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Obriši", role: .destructive) { viewModel.deleteAllDownloads() }
            Button("Odustani", role: .cancel) {}
        } message: {
            Text("Epizode ostaju dostupne za slušanje preko interneta i možeš ih ponovo preuzeti.")
        }
    }

    // MARK: Sections

    private var downloadsSection: some View {
        Section("Preuzeto") {
            HStack {
                Label("Na telefonu", systemImage: "arrow.down.circle")
                Spacer()
                Text(viewModel.downloadsSummary)
                    .foregroundColor(.secondary)
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Obriši sve preuzete epizode", systemImage: "trash")
            }
            .disabled(!viewModel.hasDownloads)

            if let message = viewModel.deleteFailureMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
    }

    private var showSection: some View {
        Section("Daško i Mlađa") {
            NavigationLink {
                WebPageView(url: Links.about, title: "O nama")
            } label: {
                Label("O nama", systemImage: "info.circle")
            }

            Link(destination: Links.shop) {
                HStack {
                    Label("Prodavnica", systemImage: "bag")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var appSection: some View {
        Section("Aplikacija") {
            Button {
                openURL(supportMailURL())
            } label: {
                HStack {
                    Label("Kontaktiraj autora", systemImage: "envelope")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Text("Verzija")
                Spacer()
                Text(Self.appVersion)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: Helpers

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    /// Pre-fills the version and OS, so a bug report arrives with the two facts
    /// that are always missing from one.
    private func supportMailURL() -> URL {
        let subject = "AlarmDM \(Self.appVersion)"
        let body = "\n\n---\nAplikacija: \(Self.appVersion)\niOS: \(UIDevice.current.systemVersion)"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Links.authorEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url ?? URL(string: "mailto:\(Links.authorEmail)")!
    }
}

// MARK: - Web page

/// Used for the "O nama" text, which lives on the site and changes there.
struct WebPageView: View {
    let url: URL
    let title: String

    @State private var isLoading = true

    var body: some View {
        ZStack {
            WebView(url: url, isLoading: $isLoading)
            if isLoading {
                ProgressView()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isLoading: $isLoading) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let isLoading: Binding<Bool>

        init(isLoading: Binding<Bool>) {
            self.isLoading = isLoading
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading.wrappedValue = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading.wrappedValue = false
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
