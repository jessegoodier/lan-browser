import SwiftUI
import UIKit

// Explicit wrapper name avoids the SDK’s same-named State macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct LocalNetworkCard: View {
    let turnOn: () -> Void
    let notNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Find devices on this network", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
            Text("Lists web apps such as Plex and Home Assistant, and shows which bookmarks are reachable. iOS will ask to allow Local Network access. Nothing is sent outside your network.")
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
                        Button("Open Settings") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                    }
                }
                ForEach(services) { service in
                    HStack(spacing: 12) {
                        Button { open(service) } label: {
                            HStack(spacing: 12) {
                                StatusDot(state: network.serviceStatus[service.id])
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(service.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
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
    }

    @ViewBuilder private var scanStatus: some View {
        if network.isSearching {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(services.isEmpty ? "Looking for web apps…" : "Scanning…").font(.subheadline).foregroundStyle(.secondary)
            }
        } else if let lastScan = network.lastScan {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scanned \(lastScan.formatted(.relative(presentation: .named))) · \(lastScan.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
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
        _diagnostics = StateObject(wrappedValue: ConnectionDiagnostics(url: url))
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
                            if step.kind == .permission && step.status == .failed {
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
