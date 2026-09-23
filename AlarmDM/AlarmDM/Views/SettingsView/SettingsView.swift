//
//  SettingsView.swift
//  AlarmDM
//
//  The Ostalo tab: what is on disk, where to find the show elsewhere, and how
//  to reach the person who made the app.
//

import SwiftUI
import UIKit
import WebKit

// MARK: - View model

final class SettingsViewModel: ObservableObject {

    @Published private(set) var bookmarkCount = 0
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
        guard hasDownloads else { return String(localized: "Nema preuzetih epizoda") }
        // The plural rules live in the string catalog — Serbian has three
        // forms, English two, and neither belongs in a switch here.
        let episodes = String(localized: "\(downloadedCount) epizoda")
        return "\(episodes) · \(formattedSize)"
    }

    var bookmarksSummary: String {
        guard bookmarkCount > 0 else { return String(localized: "Nema zabeleški") }
        return String(localized: "\(bookmarkCount) zabeleška")
    }

    func refresh() {
        downloadedCount = fileService.downloadedFiles().count
        downloadedBytes = fileService.downloadedBytes()
        bookmarkCount = BookmarkLibrary.shared.all().count
    }

    #if DEBUG
    /// A first install, without the install: files, both stores, the iCloud
    /// zone and the defaults. What is left is what a phone that has never seen
    /// this app has.
    @MainActor
    func eraseEverything() async -> String {
        var report: [String] = []

        switch fileService.deleteAllDownloads() {
        case .success: report.append("fajlovi: preuzeto obrisano")
        case .failure(let error): report.append("fajlovi: \(error.localizedDescription)")
        }

        report.append(contentsOf: await AppDatabase.shared.eraseEverything())

        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
            report.append("podešavanja: vraćena")
        }

        refresh()
        return report.joined(separator: "\n")
    }
    #endif

    func deleteAllDownloads() {
        switch fileService.deleteAllDownloads() {
        case .success:
            repository.clearAllDownloadReferences()
            deleteFailureMessage = nil
        case .failure(let error):
            deleteFailureMessage = String(localized: "Brisanje nije uspelo: \(error.localizedDescription)")
        }
        refresh()
    }
}

// MARK: - View

struct SettingsView: View {

    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject private var settings = AppSettings.shared
    @State private var showDeleteConfirmation = false
    #if DEBUG
    @State private var showEraseConfirmation = false
    @State private var eraseReport: String?
    #endif
    #if DEBUG && !targetEnvironment(macCatalyst)
    @State private var isComposingLogMail = false
    #endif
    @Environment(\.openURL) private var openURL

    private enum Links {
        static let about = URL(string: "https://www.daskoimladja.com/o-nama.php")!
        static let shop = URL(string: "https://daskoimladja.bigcartel.com/")!
        static let instagram = URL(string: "https://www.instagram.com/daskoimladja")!
        /// The studio number, as it already lives in AppConstants.
        static let sms = URL(string: "sms:\(AppConstants.phoneNumber)")!
        static let authorEmail = "marko.stajic@gmail.com"
    }

    var body: some View {
        List {
            bookmarksSection
            networkSection
            statisticsSection
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
        #if DEBUG
        .confirmationDialog(
            "Obrisati baš sve?",
            isPresented: $showEraseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Obriši sve", role: .destructive) {
                Task { eraseReport = await viewModel.eraseEverything() }
            }
            Button("Odustani", role: .cancel) {}
        } message: {
            Text("Zabeleške, omiljeno, dokle si stigao, preuzete epizode i podešavanja - i ovde i u iCloudu, dakle i na ostalim uređajima. Očisti sve uređaje pre nego što ijedan ponovo pokreneš, inače onaj koji još ima podatke vrati sve u iCloud.")
        }
        .alert("Obrisano", isPresented: Binding(get: { eraseReport != nil },
                                               set: { if !$0 { eraseReport = nil } })) {
            // The container in memory still points at stores that were just
            // emptied under it. A restart is the honest way to see the state
            // that the next launch will actually find.
            Button("Zatvori aplikaciju") { exit(0) }
            Button("Kasnije", role: .cancel) { eraseReport = nil }
        } message: {
            Text(eraseReport ?? "")
        }
        #endif
        #if DEBUG && !targetEnvironment(macCatalyst)
        .sheet(isPresented: $isComposingLogMail) {
            MailComposeView(recipient: Links.authorEmail,
                            subject: "AlarmDM log \(Self.appVersion)",
                            body: Self.diagnosticsBody,
                            attachments: AppLog.exportURLs)
                .ignoresSafeArea()
        }
        #endif
    }

    // MARK: Sections

    private var bookmarksSection: some View {
        Section {
            NavigationLink {
                BookmarksView()
            } label: {
                HStack {
                    Label("Zabeleženo", systemImage: "bookmark")
                    Spacer()
                    Text(viewModel.bookmarksSummary)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var networkSection: some View {
        Section {
            Toggle(isOn: settings.downloadsOverWiFiOnlyBinding) {
                Label("Preuzimanje samo preko WiFi-ja", systemImage: "wifi")
            }
        } footer: {
            Text("Slušanje uživo i strimovanje epizoda rade uvek. Ovo se odnosi samo na preuzimanje - kad si na mobilnoj mreži, aplikacija će pitati pre nego što skine epizodu.")
        }
    }

    private var statisticsSection: some View {
        Section {
            Toggle(isOn: settings.suppressesUsageStatisticsBinding) {
                Label("Ne šalji anonimnu statistiku", systemImage: "chart.bar.xaxis")
            }
        } footer: {
            Text("Aplikacija broji koliko se koja stvar koristi - na primer koliko puta je napravljena zabeleška. Ne šalje se ko si, šta si zabeležio ni šta slušaš, i ništa se ne povezuje sa tobom.")
        }
    }

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

            Link(destination: Links.instagram) {
                externalRow("Instagram", detail: "@daskoimladja", systemImage: "at")
            }

            Link(destination: Links.shop) {
                externalRow("Prodavnica", systemImage: "bag")
            }

            Button {
                openURL(Links.sms)
            } label: {
                externalRow("Pošalji SMS", detail: "066 442 266", systemImage: "message")
            }
        }
    }

    /// A row that leaves the app, marked as such.
    private func externalRow(_ title: LocalizedStringKey, detail: String? = nil, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if let detail {
                Text(detail)
                    .foregroundColor(.secondary)
            }
            Image(systemName: "arrow.up.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }

    private var appSection: some View {
        Section("Aplikacija") {
            Button {
                openURL(supportMailURL())
            } label: {
                externalRow("Kontaktiraj autora", systemImage: "envelope")
            }

            #if !targetEnvironment(macCatalyst)
            // iOS keeps a language per app, apart from the phone's, and offers
            // the choice on the app's own page in Settings once there is more
            // than one language to choose from. A picker of our own would
            // change the app and leave CarPlay, the share sheet and every
            // system dialog behind in the other language. The Mac has the same
            // setting in System Settings, under Language & Region.
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                externalRow("Jezik", detail: Self.languageName, systemImage: "globe")
            }
            #endif

            HStack {
                Text("Verzija")
                Spacer()
                Text(Self.appVersion)
                    .foregroundColor(.secondary)
            }

            #if DEBUG
            // The whole point of writing the log to a file: getting it off the
            // phone from wherever the thing went wrong, without a cable and
            // without a Mac. Debug builds only — a shipped app has no business
            // offering this.
            ShareLink(item: AppLog.fileURL) {
                externalRow("Izvezi log", systemImage: "square.and.arrow.up")
            }
            #endif

            #if DEBUG && !targetEnvironment(macCatalyst)
            // The same file, one step shorter: a draft addressed to me with
            // this session and the one before it already attached, so nothing
            // has to be found in Files first.
            Button {
                if MailComposeView.canSend {
                    isComposingLogMail = true
                } else {
                    // No mail account on the device. The draft would open with
                    // nowhere to go, so this falls back to the plain contact
                    // mail and leaves the log to the share sheet above.
                    openURL(supportMailURL())
                }
            } label: {
                externalRow("Pošalji log na mejl", systemImage: "envelope.badge")
            }
            #endif

            #if DEBUG
            Button(role: .destructive) {
                showEraseConfirmation = true
            } label: {
                Label("Obriši sve podatke i iCloud", systemImage: "trash.slash")
            }
            #endif
        }
    }

    // MARK: Helpers

    /// The language the app is actually showing, in that language — which is
    /// the one worth naming, since it may not be the phone's.
    private static var languageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "sr-Latn"
        let name = Locale(identifier: code).localizedString(forIdentifier: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    /// The version and the OS, plus how much log is attached — an empty file
    /// is worth noticing before reading it rather than after.
    private static var diagnosticsBody: String {
        let sizes = AppLog.exportURLs.map { url -> String in
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            return "\(url.lastPathComponent): \(size)"
        }
        let attached = sizes.isEmpty ? "nema zapisa" : sizes.joined(separator: "\n")
        return "\n\n---\nAplikacija: \(appVersion)\niOS: \(UIDevice.current.systemVersion)\nLog:\n\(attached)"
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

// MARK: - Log by mail

#if DEBUG && !targetEnvironment(macCatalyst)
import MessageUI

/// A mail draft with the log files attached. Debug builds only, and not on
/// Catalyst, where MFMailComposeViewController does not exist.
struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    let attachments: [URL]

    /// False when the device has no mail account set up, in which case the
    /// composer would appear and send nothing.
    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator { dismiss() }
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)

        for url in attachments {
            guard let data = try? Data(contentsOf: url) else { continue }
            controller.addAttachmentData(data, mimeType: "text/plain", fileName: url.lastPathComponent)
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        /// Sent, saved or cancelled — the sheet closes either way, and a
        /// failure is the mail app's to report.
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            onFinish()
        }
    }
}
#endif

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

/// Locked to one host. The About page carries the site's own navigation and
/// links out to Facebook, Instagram and YouTube — following those inside the
/// app would make this a web browser, which is a different app to review and a
/// higher age rating. Anything off-host opens in Safari instead.
private struct WebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(isLoading: $isLoading, allowedHost: url.host) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let isLoading: Binding<Bool>
        private let allowedHost: String?

        init(isLoading: Binding<Bool>, allowedHost: String?) {
            self.isLoading = isLoading
            self.allowedHost = allowedHost
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let host = url.host ?? ""
            let isAllowed = allowedHost.map { host == $0 || host.hasSuffix(".\($0)") } ?? false

            if isAllowed {
                decisionHandler(.allow)
                return
            }

            // A tap on an outside link leaves the app rather than browsing inside it.
            if navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
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
