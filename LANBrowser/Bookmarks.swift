import Combine
import Foundation

struct Bookmark: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var url: String
    var faviconPNG: Data?

    init(id: UUID = UUID(), title: String, url: String, faviconPNG: Data? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.faviconPNG = faviconPNG
    }

    static let httpForever = Bookmark(title: "HTTP Forever Captive Portal", url: "http://httpforever.com/")
}

@MainActor
final class BookmarkStore: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published var errorMessage: String?
    private let fileURL: URL
    private var canWrite = true

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory
            .appending(path: "LANBrowser", directoryHint: .isDirectory)
            .appending(path: "bookmarks.json")
        if FileManager.default.fileExists(atPath: self.fileURL.path) {
            do {
                bookmarks = try JSONDecoder().decode([Bookmark].self, from: Data(contentsOf: self.fileURL))
                var seen: Set<String> = []
                let unique = bookmarks.filter { bookmark in
                    guard let key = BrowserAddress.bookmarkKey(bookmark.url) else { return true }
                    return seen.insert(key).inserted
                }
                if unique.count != bookmarks.count {
                    do {
                        let backup = self.fileURL.deletingLastPathComponent()
                            .appending(path: "bookmarks-before-deduplication-\(UUID().uuidString).json")
                        try FileManager.default.copyItem(at: self.fileURL, to: backup)
                        if !persist(unique) { canWrite = false }
                    } catch {
                        canWrite = false
                        errorMessage = "Your duplicate bookmarks could not be backed up. The saved file has been left in place. \(error.localizedDescription)"
                    }
                }
            } catch {
                canWrite = false
                errorMessage = "Your bookmarks could not be read. The saved file has been left in place. \(error.localizedDescription)"
            }
        } else {
            bookmarks = [.httpForever]
            persist(bookmarks)
        }
    }

    @discardableResult
    func save(_ bookmark: Bookmark) -> Bool {
        guard existing(for: bookmark.url, excluding: bookmark.id) == nil else {
            errorMessage = "This address is already bookmarked."
            return false
        }
        var updated = bookmarks
        var bookmark = bookmark
        if let previous = updated.first(where: { $0.id == bookmark.id }),
           BrowserAddress.bookmarkKey(previous.url) != BrowserAddress.bookmarkKey(bookmark.url) {
            bookmark.faviconPNG = nil
        }
        if let index = updated.firstIndex(where: { $0.id == bookmark.id }) {
            updated[index] = bookmark
        } else {
            updated.append(bookmark)
        }
        return persist(updated)
    }

    func existing(for input: String, excluding id: UUID? = nil) -> Bookmark? {
        guard let key = BrowserAddress.bookmarkKey(input) else { return nil }
        return bookmarks.first { $0.id != id && BrowserAddress.bookmarkKey($0.url) == key }
    }

    func updateFavicon(_ data: Data, id: UUID, url: String) {
        guard var bookmark = bookmarks.first(where: { $0.id == id && $0.url == url }) else { return }
        bookmark.faviconPNG = data
        _ = save(bookmark)
    }

    func delete(at offsets: IndexSet) {
        let updated = bookmarks.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        persist(updated)
    }

    func move(from offsets: IndexSet, to destination: Int) {
        let moving = bookmarks.enumerated().filter { offsets.contains($0.offset) }.map(\.element)
        var updated = bookmarks.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = destination - offsets.filter { $0 < destination }.count
        updated.insert(contentsOf: moving, at: insertion)
        persist(updated)
    }

    @discardableResult
    private func persist(_ updated: [Bookmark]) -> Bool {
        guard canWrite else { return false }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(updated).write(to: fileURL, options: .atomic)
            bookmarks = updated
            return true
        } catch {
            errorMessage = "Your bookmark changes could not be saved. \(error.localizedDescription)"
            return false
        }
    }
}
