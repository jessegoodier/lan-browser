import Combine
import Foundation
import UIKit
import WebKit

struct DownloadExport: Identifiable {
    let id = UUID()
    let url: URL
}

#if DEBUG
import os

/// Debug-only: mirrors page console errors, WebSocket/WebRTC state and video errors into
/// the Xcode console (subsystem com.jesse.lanbrowser, category "page") to diagnose stream failures.
@MainActor
private final class PageDiagnostics: NSObject, WKScriptMessageHandler {
    private static let handler = PageDiagnostics()
    private let logger = Logger(subsystem: "com.jesse.lanbrowser", category: "page")

    static func install(in controller: WKUserContentController) {
        controller.add(handler, name: "lanLog")
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        logger.log("\(String(describing: message.body), privacy: .public)")
    }

    private static let script = """
    (function () {
      if (window.__lanLog) return;
      window.__lanLog = true;
      const post = (kind, detail) => {
        try { window.webkit.messageHandlers.lanLog.postMessage(kind + ' ' + detail); } catch (e) {}
      };
      const text = a => {
        try {
          if (typeof a === 'string') return a;
          // Safari's native errors (e.g. fetch "Load failed") have no stack and serialize to {}.
          if (a instanceof Error) return a.name + ': ' + a.message + (a.stack ? ' ' + a.stack : '');
          return (a && a.stack) || JSON.stringify(a);
        } catch (e) { return String(a); }
      };
      post('page.start', location.href + ' MediaSource=' + ('MediaSource' in window) +
        ' ManagedMediaSource=' + ('ManagedMediaSource' in window) + ' RTCPeerConnection=' + ('RTCPeerConnection' in window));
      ['error', 'warn'].forEach(level => {
        const original = console[level];
        console[level] = function () {
          post('console.' + level, Array.from(arguments).map(text).join(' '));
          return original.apply(console, arguments);
        };
      });
      window.addEventListener('error', e => post('window.error', e.message + ' @' + e.filename + ':' + e.lineno));
      window.addEventListener('unhandledrejection', e => post('unhandledrejection', text(e.reason)));
      // Media errors don't bubble, so listen in the capture phase.
      document.addEventListener('error', e => {
        const t = e.target;
        if (t && t.tagName === 'VIDEO') {
          post('video.error', 'code=' + (t.error && t.error.code) + ' message=' + (t.error && t.error.message) + ' src=' + (t.currentSrc || t.src));
        }
      }, true);
      const NativeWS = window.WebSocket;
      window.WebSocket = function (url, protocols) {
        const ws = protocols === undefined ? new NativeWS(url) : new NativeWS(url, protocols);
        post('ws.new', url);
        ws.addEventListener('open', () => post('ws.open', url));
        ws.addEventListener('error', () => post('ws.error', url));
        ws.addEventListener('close', e => post('ws.close', url + ' code=' + e.code + ' reason=' + e.reason + ' clean=' + e.wasClean));
        ws.addEventListener('message', e => { if (typeof e.data === 'string') post('ws.message', e.data.slice(0, 300)); });
        return ws;
      };
      window.WebSocket.prototype = NativeWS.prototype;
      ['CONNECTING', 'OPEN', 'CLOSING', 'CLOSED'].forEach(k => { window.WebSocket[k] = NativeWS[k]; });
      const NativePC = window.RTCPeerConnection;
      if (NativePC) {
        window.RTCPeerConnection = class extends NativePC {
          constructor(...args) {
            super(...args);
            this.addEventListener('connectionstatechange', () => post('rtc.connection', this.connectionState));
            this.addEventListener('iceconnectionstatechange', () => post('rtc.ice', this.iceConnectionState));
          }
        };
      }
      // The page reads streamed responses (e.g. MJPEG) with getReader(); log how far a stream got and why it ended.
      if (window.ReadableStreamDefaultReader) {
        const nativeRead = ReadableStreamDefaultReader.prototype.read;
        const counters = new WeakMap();
        ReadableStreamDefaultReader.prototype.read = function () {
          const reader = this;
          return nativeRead.apply(this, arguments).then(result => {
            const c = counters.get(reader) || { bytes: 0, chunks: 0, next: 16 * 1048576 };
            counters.set(reader, c);
            if (result.value && result.value.length !== undefined) {
              if (c.chunks === 0) {
                post('stream.first-chunk', 'length=' + result.value.length + ' head=' +
                  Array.from(result.value.slice(0, 80)).map(b => (b >= 32 && b < 127) ? String.fromCharCode(b) : '.').join(''));
              }
              c.bytes += result.value.length; c.chunks++;
              if (c.bytes >= c.next) { c.next += 16 * 1048576; post('stream.progress', 'bytes=' + c.bytes + ' chunks=' + c.chunks); }
            }
            if (result.done) post('stream.done', 'bytes=' + c.bytes + ' chunks=' + c.chunks);
            return result;
          }, err => {
            const c = counters.get(reader) || { bytes: 0, chunks: 0 };
            if (!(err && err.name === 'AbortError')) post('stream.read-failed', text(err) + ' bytes=' + c.bytes + ' chunks=' + c.chunks);
            throw err;
          });
        };
      }
      const nativeFetch = window.fetch;
      window.fetch = function (input) {
        const url = typeof input === 'string' ? input : (input && input.url);
        const signal = arguments[1] && arguments[1].signal;
        post('fetch.start', url + (signal ? ' (has abort signal)' : ''));
        return nativeFetch.apply(this, arguments).then(response => {
          post('fetch.response', url + ' status=' + response.status + ' type=' + response.headers.get('content-type'));
          return response;
        }, err => {
          post('fetch.failed', url + ' ' + text(err) + (signal && signal.aborted ? ' [aborted: ' + text(signal.reason) + ']' : ''));
          throw err;
        });
      };
    })();
    """
}
#endif

struct PageInfo {
    let url: String
    let title: String
    let scheme: String
    let host: String
    let port: Int?
    let isEncrypted: Bool
    /// True when the page loaded over HTTPS with no insecure subresources.
    let isFullySecure: Bool
    let certificateSubject: String?
    let certificateIssuer: String?
    let certificateTrusted: Bool?
    let response: PageResponse?
    let certificateIssue: CertificateIssue?
}

/// App-level browser state: the open tabs, downloads and the export queue.
@MainActor
final class BrowserSession: NSObject, ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published private(set) var selectedID = UUID()
    @Published var message: String?
    @Published private(set) var activeDownloadCount = 0
    @Published var export: DownloadExport?
    private var tabChanges: [UUID: AnyCancellable] = [:]
    private var downloads: [ObjectIdentifier: WKDownload] = [:]
    private var destinations: [ObjectIdentifier: URL] = [:]
    private var pendingExports: [DownloadExport] = []
    private var exportingURL: URL?
    private let downloadDirectory: URL
    private let tabStore: TabStore
    private var saveTask: Task<Void, Never>?

    init(tabStore: TabStore = TabStore()) {
        self.tabStore = tabStore
        downloadDirectory = FileManager.default.temporaryDirectory.appending(path: "LANBrowserDownloads", directoryHint: .isDirectory)
        super.init()
        // Downloads are foreground-only. Remove leftovers from a previous terminated session.
        try? FileManager.default.removeItem(at: downloadDirectory)
        try? FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        if Self.restoresTabs, let saved = tabStore.load() {
            tabs = saved.tabs.map { BrowserTab(session: self, restoring: $0) }
            selectedID = tabs[saved.selected].id
        } else {
            tabStore.clear()
            let tab = BrowserTab(session: self)
            tabs = [tab]
            selectedID = tab.id
        }
        tabs.forEach(observe)
    }

    static func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        #if DEBUG
        PageDiagnostics.install(in: configuration.userContentController)
        #endif
        return configuration
    }

    static var restoresTabs: Bool { UserDefaults.standard.object(forKey: TabPolicy.restoreKey) as? Bool ?? true }

    var selectedTab: BrowserTab { tabs.first { $0.id == selectedID } ?? tabs[0] }

    // MARK: Tabs

    /// Re-publishes tab changes so views observing the session redraw for the selected tab.
    private func observe(_ tab: BrowserTab) {
        tabChanges[tab.id] = tab.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
    }

    private func insert(_ tab: BrowserTab) {
        let index = tabs.firstIndex { $0.id == selectedID }.map { $0 + 1 } ?? tabs.endIndex
        tabs.insert(tab, at: index)
        observe(tab)
        select(tab)
    }

    @discardableResult
    func newTab() -> BrowserTab {
        let tab = BrowserTab(session: self)
        insert(tab)
        return tab
    }

    func openWindow(configuration: WKWebViewConfiguration) -> BrowserTab {
        let tab = BrowserTab(session: self, configuration: configuration)
        insert(tab)
        return tab
    }

    func select(_ tab: BrowserTab) {
        guard tab.id != selectedID else { return }
        let previous = selectedTab
        Task { await previous.captureSnapshot() }
        selectedID = tab.id
        tabsChanged()
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tab.close()
        tabs.remove(at: index)
        tabChanges[tab.id] = nil
        if tabs.isEmpty {
            let blank = BrowserTab(session: self)
            tabs = [blank]
            observe(blank)
        }
        if tab.id == selectedID { selectedID = tabs[min(index, tabs.count - 1)].id }
        tabsChanged()
    }

    /// Opens an address in a new tab or the current one, after checking it is a web address.
    @discardableResult
    func open(_ input: String, newTab: Bool) -> Bool {
        guard let url = BrowserAddress.parse(input) else {
            message = "Enter a web address such as httpforever.com or http://192.168.1.20:8080/."
            return false
        }
        (newTab ? self.newTab() : selectedTab).navigate(to: url)
        return true
    }

    /// Bookmarks follow the Open Bookmarks In setting, but always fill a blank tab.
    @discardableResult
    func openBookmark(_ input: String) -> Bool {
        let preference = OpenBookmarksIn(rawValue: UserDefaults.standard.string(forKey: OpenBookmarksIn.defaultsKey) ?? "") ?? .newTab
        return open(input, newTab: TabPolicy.opensNewTab(currentTabIsBlank: selectedTab.isBlank, preference: preference))
    }

    /// Saves open tabs shortly after a change, so a burst of navigations writes once.
    func tabsChanged() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveTabs()
        }
    }

    func saveTabs() {
        saveTask?.cancel()
        guard Self.restoresTabs else { tabStore.clear(); return }
        let index = tabs.firstIndex { $0.id == selectedID } ?? 0
        tabStore.save(SavedTabs(tabs: tabs.map { $0.saved() }, selected: index))
    }

    func clearWebsiteData() async {
        // Close every tab so open pages cannot immediately recreate cookies or storage.
        tabs.forEach { $0.close() }
        tabChanges.removeAll()
        let blank = BrowserTab(session: self)
        tabs = [blank]
        observe(blank)
        selectedID = blank.id
        saveTask?.cancel()
        tabStore.clear()
        await WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    // MARK: Downloads

    func finishExport() {
        if let exportingURL { try? FileManager.default.removeItem(at: exportingURL.deletingLastPathComponent()) }
        exportingURL = nil
        export = nil
    }

    func presentNextExport() {
        guard export == nil, exportingURL == nil, !pendingExports.isEmpty else { return }
        let next = pendingExports.removeFirst()
        exportingURL = next.url
        export = next
    }

    func attach(_ download: WKDownload) {
        downloads[ObjectIdentifier(download)] = download
        activeDownloadCount = downloads.count
        download.delegate = self
    }

    private func release(_ download: WKDownload, removeFile: Bool) {
        let key = ObjectIdentifier(download)
        downloads.removeValue(forKey: key)
        if let url = destinations.removeValue(forKey: key), removeFile {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        activeDownloadCount = downloads.count
    }
}

extension BrowserSession: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        let directory = downloadDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let sanitized = (suggestedFilename as NSString).lastPathComponent
            let filename = sanitized.isEmpty || [".", "..", "/"].contains(sanitized) ? "Download" : sanitized
            let destination = directory.appendingPathComponent(filename)
            destinations[ObjectIdentifier(download)] = destination
            completionHandler(destination)
        } catch {
            message = "Couldn’t start this download. \(error.localizedDescription)"
            completionHandler(nil)
            release(download, removeFile: true)
        }
    }
    func downloadDidFinish(_ download: WKDownload) {
        if let url = destinations[ObjectIdentifier(download)] {
            pendingExports.append(DownloadExport(url: url))
        }
        release(download, removeFile: false)
        presentNextExport()
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        release(download, removeFile: true)
        message = "Download failed. Try the download link again. \(error.localizedDescription)"
    }
}
