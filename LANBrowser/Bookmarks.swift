import Combine
import Foundation

struct Bookmark: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var url: String

    init(id: UUID = UUID(), title: String, url: String) {
        self.id = id
        self.title = title
        self.url = url
    }

    static let httpForever = Bookmark(title: "HTTP Forever Captive Portal", url: "http://httpforever.com/")
}

@MainActor
final class BookmarkStore: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published var errorMessage: String?
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.applicationSupportDirectory
            .appending(path: "LANBrowser", directoryHint: .isDirectory)
            .appending(path: "bookmarks.json")
        if FileManager.default.fileExists(atPath: self.fileURL.path) {
            do {
                bookmarks = try JSONDecoder().decode([Bookmark].self, from: Data(contentsOf: self.fileURL))
            } catch {
                errorMessage = "Your bookmarks could not be read. The saved file has been left in place. \(error.localizedDescription)"
            }
        } else {
            bookmarks = [.httpForever]
            persist(bookmarks)
        }
    }

    @discardableResult
    func save(_ bookmark: Bookmark) -> Bool {
        var updated = bookmarks
        if let index = updated.firstIndex(where: { $0.id == bookmark.id }) {
            updated[index] = bookmark
        } else {
            updated.append(bookmark)
        }
        return persist(updated)
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
