import SwiftUI
import UIKit
import WebKit

// Explicit wrapper name avoids the SDK’s same-named State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

private struct BookmarkDraft: Identifiable {
    let id = UUID()
    var bookmark: Bookmark
    var isNew: Bool
}

private enum BrowserSheet: Identifiable {
    case bookmark(BookmarkDraft)
    case download(DownloadExport)

    var id: UUID {
        switch self {
        case .bookmark(let draft): return draft.id
        case .download(let export): return export.id
        }
    }
}

struct BrowserScreen: View {
    @StateObject private var browser = BrowserModel()
    @StateObject private var store = BookmarkStore()
    @ViewState private var addressInput = ""
    @ViewState private var sheet: BrowserSheet?
    @ViewState private var exportingDownload = false
    @ViewState private var editingAddress = false
    @ViewState private var showingInfo = false
    @ViewState private var showingHelp = false

    var body: some View {
        // The browser controls live in the system bottom toolbar so that on the
        // foldable iPhone Duo the system can move them into the side strip, as Safari does.
        NavigationStack {
            ZStack {
                BrowserWebView(webView: browser.webView)
                    .opacity(browser.showingBookmarks ? 0 : 1)
                    .allowsHitTesting(!browser.showingBookmarks && browser.pageError == nil)
                    .accessibilityHidden(browser.showingBookmarks || browser.pageError != nil)
                if browser.showingBookmarks {
                    bookmarksHome
                } else if let error = browser.pageError {
                    ContentUnavailableView {
                        Label("Page unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { browser.retry() }.buttonStyle(.borderedProminent)
                        Button("Edit Address") { editingAddress = true }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
                }
            }
            .overlay(alignment: .top) { loadingIndicator }
            .overlay(alignment: .bottom) { downloadIndicator }
            .navigationTitle("LAN Browser")
            .toolbar(browser.showingBookmarks ? .visible : .hidden, for: .navigationBar)
            .toolbar { browserToolbar }
        }
        .onChange(of: browser.address) { _, value in
            if !editingAddress { addressInput = value }
        }
        .onChange(of: editingAddress) { _, editing in
            if editing { addressInput = browser.address }
        }
        .onChange(of: browser.export?.id) { _, _ in presentPendingDownload() }
        .sheet(isPresented: $editingAddress) {
            AddressEntry(text: $addressInput) { open(addressInput) }
        }
        .sheet(isPresented: $showingHelp) {
            BrowserHelpSheet(browser: browser) {
                showingHelp = false
                browser.openBrowserCheck()
            }
        }
        .sheet(isPresented: $showingInfo) {
            PageInfoSheet(info: browser.pageInfo())
        }
        .sheet(item: $sheet, onDismiss: {
            if exportingDownload {
                exportingDownload = false
                browser.finishExport()
                browser.presentNextExport()
            }
            presentPendingDownload()
        }) { presented in
            switch presented {
            case .bookmark(let draft):
                BookmarkEditor(bookmark: draft.bookmark, isNew: draft.isNew) { bookmark in
                    if store.save(bookmark) { return nil }
                    let error = store.errorMessage ?? "Please try again."
                    store.errorMessage = nil
                    return error
                }
            case .download(let export):
                DownloadSavePicker(url: export.url) { sheet = nil }
                    .ignoresSafeArea()
                    .interactiveDismissDisabled()
            }
        }
        .alert("LAN Browser", isPresented: Binding(
            get: { sheet == nil && (browser.message != nil || store.errorMessage != nil) },
            set: { if !$0 { browser.message = nil; store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { browser.message = nil; store.errorMessage = nil }
        } message: {
            Text(browser.message ?? store.errorMessage ?? "")
        }
    }

    private var bookmarksHome: some View {
        List {
                Section {
                    ForEach(store.bookmarks) { bookmark in
                        Button {
                            open(bookmark.url)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "network")
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bookmark.title).font(.headline).foregroundStyle(.primary)
                                    Text(bookmark.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button("Edit", systemImage: "pencil") {
                                sheet = .bookmark(BookmarkDraft(bookmark: bookmark, isNew: false))
                            }.tint(.blue)
                        }
                        .contextMenu {
                            Button("Edit Bookmark", systemImage: "pencil") {
                                sheet = .bookmark(BookmarkDraft(bookmark: bookmark, isNew: false))
                            }
                        }
                    }
                    .onDelete(perform: store.delete)
                    .onMove(perform: store.move)
                } footer: {
                    Text("Home services and captive-portal login pages, one tap away. HTTP Forever is plain HTTP, so hotel and cafe Wi-Fi can show their sign-in screen. Swipe right on a bookmark to edit it.")
                }
            }
            .overlay {
                if store.bookmarks.isEmpty {
                    ContentUnavailableView("No bookmarks yet", systemImage: "bookmark", description: Text("Tap + to save a web address."))
                }
            }
    }

    @ViewBuilder private var loadingIndicator: some View {
        if browser.isLoading && !browser.showingBookmarks {
            ProgressView(value: browser.progress).tint(.blue)
                .accessibilityLabel("Page loading")
        }
    }

    @ViewBuilder private var downloadIndicator: some View {
        if browser.activeDownloadCount > 0 {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Downloading \(browser.activeDownloadCount == 1 ? "file" : "\(browser.activeDownloadCount) files")…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 8)
        }
    }

    private var returnsToPage: Bool { browser.showingBookmarks && !browser.address.isEmpty }

    @ToolbarContentBuilder private var browserToolbar: some ToolbarContent {
        if browser.showingBookmarks {
            ToolbarItem(placement: .topBarLeading) { EditButton().disabled(store.bookmarks.isEmpty) }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Help & Privacy", systemImage: "questionmark.circle") { showingHelp = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Bookmark", systemImage: "plus") { newBookmark() }
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Back", systemImage: "chevron.left") { browser.back() }
                .disabled(!browser.canGoBack || browser.showingBookmarks)
            Button("Forward", systemImage: "chevron.right") { browser.forward() }
                .disabled(!browser.canGoForward || browser.showingBookmarks)
            // A plain button (not an inline text field) so it still works when the
            // system moves the toolbar into the iPhone Duo's side strip.
            Button("Address", systemImage: browser.address.hasPrefix("https:") ? "lock" : "network") {
                editingAddress = true
            }
            Button(browser.isLoading ? "Stop Loading" : "Reload", systemImage: browser.isLoading ? "xmark" : "arrow.clockwise") {
                browser.reloadOrStop()
            }
            .disabled(browser.showingBookmarks || browser.address.isEmpty)
            Button("Page Info", systemImage: "info.circle") { showingInfo = true }
                .disabled(browser.showingBookmarks || browser.address.isEmpty)
            Button(returnsToPage ? "Return to Page" : "Bookmarks", systemImage: returnsToPage ? "globe" : "book") {
                editingAddress = false
                browser.showingBookmarks = !returnsToPage
            }
            Button("Add Bookmark", systemImage: "bookmark") { newBookmark() }
        }
    }



    private func open(_ input: String) {
        if browser.navigate(input) {
            addressInput = browser.address
            editingAddress = false
        }
    }

    private func presentPendingDownload() {
        guard sheet == nil, let export = browser.export else { return }
        exportingDownload = true
        sheet = .download(export)
    }

    private func newBookmark() {
        editingAddress = false
        let url = browser.showingBookmarks ? "" : browser.address
        let title = browser.showingBookmarks ? "" : browser.title
        sheet = .bookmark(BookmarkDraft(bookmark: Bookmark(title: title, url: url), isNew: true))
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: 44, minHeight: 44)
            .opacity(configuration.isPressed ? 0.45 : 1)
    }
}

private struct AddressEntry: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var text: String
    let go: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Address · httpforever.com", text: $text)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit(go)
                    .accessibilityLabel("Web address")
            }
            .navigationTitle("Web Address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Go", action: go) }
            }
        }
        .presentationDetents([.medium])
        .onAppear { focused = true }
    }
}

private struct PageInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let info: PageInfo
    @ViewState private var copied = false

    private var connection: (text: String, symbol: String, color: Color) {
        if info.isFullySecure { return ("Encrypted (HTTPS)", "lock.fill", .green) }
        if info.isEncrypted { return ("HTTPS with insecure content on the page", "lock.trianglebadge.exclamationmark", .orange) }
        return ("Not encrypted (HTTP). Traffic on your network can be read.", "lock.open.fill", .orange)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Address") {
                    Text(info.url).font(.callout.monospaced()).textSelection(.enabled)
                    Button(copied ? "Copied" : "Copy Address", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = info.url
                        copied = true
                    }
                }
                Section("Connection") {
                    Label(connection.text, systemImage: connection.symbol).foregroundStyle(connection.color)
                    if let trusted = info.certificateTrusted {
                        LabeledContent("Certificate", value: trusted ? "Trusted" : "Not trusted")
                    }
                    if let subject = info.certificateSubject { LabeledContent("Issued to", value: subject) }
                    if let issuer = info.certificateIssuer { LabeledContent("Issued by", value: issuer) }
                }
                Section("Page") {
                    if !info.title.isEmpty { LabeledContent("Title", value: info.title) }
                    LabeledContent("Host", value: info.host)
                    LabeledContent("Port", value: info.port.map(String.init) ?? "Default (\(info.isEncrypted ? 443 : 80))")
                    LabeledContent("Protocol", value: info.scheme)
                }
            }
            .navigationTitle("Page Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private struct BookmarkEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState var bookmark: Bookmark
    let isNew: Bool
    let save: (Bookmark) -> String?
    @ViewState private var saveError: String?

    private var parsedURL: URL? { BrowserAddress.parse(bookmark.url) }
    private var valid: Bool { parsedURL != nil && !bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") { TextField("e.g. Home Server", text: $bookmark.title) }
                Section {
                    TextField("e.g. 192.168.1.20:8080", text: $bookmark.url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Bookmark address")
                } header: { Text("Address") } footer: {
                    Text("Addresses without http:// or https:// use HTTP.")
                }
            }
            .navigationTitle(isNew ? "Add Bookmark" : "Edit Bookmark")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn’t Save Bookmark", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "Please try again.") }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let parsedURL else { return }
                        bookmark.url = parsedURL.absoluteString
                        bookmark.title = bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let error = save(bookmark) { saveError = error }
                        else { dismiss() }
                    }.disabled(!valid)
                }
            }
        }
    }
}

private struct DownloadSavePicker: UIViewControllerRepresentable {
    let url: URL
    let completion: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: () -> Void
        init(completion: @escaping () -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion() }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion() }
    }
}


private struct BrowserHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var browser: BrowserModel
    let openCheck: () -> Void
    @ViewState private var confirmingClear = false
    @ViewState private var clearing = false
    @ViewState private var cleared = false

    var body: some View {
        NavigationStack {
            List {
                Section("Using LAN Browser") {
                    Text("Save home-server addresses and open Wi-Fi sign-in pages. Addresses without a scheme use HTTP. HTTP traffic is not encrypted; use HTTPS when your service supports it.")
                    Text("On public Wi-Fi, open the HTTP Forever bookmark to request the network’s sign-in page. A portal appears only when that network requires sign-in.")
                    Text("For home services, use the same Wi-Fi network as your server and enter its hostname or IP address and port. LAN Browser does not scan for devices or bypass certificate errors.")
                    Button("Run Browser Check", systemImage: "checkmark.circle", action: openCheck)
                    Text("Check page rendering and Save to Files without a home server or an internet connection.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                    Text("Bookmarks stay on this device. Websites can receive your requests and form entries and store cookies and website data. LAN Browser has no analytics, ads, or developer-operated backend.")
                    Button(clearing ? "Clearing Website Data…" : "Clear Cookies & Website Data", role: .destructive) {
                        confirmingClear = true
                    }.disabled(clearing)
                    Text("Signs you out of websites and removes their cookies, caches, and local storage. Your bookmarks and files saved to Files remain.").font(.caption).foregroundStyle(.secondary)
                    if cleared { Text("Website data cleared.").foregroundStyle(.secondary) }
                }
                Section("Support") {
                    Link("Ask for Help or Report a Problem", destination: URL(string: "https://github.com/jessegoodier/lan-browser/issues")!)
                    Text("Support uses public GitHub Issues and requires a GitHub account to post. Do not include passwords, private server addresses, or other sensitive information.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Help & Privacy")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Clear all cookies and website data?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear Website Data", role: .destructive) {
                    clearing = true
                    cleared = false
                    Task { @MainActor in
                        await browser.clearWebsiteData()
                        clearing = false
                        cleared = true
                    }
                }
            } message: { Text("You will be signed out of websites. Bookmarks and exported downloads are kept.") }
        }
    }
}

private struct PrivacyPolicyView: View {
    private var policy: String {
        guard let url = Bundle.main.url(forResource: "privacy_policy", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "The privacy policy could not be loaded. Please use the online policy link below."
        }
        return text
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(policy).textSelection(.enabled)
                Link("View Online Privacy Policy", destination: URL(string: "https://github.com/jessegoodier/lan-browser/blob/main/LANBrowser/privacy_policy.md")!)
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
