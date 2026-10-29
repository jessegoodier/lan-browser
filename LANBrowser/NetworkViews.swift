import SwiftUI
import UIKit

// Explicit wrapper name avoids the SDK’s same-named State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

extension HostDevice {
    /// The Mac reports the iPad idiom when it runs the iPad app, so check for it first.
    @MainActor static var current: HostDevice {
        if ProcessInfo.processInfo.isiOSAppOnMac { return .mac }
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
    }
}

struct LocalNetworkCard: View {
    let turnOn: () -> Void
    let notNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Find devices on this network", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
            Text("Lists web apps such as Plex and Home Assistant, and shows which bookmarks are reachable. You’ll be asked to allow Local Network access. Nothing is sent outside your network.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Not Now", action: notNow)
                Button("Turn On", action: turnOn).buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
    }
}

struct DiscoveredSection: View {
    @ObservedObject var network: LocalNetwork
    /// Web servers already bookmarked are left out, matched by host name or IP plus port.
    let bookmarked: Set<String>
    let label: (DiscoveredService) -> String
    let open: (DiscoveredService) -> Void
    /// The open action that isn’t the default, e.g. “Open in Current Tab”.
    let alternateOpen: (title: String, action: (DiscoveredService) -> Void)
    let save: (DiscoveredService) -> Void
    let rename: (DiscoveredService) -> Void
    @ViewState private var expanded = true
    @ViewState private var reviewing: PortScanPlan?
    @Environment(\.openURL) private var openURL

    private var services: [DiscoveredService] {
        network.services.filter { !ServiceCatalog.isBookmarked($0, bookmarked: bookmarked) }
    }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                scanStatus
                if network.accessDenied {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Local Network access is off for LAN Browser.").font(.subheadline)
                        if HostDevice.current == .mac {
                            Text("Turn it on in System Settings › Privacy & Security › Local Network.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                        }
                    }
                }
                ForEach(services) { service in
                    HStack(spacing: 12) {
                        Button { open(service) } label: {
                            HStack(spacing: 12) {
                                StatusDot(state: network.serviceStatus[service.id])
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(service.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                        if service.foundBy == .portScan {
                                            Text("port scan").font(.caption2).foregroundStyle(.secondary)
                                                .padding(.horizontal, 6).padding(.vertical, 1)
                                                .background(.quaternary, in: Capsule())
                                        }
                                    }
                                    Text(label(service)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button("Add to Bookmarks", systemImage: "plus.circle") { save(service) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).font(.title3)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Remove", systemImage: "minus.circle", role: .destructive) { network.remove(service) }
                    }
                    .contextMenu {
                        Button(alternateOpen.title, systemImage: "plus.square.on.square") { alternateOpen.action(service) }
                        Button("Rename Device…", systemImage: "character.cursor.ibeam") { rename(service) }
                        Button("Remove from List", systemImage: "minus.circle", role: .destructive) { network.remove(service) }
                    }
                }
            } label: {
                HStack {
                    Label("On This Network", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    if network.isSearching && !services.isEmpty { ProgressView().controlSize(.small) }
                    if !services.isEmpty { Text("\(services.count)").foregroundStyle(.secondary) }
                    Menu {
                        Button("Scan Again", systemImage: "arrow.clockwise") { network.scan() }
                            .disabled(network.isSearching)
                        Button("Clear Results", systemImage: "trash", role: .destructive) { network.clearResults() }
                            .disabled(network.services.isEmpty && network.lastScan == nil)
                    } label: {
                        Image(systemName: "ellipsis.circle").accessibilityLabel("Discovery options")
                    }
                    .buttonStyle(.borderless)
                }
            }
        } footer: {
            Text("Web apps found by the last scan, except ones already in your bookmarks. Scan again from the ••• menu or pull down. Tap + to save one as a bookmark; swipe left to remove it from this list.")
        }
        .animation(.default, value: services.map(\.id))
        .sheet(item: $reviewing) { plan in
            PortScanConfirmationSheet(preset: plan.preset, plan: plan) { confirmed in
                network.confirm(confirmed)
                network.scan()
            }
        }
    }

    @ViewBuilder private var scanStatus: some View {
        if network.isSearching {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    if let progress = network.portScanProgress {
                        Text("\(progress.phase) · \(progress.done.formatted()) of \(progress.total.formatted())")
                            .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    } else {
                        Text(services.isEmpty ? "Looking for web apps…" : "Scanning…").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cancel") { network.stopScanning() }.buttonStyle(.borderless)
                }
                if let progress = network.portScanProgress, progress.total > 0 {
                    ProgressView(value: Double(progress.done), total: Double(progress.total))
                }
            }
        } else if let lastScan = network.lastScan {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scanned \(lastScan.formatted(.relative(presentation: .named))) · \(lastScan.formatted(date: .omitted, time: .shortened)) · \(network.lastScanPorts.map { "Bonjour + \($0.summary.lowercased())" } ?? "Bonjour")")
                    .font(.caption).foregroundStyle(.secondary)
                if let plan = network.pendingConfirmation {
                    HStack {
                        Label("The port scan needs confirming for this network.", systemImage: "questionmark.circle")
                            .font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button("Review") { reviewing = plan }.buttonStyle(.borderless).font(.caption)
                    }
                }
                if network.networkChanged {
                    Label("You’ve changed networks since this scan. Scan again to update.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if network.services.isEmpty {
                    Text("No web apps were found.").font(.subheadline).foregroundStyle(.secondary)
                } else if services.isEmpty {
                    Text("Everything found is already in your bookmarks.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        } else {
            HStack {
                Text("Not scanned yet.").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button("Scan") { network.scan() }.buttonStyle(.borderless)
            }
        }
    }
}

/// Shows exactly what a port scan would do before the user allows it.
struct PortScanConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preset: PortScanPreset
    /// Nil when this device isn’t on Wi-Fi or Ethernet, so there is no network to describe.
    let plan: PortScanPlan?
    let confirm: (PortScanPlan) -> Void

    var body: some View {
        NavigationStack {
            List {
                if let plan {
                    Section {
                        LabeledContent("Range", value: plan.range.description)
                        LabeledContent("Addresses", value: plan.addressCount.formatted())
                    } header: { Text("Addresses") } footer: {
                        Text("Your network, \(plan.range.cidr). This \(HostDevice.current.rawValue) (\(plan.deviceIP)) is skipped.")
                    }
                    Section("Ports · \(preset.title)") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(preset.ports, id: \.self) { port in
                                Text(String(port)).font(.callout.monospacedDigit())
                                    .frame(maxWidth: .infinity).padding(.vertical, 4)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Section {
                        Text("First, ports 80 and 443 are tried on each address to find devices that are on (about \(plan.discoveryConnections.formatted()) connections). Then the ports above are tried on those devices, and any that answer as a web page are listed. A scan usually takes 10–30 seconds.")
                        Text("Runs only when you tap Scan Again or pull down on the bookmark list. Nothing is sent outside your network.")
                    }
                } else {
                    Text("Join a Wi-Fi network to see which addresses would be scanned.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Scan Ports on This Network?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        if let plan { confirm(plan) }
                        dismiss()
                    }
                    .disabled(plan == nil)
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Marks a local page opened despite an untrusted certificate; tapping shows the certificate.
struct CertificateStrip: View {
    let issue: CertificateIssue
    let show: () -> Void

    var body: some View {
        Button(action: show) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Certificate not trusted").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(issue.host).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityLabel("Certificate not trusted for \(issue.host). Show certificate.")
    }
}

/// The untrusted certificate in full, so it can be checked against the device.
struct CertificateDetailsView: View {
    let issue: CertificateIssue
    @ViewState private var copied = false

    var body: some View {
        List {
            Section {
                Label(issue.error, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red).textSelection(.enabled)
                if let code = issue.errorCode { LabeledContent("Error code", value: String(code)) }
            } header: { Text("Problem") } footer: {
                Text("LAN Browser opened \(issue.host) anyway because it’s an address on your local network. Another device on your network could pretend to be it, so if it matters, compare the SHA-256 fingerprint below with the one the device shows in its own settings.")
            }
            ForEach(Array(issue.chain.enumerated()), id: \.offset) { index, certificate in
                Section(index == 0 ? "Server Certificate" : "Issuer \(index)") {
                    LabeledContent("Subject", value: certificate.subject)
                    if let commonName = certificate.commonName, commonName != certificate.subject {
                        LabeledContent("Common Name", value: commonName)
                    }
                    if let notBefore = certificate.notBefore {
                        LabeledContent("Valid From", value: notBefore.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let notAfter = certificate.notAfter {
                        LabeledContent("Valid Until", value: notAfter.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(notAfter < Date() ? .red : .primary)
                    }
                    if let key = certificate.key { LabeledContent("Key", value: key) }
                    if let serial = certificate.serialNumber {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Serial Number").font(.caption.weight(.semibold))
                            Text(serial).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SHA-256 Fingerprint").font(.caption.weight(.semibold))
                        Text(certificate.sha256).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            Section {
                Button(copied ? "Copied" : "Copy Certificate Details", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = issue.report
                    copied = true
                }
            }
        }
        .navigationTitle("Certificate")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A non-200 page’s first line: status, exact request, and quick ways to see more.
struct ResponseBanner: View {
    let response: PageResponse
    let details: () -> Void
    let diagnose: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: response.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(response.statusCode >= 500 ? .red : response.isError ? .orange : .blue)
            VStack(alignment: .leading, spacing: 6) {
                Text("HTTP \(response.statusLine)").font(.subheadline.weight(.semibold).monospaced())
                Text("\(response.method) \(response.url)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                HStack(spacing: 8) {
                    Button("Details", action: details)
                    if response.isError { Button("Diagnose", action: diagnose) }
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            Spacer(minLength: 0)
            Button("Hide", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }
}

/// Every detail WebKit reports about the page’s response, verbatim.
struct ResponseDetailsView: View {
    let response: PageResponse
    @ViewState private var copied = false

    var body: some View {
        List {
            Section("Request") {
                LabeledContent("Method", value: response.method)
                Text(response.url).font(.callout.monospaced()).textSelection(.enabled)
            }
            Section {
                Text(response.statusLine).font(.body.monospaced()).textSelection(.enabled)
            } header: { Text("Status") } footer: {
                Text("The status code is exactly what the server sent. WebKit doesn’t pass on the server’s own reason phrase, and HTTP/2 doesn’t send one, so the phrase shown is the standard one for this code.")
            }
            Section {
                ForEach(Array(response.headers.enumerated()), id: \.offset) { _, header in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(header.name).font(.caption.weight(.semibold).monospaced())
                        Text(header.value).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            } header: { Text("Response Headers (\(response.headers.count))") } footer: {
                Text("Values are as received. iOS may normalize header names and doesn’t keep their original order, so they are sorted by name.")
            }
            Section {
                Button(copied ? "Copied" : "Copy Response Details", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = response.report
                    copied = true
                }
            }
        }
        .navigationTitle("HTTP \(response.statusCode)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StatusDot: View {
    let state: Reachability?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
            .accessibilityLabel(label)
    }

    private var color: Color {
        switch state {
        case .reachable: return .green
        case .unreachable: return .red
        case .checking, nil: return .gray
        }
    }

    private var label: String {
        switch state {
        case .reachable: return "Reachable"
        case .unreachable: return "Not reachable"
        case .checking, nil: return "Checking"
        }
    }
}

struct DiagnosticsTarget: Identifiable {
    let id = UUID()
    let url: URL
}

/// Presented on its own (error screen, bookmark menu) with a Done button.
struct DiagnosticsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        NavigationStack {
            DiagnosticsView(url: url)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct DiagnosticsView: View {
    @StateObject private var diagnostics: ConnectionDiagnostics
    @ViewState private var copied = false
    @Environment(\.openURL) private var openURL

    init(url: URL) {
        _diagnostics = StateObject(wrappedValue: ConnectionDiagnostics(url: url, device: .current))
    }

    var body: some View {
        List {
            Section {
                Text(diagnostics.url.absoluteString).font(.callout.monospaced()).textSelection(.enabled)
            }
            Section("Checks") {
                ForEach(diagnostics.steps) { step in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            icon(for: step.status).frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.kind.title).font(.subheadline.weight(.semibold))
                                if !step.detail.isEmpty {
                                    Text(step.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                        }
                        if let advice = step.advice {
                            Text(advice).font(.callout).padding(.leading, 30)
                            // The advice names the System Settings path on a Mac, where this URL doesn’t reach it.
                            if step.kind == .permission && step.status == .failed && diagnostics.device != .mac {
                                Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                                    .padding(.leading, 30)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            }
            Section {
                Button(diagnostics.isRunning ? "Checking…" : "Retry Checks", systemImage: "arrow.clockwise") {
                    copied = false
                    Task { await diagnostics.run() }
                }
                .disabled(diagnostics.isRunning)
                Button(copied ? "Copied" : "Copy Report", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = diagnostics.report
                    copied = true
                }
                .disabled(diagnostics.isRunning)
            } footer: {
                Text("The report includes addresses on your network. Review it before posting it publicly.")
            }
        }
        .navigationTitle("Why Can’t I Connect?")
        .navigationBarTitleDisplayMode(.inline)
        .task { await diagnostics.run() }
    }

    @ViewBuilder private func icon(for status: DiagnosticStatus) -> some View {
        switch status {
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary).accessibilityLabel("Waiting")
        case .running: ProgressView().controlSize(.small)
        case .passed: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Passed")
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityLabel("Warning")
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red).accessibilityLabel("Failed")
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.tertiary).accessibilityLabel("Skipped")
        }
    }
}
