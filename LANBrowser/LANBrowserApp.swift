import SwiftUI

@main
struct LANBrowserApp: App {
    var body: some Scene {
        WindowGroup { BrowserScreen() }
            .commands { BrowserCommands() }
    }
}

/// Menu bar items and keyboard shortcuts for iPad hardware keyboards and the Mac, matching Safari’s.
private struct BrowserCommands: Commands {
    @FocusedValue(\.browserActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            item("New Tab", .newTab).keyboardShortcut("t")
            item("Open Location…", .openAddress).keyboardShortcut("l")
            item("Close Tab", .closeTab).keyboardShortcut("w")
        }
        CommandGroup(replacing: .appSettings) {
            item("Settings…", .settings).keyboardShortcut(",")
        }
        CommandGroup(before: .toolbar) {
            item("Reload Page", .reload, available: actions?.hasPage == true && actions?.isLoading == false)
                .keyboardShortcut("r")
            item("Stop Loading", .stop, available: actions?.isLoading == true).keyboardShortcut(".")
            item("Show All Tabs", .showTabs).keyboardShortcut("\\", modifiers: [.command, .shift])
        }
        CommandMenu("History") {
            item("Back", .back, available: actions?.canGoBack == true).keyboardShortcut("[")
            item("Forward", .forward, available: actions?.canGoForward == true).keyboardShortcut("]")
        }
        CommandMenu("Bookmarks") {
            item("Add Bookmark…", .addBookmark).keyboardShortcut("d")
        }
    }

    private func item(_ title: String, _ command: BrowserCommand, available: Bool = true) -> some View {
        Button(title) { actions?.perform(command) }
            .disabled(actions?.enabled != true || !available)
    }
}
