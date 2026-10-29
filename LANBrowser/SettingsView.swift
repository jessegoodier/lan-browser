import SwiftUI

// Explicit wrapper name avoids the SDK’s same-named State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

/// Preferences, local-network controls, privacy actions and help, in one sheet.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: BrowserSession
    @ObservedObject var network: LocalNetwork
    @ObservedObject var devices: DeviceStore
    let openCheck: () -> Void
    @AppStorage(OpenBookmarksIn.defaultsKey) private var openPreference = OpenBookmarksIn.newTab
    @AppStorage(TabPolicy.restoreKey) private var restoreTabs = true
    @ViewState private var confirmingClear = false
    @ViewState private var confirmingReset = false
    @ViewState private var clearing = false
    @ViewState private var cleared = false
    @ViewState private var reviewingPreset: PortScanPreset?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Open Bookmarks In", selection: $openPreference) {
                        ForEach(OpenBookmarksIn.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Restore Tabs on Launch", isOn: $restoreTabs)
                } header: { Text("Browsing") } footer: {
                    Text("A bookmark always fills a blank tab. When tabs are restored, their addresses and Back history are saved on this device.")
                }
                .onChange(of: restoreTabs) { _, _ in session.saveTabs() }

                Section {
                    Toggle("Local Network Features", isOn: $network.isEnabled)
                    if network.isEnabled {
                        Button(network.isSearching ? "Scanning…" : "Scan Again", systemImage: "arrow.clockwise") { network.scan() }
                            .disabled(network.isSearching)
                        if let lastScan = network.lastScan {
                            LabeledContent("Last Scan", value: lastScan.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    if network.isEnabled {
                        Picker("Port Scan", selection: Binding(
                            get: { network.portScanPreset },
                            set: { preset in
                                // Nothing changes until the user has seen the ports and range and confirmed.
                                if preset == .off { network.turnOffPortScan() } else { reviewingPreset = preset }
                            }
                        )) {
                            ForEach(PortScanPreset.allCases) { Text("\($0.title) (\($0.summary))").tag($0) }
                        }
                        if network.portScanPreset != .off {
                            Text("Scans ports \(network.portScanPreset.ports.map(String.init).joined(separator: ", ")) when you tap Scan Again.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("Clear Discovered Services", role: .destructive) { network.clearResults() }
                        .disabled(network.lastScan == nil && network.services.isEmpty)
                    Button("Reset Device Names", role: .destructive) { confirmingReset = true }
                        .disabled(devices.records.isEmpty)
                } header: { Text("Local Network") } footer: {
                    Text("Off by default. When on, LAN Browser scans once for web apps advertised with Bonjour, then only when you ask, and checks whether your bookmarks are reachable while the bookmark list is open. A port scan also finds web apps that don’t advertise themselves; it is off until you review and confirm the ports and addresses, and runs only when you scan. iOS asks for Local Network access. Nothing is sent to the developer or anyone else.")
                }

                Section {
                    Button(clearing ? "Clearing Website Data…" : "Clear Cookies & Website Data", role: .destructive) {
                        confirmingClear = true
                    }.disabled(clearing)
                    if cleared { Text("Website data cleared.").foregroundStyle(.secondary) }
                    NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                } header: { Text("Privacy") } footer: {
                    Text("Bookmarks stay on this device. Websites can receive your requests and form entries and store cookies and website data. LAN Browser has no analytics, ads, or developer-operated backend. Clearing website data signs you out of websites and closes all tabs; bookmarks and files saved to Files remain.")
                }

                Section {
                    NavigationLink("Using LAN Browser") { HelpView() }
                    Button("Run Browser Check", systemImage: "checkmark.circle", action: openCheck)
                    Link("Ask for Help or Report a Problem", destination: URL(string: "https://github.com/jessegoodier/lan-browser/issues")!)
                    LabeledContent("Version", value: version)
                } header: { Text("Help & Support") } footer: {
                    Text("Browser Check tests page rendering and Save to Files without a home server or an internet connection. Support uses public GitHub Issues and requires a GitHub account to post. Do not include passwords, private server addresses, or other sensitive information.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Clear all cookies and website data?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear Website Data", role: .destructive) {
                    clearing = true
                    cleared = false
                    Task { @MainActor in
                        await session.clearWebsiteData()
                        clearing = false
                        cleared = true
                    }
                }
            } message: { Text("You’ll be signed out of websites, and all tabs will close. Bookmarks and exported downloads are kept.") }
            .sheet(item: $reviewingPreset) { preset in
                PortScanConfirmationSheet(preset: preset, plan: network.plan(for: preset)) { network.confirm($0) }
            }
            .confirmationDialog("Reset all device names?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset Device Names", role: .destructive) { devices.resetAll() }
            } message: { Text("Custom names, remembered IP addresses and looked-up host names are forgotten. Bookmarks are kept.") }
        }
    }
}

/// Shown once, before first use, and repeated at the top of the help page.
struct TrustedNetworkNotice: View {
    static let acceptedKey = "trustedNetworkNoticeAccepted"
    static let summary = "LAN Browser is intended exclusively for use on trusted home networks. It isn’t meant for browsing websites that are expected to be secure, such as banking, email or shopping."
    static let details = "To reach home devices it loads plain HTTP pages, and it opens devices on your network even when their certificates aren’t trusted. When you’re on a network you don’t trust, use Safari."

    let accept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "house.fill").font(.system(size: 44)).foregroundStyle(.tint)
            Text("For Trusted Home Networks").font(.title.bold())
            Text(Self.summary).font(.body)
            Text(Self.details).font(.body).foregroundStyle(.secondary)
            Spacer()
            Button(action: accept) {
                Text("I Understand").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .interactiveDismissDisabled()
    }
}

private struct HelpView: View {
    var body: some View {
        List {
            Section {
                Text(TrustedNetworkNotice.summary).bold()
                Text(TrustedNetworkNotice.details)
            }
            Text("Save home-server addresses and open Wi-Fi sign-in pages. Addresses without a scheme use HTTP. HTTP traffic is not encrypted; use HTTPS when your service supports it.")
            Text("On public Wi-Fi, open the HTTP Forever bookmark to request the network’s sign-in page. A portal appears only when that network requires sign-in.")
            Text("For home services, use the same Wi-Fi network as your server and enter its hostname or IP address and port. Devices on your network with self-signed or otherwise untrusted certificates open anyway, marked with a red “!” you can tap to see the certificate; internet sites with invalid certificates are still blocked.")
            Text("Bookmarks open in a new tab unless the current tab is blank; change this in Settings. Touch and hold a bookmark to open it the other way. Tap the tabs button to switch tabs, or touch and hold it for New Tab and Close Tab. Touch and hold the bookmarks button to bookmark the current page.")
            Text("If a page won’t load, use Diagnose on the error screen, Why Can’t I Connect? in Page Info, or touch and hold a bookmark and choose Check Connection. Choose Rename Device… there, or use the Device section in Page Info, to give a device a friendly name.")
        }
        .navigationTitle("Using LAN Browser")
        .navigationBarTitleDisplayMode(.inline)
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
