import Combine
import Foundation
import UIKit
import WebKit

/// One tab: its web view, navigation state and page errors. The web view is created on
/// first use, so restored tabs cost nothing until they are selected.
@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable {
    let id: UUID
    @Published var showingStartPage: Bool
    @Published private(set) var address = ""
    @Published private(set) var title = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var pageError: String?
    @Published private(set) var snapshot: UIImage?
    /// The main page’s last HTTP response, so non-200 answers are never silent.
    @Published private(set) var response: PageResponse?
    /// Untrusted certificates accepted in this tab, by host, so the page can be marked.
    @Published private(set) var untrustedCertificates: [String: CertificateIssue] = [:]
    private var pendingMethod = "GET"
    weak var session: BrowserSession?
    private var loadedWebView: WKWebView?
    private var configuration: WKWebViewConfiguration?
    private var restoredState: Data?
    private var observations: [NSKeyValueObservation] = []
    private var requestedURL: URL?

    /// A blank tab, or one restored from a previous launch.
    init(session: BrowserSession, restoring saved: SavedTab? = nil) {
        id = saved?.id ?? UUID()
        self.session = session
        showingStartPage = saved?.url == nil
        super.init()
        if let saved, let url = saved.url {
            address = url
            title = saved.title
            requestedURL = URL(string: url)
            restoredState = saved.state
        }
    }

    /// A tab for a page that asked for a new window. WebKit requires the returned web view
    /// to use the configuration it supplies, and it loads the request itself.
    init(session: BrowserSession, configuration: WKWebViewConfiguration) {
        id = UUID()
        self.session = session
        self.configuration = configuration
        showingStartPage = false
        super.init()
        _ = webView
    }

    var webView: WKWebView {
        if let loadedWebView { return loadedWebView }
        let webView = WKWebView(frame: .zero, configuration: configuration ?? BrowserSession.makeWebViewConfiguration())
        configuration = nil
        loadedWebView = webView
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
        if let restoredState {
            webView.interactionState = restoredState
            self.restoredState = nil
        } else if let requestedURL, !showingStartPage, requestedURL.scheme != "about" {
            webView.load(URLRequest(url: requestedURL))
        }
        return webView
    }

    /// A response that is itself the error (not a 200 page that later failed or crashed).
    var errorResponse: PageResponse? { response.flatMap { $0.statusCode == 200 ? nil : $0 } }

    /// The certificate problem for the page shown, if it was opened despite one.
    var certificateIssue: CertificateIssue? {
        guard let url = URL(string: address), url.scheme?.lowercased() == "https", let host = url.host else { return nil }
        return untrustedCertificates[DeviceStore.key(host)]
    }

    /// Nothing has been opened in this tab, so a bookmark can fill it instead of opening another.
    var isBlank: Bool { address.isEmpty }

    nonisolated private func scheduleSync() {
        Task { @MainActor [weak self] in self?.synchronize() }
    }

    private func synchronize() {
        guard let webView = loadedWebView else { return }
        let displayedURL = pageError == nil ? (webView.url ?? requestedURL) : (requestedURL ?? webView.url)
        address = displayedURL?.absoluteString ?? ""
        title = webView.title ?? ""
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
    }

    func saved() -> SavedTab {
        let pageURL = address.isEmpty || address.hasPrefix("about:") ? nil : address
        let state = pageURL == nil ? nil : (loadedWebView?.interactionState as? Data) ?? restoredState
        return SavedTab(id: id, url: pageURL, title: title, state: state)
    }

    func captureSnapshot() async {
        guard let loadedWebView, !showingStartPage, loadedWebView.window != nil else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 360
        if let image = try? await loadedWebView.takeSnapshot(configuration: configuration) { snapshot = image }
    }

    func close() {
        loadedWebView?.stopLoading()
        loadedWebView?.navigationDelegate = nil
        loadedWebView?.uiDelegate = nil
        observations = []
    }

    /// Details about the page currently shown, read on demand when the info sheet opens.
    func pageInfo() -> PageInfo {
        let url = loadedWebView?.url ?? requestedURL
        let isHTTPS = url?.scheme?.lowercased() == "https"
        var subject: String?
        var issuer: String?
        var trusted: Bool?
        if isHTTPS, let trust = loadedWebView?.serverTrust {
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
            isFullySecure: isHTTPS && (loadedWebView?.hasOnlySecureContent ?? false),
            certificateSubject: subject,
            certificateIssuer: issuer,
            certificateTrusted: trusted,
            response: response,
            certificateIssue: certificateIssue
        )
    }

    func navigate(to url: URL) {
        requestedURL = url
        address = url.absoluteString
        pageError = nil
        showingStartPage = false
        webView.load(URLRequest(url: url))
    }

    func openBrowserCheck() {
        requestedURL = URL(string: "about:blank")
        address = "about:blank"
        pageError = nil
        showingStartPage = false
        webView.loadHTMLString("""
        <!doctype html><html lang="en"><head>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Browser Check</title>
        <style>body{font:18px system-ui;padding:24px;line-height:1.5;color-scheme:light dark}a,button{font:inherit}li{margin:20px 0}</style>
        </head><body><h1>Browser Check</h1>
        <p>If you can read this page, page rendering works. This check is built into LAN Browser and does not contact a server.</p>
        <ul><li><button onclick="const a=document.createElement('a');a.href=URL.createObjectURL(new Blob(['LAN Browser download works.\\n'],{type:'application/octet-stream'}));a.download='lan-browser-check.txt';document.body.appendChild(a);a.click();a.remove();">Save a sample file</button></li>
        <li><a href="http://httpforever.com/">Open HTTP Forever (internet or captive Wi-Fi required)</a></li>
        <li><a href="https://example.com/">Open an HTTPS page (internet required)</a></li></ul>
        <p>Save the sample file to Files, then open it to check its contents. Keep LAN Browser open until the save finishes.</p>
        <p>This local check does not test Wi-Fi portal interception or connectivity to your home server.</p>
        </body></html>
        """, baseURL: nil)
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

    private func failed(_ error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled,
              !(nsError.domain == "WebKitErrorDomain" && nsError.code == 102) else { return }
        let failingURL = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String
            ?? (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString ?? requestedURL?.absoluteString
        let underlying = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError).map { (domain: $0.domain, code: $0.code) }
        pageError = "Couldn’t load this page. On a home network, check the address and port. On public Wi-Fi, open HTTP Forever so the captive portal can show its sign-in page.\n\n\(error.localizedDescription)\n\n"
            + ErrorText.details(domain: nsError.domain, code: nsError.code, url: failingURL, underlying: underlying)
        synchronize()
    }
}

extension BrowserTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        guard ["http", "https", "about", "blob", "data"].contains(scheme) else {
            decisionHandler(.cancel)
            session?.message = "LAN Browser opens HTTP and HTTPS pages. This link uses an unsupported address type."
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true, let blocked = BlockedPorts.message(for: url) {
            decisionHandler(.cancel)
            requestedURL = url
            pageError = blocked
            synchronize()
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true, ["http", "https"].contains(scheme) {
            requestedURL = url
            pendingMethod = navigationAction.request.httpMethod ?? "GET"
        }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        let http = navigationResponse.response as? HTTPURLResponse
        let disposition = http?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        let download = !navigationResponse.canShowMIMEType || disposition.lowercased().hasPrefix("attachment")
        if navigationResponse.isForMainFrame, let http, !download || http.statusCode >= 400 {
            let headers = http.allHeaderFields.map { ResponseHeader(name: "\($0.key)", value: "\($0.value)") }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let page = PageResponse(method: pendingMethod, url: http.url?.absoluteString ?? address, statusCode: http.statusCode, headers: headers)
            response = page
            // An error answer is never saved as a file; say what came back instead.
            if download {
                decisionHandler(.cancel)
                pageError = "The server answered with an error, and its content isn’t something a page can show.\n\n\(page.summary)"
                synchronize()
                return
            }
        }
        decisionHandler(download ? .download : .allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        pageError = nil
        response = nil
        synchronize()
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        requestedURL = webView.url
        synchronize()
        session?.tabsChanged()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        requestedURL = webView.url
        synchronize()
        session?.tabsChanged()
    }
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        requestedURL = webView.url ?? requestedURL
        synchronize()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    /// Home devices often use self-signed certificates. For local addresses the page opens anyway and is
    /// marked with a red “!”; public sites keep the system’s normal rejection.
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let host = challenge.protectionSpace.host
        var error: CFError?
        guard !SecTrustEvaluateWithError(trust, &error), ServiceCatalog.isLocalHost(host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        untrustedCertificates[DeviceStore.key(host)] = CertificateIssue(host: host, trust: trust, error: error)
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageError = "The page stopped responding. Tap Retry to reload it."
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { session?.attach(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { session?.attach(download) }
}

extension BrowserTab: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let session { return session.openWindow(configuration: configuration).webView }
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
        alert.addTextField {
            $0.text = defaultText
            $0.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in completionHandler(alert?.textFields?.first?.text) })
        present(alert) { completionHandler(nil) }
    }
}
