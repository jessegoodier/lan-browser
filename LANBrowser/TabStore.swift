import Foundation

enum OpenBookmarksIn: String, CaseIterable, Identifiable {
    case newTab, currentTab
    var id: String { rawValue }
    var title: String { self == .newTab ? "New Tab" : "Current Tab" }

    static let defaultsKey = "openBookmarksIn"
}

enum TabPolicy {
    static let restoreKey = "restoreTabs"

    /// A blank tab is always filled rather than leaving an empty tab behind.
    static func opensNewTab(currentTabIsBlank: Bool, preference: OpenBookmarksIn) -> Bool {
        !currentTabIsBlank && preference == .newTab
    }
}

/// A tab as saved between launches. `state` is WebKit’s opaque back/forward history.
struct SavedTab: Codable, Equatable {
    var id: UUID
    var url: String?
    var title: String
    var state: Data?
}

struct SavedTabs: Codable, Equatable {
    var tabs: [SavedTab]
    var selected: Int
}

/// Open tabs, saved only while Restore Tabs on Launch is on. A missing or damaged file
/// simply means starting with one blank tab.
struct TabStore {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory
            .appending(path: "LANBrowser", directoryHint: .isDirectory)
            .appending(path: "tabs.json")
    }

    func load() -> SavedTabs? {
        guard let data = try? Data(contentsOf: fileURL),
              var saved = try? JSONDecoder().decode(SavedTabs.self, from: data),
              !saved.tabs.isEmpty else { return nil }
        saved.selected = min(max(saved.selected, 0), saved.tabs.count - 1)
        return saved
    }

    func save(_ saved: SavedTabs) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(saved).write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
