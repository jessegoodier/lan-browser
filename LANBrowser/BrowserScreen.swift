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
    case diagnostics(DiagnosticsTarget)

    var id: UUID {
        switch self {
        case .bookmark(let draft): return draft.id
        case .download(let export): return export.id
        case .diagnostics(let target): return target.id
        }
    }
}

struct BrowserScreen: View {
    @StateObject private var session = BrowserSession()
    @StateObject private var store = BookmarkStore()
    @StateObject private var devices: DeviceStore
    @StateObject private var network: LocalNetwork
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(OpenBookmarksIn.defaultsKey) private var openPreference = OpenBookmarksIn.newTab
    @ViewState private var renaming: DeviceRename?
    @ViewState private var addressInput = ""
    @ViewState private var sheet: BrowserSheet?
    @ViewState private var exportingDownload = false
    @ViewState private var editingAddress = false
    @ViewState private var showingInfo = false
    @ViewState private var bookmarkAfterInfo = false
    @ViewState private var showingSettings = false
    @ViewState private var showingTabs = false

    init() {
        let devices = DeviceStore()
        _devices = StateObject(wrappedValue: devices)
        _network = StateObject(wrappedValue: LocalNetwork(devices: devices))
    }

    private var tab: BrowserTab { session.selectedTab }

    var body: some View {
        // The browser controls live in the system bottom toolbar so that on the
        // foldable iPhone Duo the system can move them into the side strip, as Safari does.
        NavigationStack {
            ZStack {
                BrowserWebView(webView: tab.webView)
                    .id(tab.id)
                    .opacity(tab.showingStartPage ? 0 : 1)
                    .allowsHitTesting(!tab.showingStartPage && tab.pageError == nil)
                    .accessibilityHidden(tab.showingStartPage || tab.pageError != nil)
                if tab.showingStartPage {
                    bookmarksHome
                } else if let error = tab.pageError {
                    ContentUnavailableView {
                        Label("Page unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") { tab.retry() }.buttonStyle(.borderedProminent)
                        if let url = URL(string: tab.address), DiagnosticTarget(url: url) != nil {
                            Button("Diagnose") { sheet = .diagnostics(DiagnosticsTarget(url: url)) }
                        }
                        Button("Edit Address") { editingAddress = true }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
                }
            }
            .overlay(alignment: .top) { loadingIndicator }
            .overlay(alignment: .bottom) { downloadIndicator }
            .navigationTitle("LAN Browser")
            .toolbar(tab.showingStartPage ? .visible : .hidden, for: .navigationBar)
            .toolbar { browserToolbar }
        }
        .onChange(of: tab.address) { _, value in
            if !editingAddress { addressInput = value }
        }
        .onChange(of: editingAddress) { _, editing in
            if editing { addressInput = tab.address }
        }
        .onChange(of: session.export?.id) { _, _ in presentPendingDownload() }
        .onChange(of: tab.showingStartPage && scenePhase == .active, initial: true) { _, visible in
            network.setVisible(visible, bookmarks: store.bookmarks)
        }
        .onChange(of: scenePhase) { _, phase in
            network.setForeground(phase != .background)
            if phase == .background { session.saveTabs() }
        }
        .onChange(of: store.bookmarks) { _, bookmarks in network.bookmarksChanged(bookmarks) }
        .sheet(isPresented: $editingAddress) {
            AddressEntry(text: $addressInput) { open(addressInput) }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(session: session, network: network, devices: devices) {
                showingSettings = false
                tab.openBrowserCheck()
            }
        }
        .sheet(isPresented: $showingInfo, onDismiss: {
            if bookmarkAfterInfo {
                bookmarkAfterInfo = false
                newBookmark()
            }
        }) {
            PageInfoSheet(info: tab.pageInfo(), devices: devices, lookUp: network.isEnabled) {
                bookmarkAfterInfo = true
                showingInfo = false
            }
        }
        .fullScreenCover(isPresented: $showingTabs) {
            TabSwitcher(session: session, devices: devices)
        }
        .alert("Rename Device", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField(DeviceStore.defaultName(for: renaming?.host ?? ""), text: Binding(
                get: { renaming?.name ?? "" }, set: { renaming?.name = $0 }
            ))
            Button("Save") {
                if let renaming { devices.rename(renaming.host, to: renaming.name) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("Shown for every bookmark on \(renaming?.host ?? "this device"). Leave it empty to use the default name.")
        }
        .sheet(item: $sheet, onDismiss: {
            if exportingDownload {
                exportingDownload = false
                session.finishExport()
                session.presentNextExport()
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
            case .diagnostics(let target):
                DiagnosticsSheet(url: target.url)
            }
        }
        .alert("LAN Browser", isPresented: Binding(
            get: { sheet == nil && (session.message != nil || store.errorMessage != nil || devices.errorMessage != nil) },
            set: { if !$0 { clearMessages() } }
        )) {
            Button("OK", role: .cancel) { clearMessages() }
        } message: {
            Text(session.message ?? store.errorMessage ?? devices.errorMessage ?? "")
        }
    }

    /// Each bookmark’s host and port, also at the IP it was last seen at, so discovery can skip
    /// web servers already saved.
    private var bookmarkedEndpoints: Set<String> {
        Set(store.bookmarks.compactMap { BrowserAddress.parse($0.url) }.flatMap { url in
            ServiceCatalog.endpointKeys(for: url, address: url.host.flatMap(devices.address(for:)))
        })
    }

    /// The other way to open a row, offered in its long-press menu.
    private var alternateOpenTitle: String { openPreference == .newTab ? "Open in Current Tab" : "Open in New Tab" }

    private func openAlternate(_ input: String) {
        editingAddress = false
        session.open(input, newTab: openPreference != .newTab)
    }

    private var bookmarksHome: some View {
        List {
                if !network.isEnabled && !network.cardDismissed {
                    Section {
                        LocalNetworkCard(turnOn: { network.isEnabled = true }, notNow: { network.cardDismissed = true })
                    }
                }
                Section {
                    if store.bookmarks.isEmpty && network.isEnabled {
                        Text("No bookmarks yet. Tap + to save a web address, or add one from On This Network below.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.bookmarks) { bookmark in
                        Button {
                            openBookmark(bookmark.url)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "network")
                                    .font(.title3)
                                    .foregroundStyle(.tint)
                                    .frame(width: 30)
                                    .overlay(alignment: .bottomTrailing) {
                                        if network.isEnabled { StatusDot(state: network.status[bookmark.id]) }
                                    }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bookmark.title).font(.headline).foregroundStyle(.primary)
                                    Text(BrowserAddress.parse(bookmark.url).map { devices.label(for: $0) } ?? bookmark.url)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                            Button(alternateOpenTitle, systemImage: "plus.square.on.square") { openAlternate(bookmark.url) }
                            Button("Edit Bookmark", systemImage: "pencil") {
                                sheet = .bookmark(BookmarkDraft(bookmark: bookmark, isNew: false))
                            }
                            if let url = BrowserAddress.parse(bookmark.url) {
                                Button("Check Connection", systemImage: "stethoscope") {
                                    sheet = .diagnostics(DiagnosticsTarget(url: url))
                                }
                                if let host = url.host {
                                    Button("Rename Device…", systemImage: "character.cursor.ibeam") { rename(host) }
                                }
                            }
                        }
                    }
                    .onDelete(perform: store.delete)
                    .onMove(perform: store.move)
                } footer: {
                    Text("Home services and captive-portal login pages, one tap away. HTTP Forever is plain HTTP, so hotel and cafe Wi-Fi can show their sign-in screen. Swipe right on a bookmark to edit it, or touch and hold for more options.")
                }
                // Below the bookmarks, so arriving results never push saved rows out from under a tap.
                if network.isEnabled {
                    DiscoveredSection(
                        network: network,
                        bookmarked: bookmarkedEndpoints,
                        label: { devices.label(for: $0.url, address: $0.address) },
                        open: { openBookmark($0.url.absoluteString) },
                        alternateOpen: (alternateOpenTitle, { openAlternate($0.url.absoluteString) }),
                        save: { store.save(Bookmark(title: $0.name, url: $0.url.absoluteString)) },
                        rename: { if let host = $0.url.host { rename(host) } }
                    )
                }
            }
            .refreshable { await network.refresh() }
            .overlay {
                if store.bookmarks.isEmpty && !network.isEnabled {
                    ContentUnavailableView("No bookmarks yet", systemImage: "bookmark", description: Text("Tap + to save a web address."))
                }
            }
    }

    @ViewBuilder private var loadingIndicator: some View {
        if tab.isLoading && !tab.showingStartPage {
            ProgressView(value: tab.progress).tint(.blue)
                .accessibilityLabel("Page loading")
        }
    }

    @ViewBuilder private var downloadIndicator: some View {
        if session.activeDownloadCount > 0 {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Downloading \(session.activeDownloadCount == 1 ? "file" : "\(session.activeDownloadCount) files")…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 8)
        }
    }

    private var returnsToPage: Bool { tab.showingStartPage && !tab.address.isEmpty }

    @ToolbarContentBuilder private var browserToolbar: some ToolbarContent {
        if tab.showingStartPage {
            ToolbarItem(placement: .topBarLeading) { EditButton().disabled(store.bookmarks.isEmpty) }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { showingSettings = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Bookmark", systemImage: "plus") { newBookmark() }
            }
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button("Back", systemImage: "chevron.left") { tab.back() }
                .disabled(!tab.canGoBack || tab.showingStartPage)
            Button("Forward", systemImage: "chevron.right") { tab.forward() }
                .disabled(!tab.canGoForward || tab.showingStartPage)
            // A plain button (not an inline text field) so it still works when the
            // system moves the toolbar into the iPhone Duo's side strip.
            Button("Address", systemImage: tab.address.hasPrefix("https:") ? "lock" : "network") {
                editingAddress = true
            }
            Button(tab.isLoading ? "Stop Loading" : "Reload", systemImage: tab.isLoading ? "xmark" : "arrow.clockwise") {
                tab.reloadOrStop()
            }
            .disabled(tab.showingStartPage || tab.address.isEmpty)
            Button("Page Info", systemImage: "info.circle") { showingInfo = true }
                .disabled(tab.showingStartPage || tab.address.isEmpty)
            // Tap toggles bookmarks; touch and hold offers Add Bookmark, as in Safari.
            Menu {
                Button("Add Bookmark", systemImage: "bookmark") { newBookmark() }
                    .disabled(tab.address.isEmpty)
            } label: {
                Label(returnsToPage ? "Return to Page" : "Bookmarks", systemImage: returnsToPage ? "globe" : "book")
            } primaryAction: {
                editingAddress = false
                tab.showingStartPage = !returnsToPage
            }
            Menu {
                Button("New Tab", systemImage: "plus.square.on.square") { session.newTab() }
                Button("Close Tab", systemImage: "xmark", role: .destructive) { session.close(tab) }
            } label: {
                Label("Tabs", systemImage: "square.on.square")
                    .accessibilityValue("\(session.tabs.count) open")
            } primaryAction: {
                Task {
                    await tab.captureSnapshot()
                    showingTabs = true
                }
            }
        }
    }

    private func open(_ input: String) {
        if session.open(input, newTab: false) {
            addressInput = tab.address
            editingAddress = false
        }
    }

    private func openBookmark(_ input: String) {
        editingAddress = false
        session.openBookmark(input)
    }

    private func rename(_ host: String) {
        renaming = DeviceRename(host: host, name: devices.customName(for: host) ?? devices.name(for: host))
    }

    private func clearMessages() {
        session.message = nil
        store.errorMessage = nil
        devices.errorMessage = nil
    }

    private func presentPendingDownload() {
        guard sheet == nil, let export = session.export else { return }
        exportingDownload = true
        sheet = .download(export)
    }

    private func newBookmark() {
        editingAddress = false
        let onPage = !tab.showingStartPage
        sheet = .bookmark(BookmarkDraft(bookmark: Bookmark(title: onPage ? tab.title : "", url: onPage ? tab.address : ""), isNew: true))
    }
}

private struct DeviceRename {
    let host: String
    var name: String
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
    @ObservedObject var devices: DeviceStore
    /// Native lookups run only with Local Network Features on, so this sheet never triggers the prompt by itself.
    let lookUp: Bool
    let addBookmark: () -> Void
    @ViewState private var copied = false
    @ViewState private var deviceName = ""

    private var deviceDetail: String {
        let record = devices.records[DeviceStore.key(info.host)]
        let other = DeviceStore.isIPAddress(info.host) ? record?.hostname : record?.address
        return [info.host, other].compactMap { $0 }.joined(separator: " · ")
    }

    private var connection: (text: String, symbol: String, color: Color) {
        if info.isFullySecure { return ("Encrypted (HTTPS)", "lock.fill", .green) }
        if info.isEncrypted { return ("HTTPS with insecure content on the page", "lock.trianglebadge.exclamationmark", .orange) }
        return ("Not encrypted (HTTP). Traffic on your network can be read.", "lock.open.fill", .orange)
    }

    var body: some View {
        NavigationStack {
            List {
                if !info.host.isEmpty {
                    Section {
                        TextField(devices.name(for: info.host), text: $deviceName)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { devices.rename(info.host, to: deviceName) }
                            .accessibilityLabel("Device name")
                        Text(deviceDetail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    } header: { Text("Device") } footer: {
                        Text("Shown for every bookmark on this device. Leave it empty to use the default name.")
                    }
                }
                Section("Address") {
                    Text(info.url).font(.callout.monospaced()).textSelection(.enabled)
                    Button(copied ? "Copied" : "Copy Address", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = info.url
                        copied = true
                    }
                    Button("Add Bookmark", systemImage: "bookmark", action: addBookmark)
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
                if let url = URL(string: info.url), DiagnosticTarget(url: url) != nil {
                    Section {
                        NavigationLink {
                            DiagnosticsView(url: url)
                        } label: {
                            Label("Why Can’t I Connect?", systemImage: "stethoscope")
                        }
                    } footer: {
                        Text("Checks Wi-Fi, Local Network access, name lookup, the port, and whether the server answers.")
                    }
                }
            }
            .navigationTitle("Page Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            guard !info.host.isEmpty else { return }
            deviceName = devices.customName(for: info.host) ?? ""
            guard lookUp else { return }
            let sighting = await NetworkProbe.sighting(of: info.host, reverseLookup: true)
            devices.record(address: sighting.address, hostname: sighting.hostname, for: info.host)
        }
        .onDisappear {
            if !info.host.isEmpty, deviceName != (devices.customName(for: info.host) ?? "") {
                devices.rename(info.host, to: deviceName)
            }
        }
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
