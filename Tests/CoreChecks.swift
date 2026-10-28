import Foundation

@main
struct CoreChecks {
    @MainActor
    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) {
            precondition(condition(), description)
            count += 1
        }
        let valid: [(String, String)] = [
            ("nas.local:8888", "http://nas.local:8888"),
            ("http://nas.local:8888/", "http://nas.local:8888/"),
            ("nas.local:8888/path?q=hello#section", "http://nas.local:8888/path?q=hello#section"),
            ("  server.local  ", "http://server.local"),
            ("192.168.1.20:8080/dashboard", "http://192.168.1.20:8080/dashboard"),
            ("https://example.com/", "https://example.com/"),
            ("HTTP://nas.local:8888/", "HTTP://nas.local:8888/"),
            ("//nas.local:8888/", "http://nas.local:8888/"),
            ("[fd00::1]:8080/", "http://[fd00::1]:8080/")
        ]
        for (input, expected) in valid {
            check(BrowserAddress.parse(input)?.absoluteString == expected, "Address parsing: \(input)")
        }
        for input in ["", "  ", "hello world", "http://", "https://", "ftp://nas.local/", "file:///tmp/a", "http://nas.local:0", "http://nas.local:65536", "http://nas.local:abc", "http://user:password@nas.local/", "nas.local\n:8888"] {
            check(BrowserAddress.parse(input) == nil, "Reject invalid address: \(input)")
        }

        let directory = FileManager.default.temporaryDirectory.appending(path: "LANBrowserChecks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "bookmarks.json")
        let store = BookmarkStore(fileURL: file)
        check(store.bookmarks.count == 1 && store.bookmarks[0] == .httpForever, "Seed HTTP Forever on first launch")
        let custom = Bookmark(title: "Router", url: "http://192.168.1.1/")
        check(store.save(custom), "Save bookmark")
        var edited = custom
        edited.title = "Home Router"
        edited.url = "https://192.168.1.1/"
        check(store.save(edited), "Edit bookmark")
        check(store.bookmarks.count == 2, "Editing does not duplicate")
        store.move(from: IndexSet(integer: 1), to: 0)
        let reopened = BookmarkStore(fileURL: file)
        check(reopened.bookmarks.first == edited, "Order and edits survive relaunch")
        reopened.delete(at: IndexSet(integer: 0))
        reopened.delete(at: IndexSet(integer: 0))
        check(BookmarkStore(fileURL: file).bookmarks.isEmpty, "Empty bookmarks stay empty after relaunch")
        try Data("not valid json".utf8).write(to: file)
        let corrupt = BookmarkStore(fileURL: file)
        check(corrupt.errorMessage != nil, "Corruption is reported")
        let preserved = try String(contentsOf: file, encoding: .utf8)
        check(preserved == "not valid json", "Corrupt file is not silently overwritten")
        let blocked = directory.appending(path: "not-a-directory")
        try Data().write(to: blocked)
        let failed = BookmarkStore(fileURL: blocked.appending(path: "bookmarks.json"))
        check(failed.errorMessage != nil, "Write errors are reported")
        check(!failed.save(custom), "Failed writes return failure")
        check(!failed.bookmarks.contains(custom), "Failed writes do not claim persistence")
        print("Passed \(count) core checks (address parsing and bookmark persistence).")
    }
}
