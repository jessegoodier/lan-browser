import SwiftUI

/// Safari-style tab overview: a grid of page thumbnails with close buttons.
struct TabSwitcher: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: BrowserSession
    @ObservedObject var devices: DeviceStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Two columns on iPhone, more on a wide iPad or Mac window.
    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(session.tabs) { tab in
                            TabCard(tab: tab, label: label(for: tab), selected: tab.id == session.selectedID) {
                                session.select(tab)
                                dismiss()
                            } close: {
                                withAnimation { session.close(tab) }
                            }
                            .id(tab.id)
                        }
                    }
                    .padding(16)
                }
                .onAppear { proxy.scrollTo(session.selectedID, anchor: .center) }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(session.tabs.count == 1 ? "1 Tab" : "\(session.tabs.count) Tabs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if BrowserLayout.usesTopBar(sizeClass) {
                    ToolbarItem(placement: .topBarLeading) { newTabButton }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                } else {
                    ToolbarItem(placement: .bottomBar) { newTabButton }
                    ToolbarItem(placement: .bottomBar) { Spacer() }
                    ToolbarItem(placement: .bottomBar) { Button("Done") { dismiss() }.bold() }
                }
            }
        }
    }

    private var newTabButton: some View {
        Button("New Tab", systemImage: "plus") {
            session.newTab()
            dismiss()
        }
    }

    private func label(for tab: BrowserTab) -> String {
        if tab.address.isEmpty { return "Start Page" }
        return URL(string: tab.address).flatMap { url in url.host.map { _ in devices.label(for: url) } } ?? tab.address
    }
}

private struct TabCard: View {
    @ObservedObject var tab: BrowserTab
    let label: String
    let selected: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(tab.title.isEmpty ? (tab.address.isEmpty ? "Start Page" : label) : tab.title)
                        .font(.caption.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                preview
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .clipped()
                Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button("Close Tab", systemImage: "xmark.circle.fill", action: close)
                .labelStyle(.iconOnly).font(.title3).foregroundStyle(.secondary)
                .padding(4)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var preview: some View {
        if let snapshot = tab.snapshot, !tab.showingStartPage {
            Image(uiImage: snapshot).resizable().scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            Image(systemName: tab.address.isEmpty ? "book" : "globe")
                .font(.largeTitle).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
        }
    }
}
