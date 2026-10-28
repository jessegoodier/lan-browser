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
}

@MainActor
final class BrowserModel: NSObject, ObservableObject {
    let webView: WKWebView
    @Published var showingBookmarks = true
    @Published private(set) var address = ""
    @Published private(set) var title = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var pageError: String?
    @Published var message: String?
    @Published private(set) var activeDownloadCount = 0
    @Published var export: DownloadExport?
    private var observations: [NSKeyValueObservation] = []
    private var downloads: [ObjectIdentifier: WKDownload] = [:]
    private var destinations: [ObjectIdentifier: URL] = [:]
    private var pendingExports: [DownloadExport] = []
    private var exportingURL: URL?
    private var requestedURL: URL?
    private let downloadDirectory: URL

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        #if DEBUG
        PageDiagnostics.install(in: configuration.userContentController)
        #endif
        webView = WKWebView(frame: .zero, configuration: configuration)
        downloadDirectory = FileManager.default.temporaryDirectory.appending(path: "LANBrowserDownloads", directoryHint: .isDirectory)
        super.init()
        // Downloads are foreground-only. Remove leftovers from a previous terminated session.
        try? FileManager.default.removeItem(at: downloadDirectory)
        try? FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = false
        observations = [
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.title, options: [.new]) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in self?.scheduleSync() }
        ]
    }

    nonisolated private func scheduleSync() {
        Task { @MainActor [weak self] in self?.synchronize() }
    }

    private func synchronize() {
        let displayedURL = pageError == nil ? (webView.url ?? requestedURL) : (requestedURL ?? webView.url)
        address = displayedURL?.absoluteString ?? ""
        title = webView.title ?? ""
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
    }

    /// Details about the page currently shown, read on demand when the info sheet opens.
    func pageInfo() -> PageInfo {
        let url = webView.url ?? requestedURL
        let isHTTPS = url?.scheme?.lowercased() == "https"
        var subject: String?
        var issuer: String?
        var trusted: Bool?
        if isHTTPS, let trust = webView.serverTrust {
            trusted = SecTrustEvaluateWithError(trust, nil)
            let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
            subject = chain.first.flatMap { SecCertificateCopySubjectSummary($0) as String? }
            // The issuer is the next certificate in the chain; a self-signed leaf is its own issuer.
            issuer = (chain.dropFirst().first ?? chain.first).flatMap { SecCertificateCopySubjectSummary($0) as String? }
        }
        return PageInfo(
            url: address,
            title: title,
            scheme: url?.scheme?.uppercased() ?? "",
            host: url?.host ?? "",
            port: url?.port,
            isEncrypted: isHTTPS,
            isFullySecure: isHTTPS && webView.hasOnlySecureContent,
            certificateSubject: subject,
            certificateIssuer: issuer,
            certificateTrusted: trusted
        )
    }

    func navigate(_ input: String) -> Bool {
        guard let url = BrowserAddress.parse(input) else {
            message = "Enter a web address such as httpforever.com or http://192.168.1.20:8080/."
            return false
        }
        requestedURL = url
        address = url.absoluteString
        pageError = nil
        showingBookmarks = false
        webView.load(URLRequest(url: url))
        return true
    }

    func back() { pageError = nil; webView.goBack() }
    func forward() { pageError = nil; webView.goForward() }
    func reloadOrStop() {
        if webView.isLoading { webView.stopLoading() }
        else if pageError != nil { retry() }
        else { webView.reload() }
    }
    func retry() {
        pageError = nil
        if let url = requestedURL ?? webView.url { webView.load(URLRequest(url: url)) }
    }

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

    private func attach(_ download: WKDownload) {
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

    private func failed(_ error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled,
              !(nsError.domain == "WebKitErrorDomain" && nsError.code == 102) else { return }
        pageError = "Couldn’t load this page. On a home network, check the address and port. On public Wi-Fi, open HTTP Forever so the captive portal can show its sign-in page.\n\n\(error.localizedDescription)"
        synchronize()
    }
}

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        guard ["http", "https", "about", "blob", "data"].contains(scheme) else {
            decisionHandler(.cancel)
            message = "LAN Browser opens HTTP and HTTPS pages. This link uses an unsupported address type."
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true, ["http", "https"].contains(scheme) {
            requestedURL = url
        }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        decisionHandler(!navigationResponse.canShowMIMEType || disposition.lowercased().hasPrefix("attachment") ? .download : .allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        pageError = nil
        synchronize()
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        requestedURL = webView.url
        synchronize()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        requestedURL = webView.url
        synchronize()
    }
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        requestedURL = webView.url ?? requestedURL
        synchronize()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageError = "The page stopped responding. Tap Retry to reload it."
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { attach(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { attach(download) }
}

extension BrowserModel: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    private func present(_ alert: UIAlertController, fallback: () -> Void) {
        guard var presenter = webView.window?.rootViewController else { fallback(); return }
        while let presented = presenter.presentedViewController { presenter = presented }
        guard !(presenter is UIAlertController) else { fallback(); return }
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        let alert = UIAlertController(title: webView.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert) { completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        let alert = UIAlertController(title: webView.url?.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert) { completionHandler(false) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
        let alert = UIAlertController(title: webView.url?.host, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in completionHandler(alert?.textFields?.first?.text) })
        present(alert) { completionHandler(nil) }
    }
}

extension BrowserModel: WKDownloadDelegate {
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
