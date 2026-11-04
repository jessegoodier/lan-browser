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
        let passwordDefaults = UserDefaults(suiteName: "LANBrowserPasswordChecks-\(UUID().uuidString)")!
        check(PasswordPolicy.isEnabled(in: passwordDefaults), "Password offers default to on")
        passwordDefaults.set(false, forKey: PasswordPolicy.enabledKey)
        check(!PasswordPolicy.isEnabled(in: passwordDefaults), "Password offers can be disabled")
        passwordDefaults.removeObject(forKey: PasswordPolicy.enabledKey)
        let httpOrigin = PasswordOrigin(URL(string: "http://NAS.local/login?secret=hidden")!)!
        check(httpOrigin.label == "http://nas.local:80", "Password origin excludes paths and queries")
        check(httpOrigin == PasswordOrigin(URL(string: "http://nas.local:80/other")!), "Default ports share a password origin")
        check(httpOrigin != PasswordOrigin(URL(string: "https://nas.local/")!), "HTTP and HTTPS passwords stay separate")
        check(httpOrigin != PasswordOrigin(URL(string: "http://nas.local:8080/")!), "Different service ports stay separate")
        check(PasswordOrigin(URL(string: "file:///tmp/login")!) == nil, "Only web origins can save passwords")
        check(PasswordOrigin(URL(string: "http://[fd00::1]:8080/")!)?.label == "http://[fd00::1]:8080", "IPv6 password origins")
        check(PasswordPolicy.autofillEnabled(in: passwordDefaults), "AutoFill defaults to on")
        passwordDefaults.set(false, forKey: PasswordPolicy.autofillKey)
        check(!PasswordPolicy.autofillEnabled(in: passwordDefaults), "AutoFill can be disabled independently")
        passwordDefaults.removeObject(forKey: PasswordPolicy.autofillKey)
        let olderAccount = SavedPassword(origin: httpOrigin, username: "alice", modifiedAt: Date(timeIntervalSince1970: 1))
        let newerAccount = SavedPassword(origin: httpOrigin, username: "bob", modifiedAt: Date(timeIntervalSince1970: 2))
        let accounts = [olderAccount, newerAccount]
        check(PasswordPolicy.accountToFill(accounts, origin: httpOrigin, username: "")?.username == "bob", "Empty forms use the most recently saved account")
        check(PasswordPolicy.accountToFill(accounts, origin: httpOrigin, username: "alice")?.username == "alice", "Entered usernames select their own saved password")
        check(PasswordPolicy.accountToFill(accounts, origin: httpOrigin, username: "ALICE") == nil, "Username matching preserves case")
        check(PasswordPolicy.accountToFill(accounts, origin: PasswordOrigin(URL(string: "https://nas.local/")!)!, username: "") == nil, "AutoFill never crosses schemes")
        check(PasswordPolicy.accountToFill(accounts, origin: PasswordOrigin(URL(string: "http://nas.local:8080/")!)!, username: "") == nil, "AutoFill never crosses ports")
        check(PasswordPolicy.accountToFill(accounts, origin: PasswordOrigin(URL(string: "http://other.local/")!)!, username: "") == nil, "AutoFill never crosses hosts")
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

        let canonical = BrowserAddress.bookmarkKey("HTTP://NAS.local:80")
        check(canonical == BrowserAddress.bookmarkKey("http://nas.local/"), "Equivalent bookmark origins")
        check(BrowserAddress.bookmarkKey("HTTPS://NAS.local:443") == BrowserAddress.bookmarkKey("https://nas.local/"), "HTTPS default port")
        for distinct in ["https://nas.local/", "http://nas.local:8080/", "http://nas.local/app", "http://nas.local/?a=1", "http://nas.local/#section"] {
            check(BrowserAddress.bookmarkKey(distinct) != canonical, "Keep distinct bookmark: \(distinct)")
        }
        check(BrowserAddress.bookmarkKey("http://nas.local/App") != BrowserAddress.bookmarkKey("http://nas.local/app"), "Paths remain case sensitive")
        check(BrowserAddress.bookmarkKey("http://nas.local/?b=2&a=1") != BrowserAddress.bookmarkKey("http://nas.local/?a=1&b=2"), "Query order is preserved")
        let uniqueFile = directory.appending(path: "unique/bookmarks.json")
        let uniqueStore = BookmarkStore(fileURL: uniqueFile)
        let firstBookmark = Bookmark(title: "First", url: "HTTP://NAS.local:80")
        check(uniqueStore.save(firstBookmark), "Save original URL spelling")
        let duplicate = Bookmark(title: "Second", url: "http://nas.local/")
        check(!uniqueStore.save(duplicate), "Reject duplicate add")
        check(uniqueStore.existing(for: duplicate.url) == firstBookmark, "Find existing bookmark for Add UI")
        var colliding = uniqueStore.bookmarks[0]
        colliding.url = duplicate.url
        check(!uniqueStore.save(colliding), "Reject colliding edit")
        check(BookmarkStore(fileURL: uniqueFile).bookmarks == uniqueStore.bookmarks, "Rejected writes leave disk unchanged")
        var withIcon = firstBookmark
        withIcon.faviconPNG = Data([1, 2, 3])
        check(uniqueStore.save(withIcon), "Edit own URL and icon")
        uniqueStore.updateFavicon(Data([9]), id: withIcon.id, url: "http://old.local/")
        check(uniqueStore.existing(for: withIcon.url)?.faviconPNG == Data([1, 2, 3]), "Stale icon URL ignored")
        var movedBookmark = withIcon
        movedBookmark.url = "http://elsewhere.local/"
        check(uniqueStore.save(movedBookmark), "Change bookmark address")
        check(uniqueStore.existing(for: movedBookmark.url)?.faviconPNG == nil, "Changing URL clears old icon")
        uniqueStore.delete(at: IndexSet(integer: 1))
        uniqueStore.updateFavicon(Data([9]), id: movedBookmark.id, url: movedBookmark.url)
        check(uniqueStore.bookmarks.count == 1, "Late icon cannot resurrect deleted bookmark")
        check(!corrupt.save(custom), "Corrupt bookmark files cannot be overwritten by a later save")
        let preservedAgain = try String(contentsOf: file, encoding: .utf8)
        check(preservedAgain == preserved, "Corrupt file preserved after save attempt")

        let migrationDirectory = directory.appending(path: "migration")
        try FileManager.default.createDirectory(at: migrationDirectory, withIntermediateDirectories: true)
        let migrationFile = migrationDirectory.appending(path: "bookmarks.json")
        let oldBookmarks = [firstBookmark, duplicate, custom]
        let oldData = try JSONEncoder().encode(oldBookmarks)
        try oldData.write(to: migrationFile)
        let migrated = BookmarkStore(fileURL: migrationFile)
        check(migrated.bookmarks == [firstBookmark, custom], "Migration keeps first identity, title and order")
        let backups = try FileManager.default.contentsOfDirectory(at: migrationDirectory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("bookmarks-before-deduplication-") }
        check(backups.count == 1, "Migration creates one backup")
        let backupData = try Data(contentsOf: backups[0])
        check(backupData == oldData, "Migration backup preserves exact original bytes")
        check(BookmarkStore(fileURL: migrationFile).bookmarks == migrated.bookmarks, "Migration survives relaunch")
        let migrationFiles = try FileManager.default.contentsOfDirectory(atPath: migrationDirectory.path)
        check(migrationFiles.count == 2, "Migration does not repeat")
        let lockedDirectory = directory.appending(path: "locked-migration")
        try FileManager.default.createDirectory(at: lockedDirectory, withIntermediateDirectories: true)
        let lockedFile = lockedDirectory.appending(path: "bookmarks.json")
        try oldData.write(to: lockedFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: lockedDirectory.path)
        let lockedStore = BookmarkStore(fileURL: lockedFile)
        let lockedBytes = try Data(contentsOf: lockedFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: lockedDirectory.path)
        check(lockedStore.errorMessage != nil && lockedStore.bookmarks == oldBookmarks, "Failed migration backup preserves the original list")
        check(lockedBytes == oldData && !lockedStore.save(custom), "Backup failure prevents later writes in this session")
        let legacy = Data("[{\"id\":\"\(custom.id.uuidString)\",\"title\":\"Router\",\"url\":\"http://192.168.1.1/\"}]".utf8)
        let decodedLegacy = try JSONDecoder().decode([Bookmark].self, from: legacy)
        check(decodedLegacy.first?.faviconPNG == nil, "Legacy bookmarks decode without an icon")
        let cachedService = DiscoveredService(name: "Fixture", type: "_http._tcp", url: URL(string: "http://fixture.local/")!, faviconPNG: Data([1, 2, 3]))
        let iconCache = DiscoveryCache(fileURL: directory.appending(path: "discovered.json"))
        iconCache.save(DiscoveryScan(date: Date(), services: [cachedService]))
        check(iconCache.load()?.services.first?.faviconPNG == cachedService.faviconPNG, "Discovery icon persists")
        iconCache.save(DiscoveryScan(date: Date(), services: []))
        iconCache.clear()
        check(BookmarkStore(fileURL: migrationFile).bookmarks == migrated.bookmarks, "Replacing and clearing discovery never changes bookmarks")

        let page = URL(string: "http://fixture.local/apps/index.html")!
        let iconHTML = """
        <!-- <link rel="icon" href="/comment.png"> -->
        <script>const text = '<link rel="icon" href="/script.png">';</script>
        <SCRIPT>const other = '<link rel="icon" href="/script2.png">';</script
         bar>
        <!-- <link rel="icon" href="/bang.png"> --!>
        <LINK HREF='../images/icon.png?a=1&amp;b=2' REL='shortcut ICON'>
        <link href="http://external.local/icon.png" rel=icon>
        <link href="//fixture.local:80/second.ico" rel=icon>
        <link href="/apple.png" rel=apple-touch-icon>
        """
        let candidates = FaviconPolicy.candidates(in: iconHTML, page: page).map(\.absoluteString)
        check(candidates == ["http://fixture.local/images/icon.png?a=1&b=2", "http://fixture.local:80/second.ico", "http://fixture.local/favicon.ico"], "Resolve icon links, entities, default port, and fallback")
        check(FaviconPolicy.resolve("https://fixture.local/icon.png", relativeTo: page) == nil, "Icons cannot change scheme")
        check(FaviconPolicy.resolve("http://fixture.local:8080/icon.png", relativeTo: page) == nil, "Icons cannot change port")
        check(FaviconPolicy.resolve("data:image/png;base64,AA==", relativeTo: page) == nil, "Ignore non-HTTP icons")
        func parsed(_ text: String, eof: Bool = false, limit: Int = 100) -> FaviconHTTP.Result {
            FaviconHTTP.parse(Data(text.utf8), limit: limit, eof: eof)
        }
        if case .complete(let reply) = parsed("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nabc") {
            check(reply.body == Data("abc".utf8), "Read a framed icon body")
        } else { check(false, "Expected complete response") }
        if case .incomplete = parsed("HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\na") { check(true, "Wait for fragmented body") }
        else { check(false, "Premature response completion") }
        if case .complete(let reply) = parsed("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nab\r\n1\r\nc\r\n0\r\n\r\n") {
            check(reply.body == Data("abc".utf8), "Decode chunked icon body")
        } else { check(false, "Chunked response failed") }
        for invalid in ["HTTP/1.1 200 OK\r\nContent-Length: 101\r\n\r\n", "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\na", "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\n", "HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\n\r\n"] {
            if case .rejected = parsed(invalid, eof: true) { check(true, "Reject oversized or malformed response") }
            else { check(false, "Invalid HTTP accepted") }
        }
        if case .complete(let reply) = parsed("HTTP/1.0 200 OK\r\n\r\nabc", eof: true) {
            check(reply.body == Data("abc".utf8), "Connection-close response")
        } else { check(false, "Missing EOF framing") }

        if CommandLine.arguments.count > 1 {
            let plistTypes = try JSONDecoder().decode([String].self, from: Data(CommandLine.arguments[1].utf8))
            check(plistTypes == ServiceCatalog.types, "NSBonjourServices matches ServiceCatalog.types")
        }
        let mapped: [(String, String, Int, [String: String], String)] = [
            ("_http._tcp", "192.168.1.40", 80, [:], "http://192.168.1.40/"),
            ("_http._tcp", "192.168.1.40", 8080, ["path": "admin"], "http://192.168.1.40:8080/admin"),
            ("_https._tcp", "192.168.1.40", 443, ["path": "/ui"], "https://192.168.1.40/ui"),
            ("_home-assistant._tcp", "192.168.1.5", 8123, [:], "http://192.168.1.5:8123/"),
            ("_plexmediasvr._tcp", "192.168.1.6", 32400, [:], "http://192.168.1.6:32400/web"),
            ("_ipp._tcp", "192.168.1.7", 631, [:], "http://192.168.1.7/"),
            ("_ipps._tcp", "192.168.1.7", 631, [:], "https://192.168.1.7/"),
            ("_octoprint._tcp", "192.168.1.8", 5000, ["path": "/"], "http://192.168.1.8:5000/"),
            ("_esphomelib._tcp", "192.168.1.9", 6053, [:], "http://192.168.1.9/"),
            ("_wled._tcp", "192.168.1.10", 80, [:], "http://192.168.1.10/")
        ]
        for (type, host, port, txt, expected) in mapped {
            check(ServiceCatalog.url(type: type, host: host, port: port, txt: txt)?.absoluteString == expected, "Service URL: \(type)")
        }
        let printerHTTP = DiscoveredService(name: "printer", type: "_http._tcp", url: URL(string: "http://192.168.1.7/")!)
        let printerIPP = DiscoveredService(name: "Office Printer", type: "_ipp._tcp", url: URL(string: "http://192.168.1.7/")!)
        let nas = DiscoveredService(name: "NAS", type: "_http._tcp", url: URL(string: "http://192.168.1.40:5000/")!)
        check(ServiceCatalog.merged([printerHTTP, printerIPP, nas]) == [nas, printerIPP], "Specific service types win duplicates")
        check(ServiceCatalog.merged([printerIPP, printerHTTP]) == [printerIPP], "Duplicate order does not matter")
        let brother = DiscoveredService(name: "Brother", type: "_http._tcp", url: URL(string: "http://brotherA1B2C3D4.local/")!, address: "10.0.0.232")
        let bookmarkedPrinter = Set(ServiceCatalog.endpointKeys(for: URL(string: "http://10.0.0.232/")!, address: nil))
        check(ServiceCatalog.isBookmarked(brother, bookmarked: bookmarkedPrinter), "Bookmarked IP and port hide a discovered host name")
        check(ServiceCatalog.isBookmarked(brother, bookmarked: Set(ServiceCatalog.endpointKeys(for: URL(string: "http://BrotherA1B2C3D4.local:80/admin")!, address: nil))), "Host name match ignores case, path, and an explicit default port")
        check(ServiceCatalog.isBookmarked(printerIPP, bookmarked: ["192.168.1.7:80"]), "IP-only discovery matches a bookmarked IP and port")
        let studio8888 = Set(ServiceCatalog.endpointKeys(for: URL(string: "http://studio.local:8888/")!, address: "10.0.3.46"))
        let studio3000 = DiscoveredService(name: "Grafana", type: "_http._tcp", url: URL(string: "http://studio.local:3000/")!, address: "10.0.3.46")
        check(!ServiceCatalog.isBookmarked(studio3000, bookmarked: studio8888), "Another port on a bookmarked device stays listed")
        let studioByIP = DiscoveredService(name: "Dev", type: "_http._tcp", url: URL(string: "http://10.0.3.46:8888/")!)
        check(ServiceCatalog.isBookmarked(studioByIP, bookmarked: studio8888), "Bookmarked host name matches discovery by its last-seen IP")
        check(!ServiceCatalog.isBookmarked(brother, bookmarked: Set(ServiceCatalog.endpointKeys(for: URL(string: "https://10.0.0.232/")!, address: nil))), "HTTPS bookmark on 443 doesn’t hide the HTTP page on 80")
        for host in ["nas.local", "NAS.LOCAL", "nas", "localhost", "10.0.0.2", "172.20.1.1", "192.168.1.1", "169.254.3.4", "127.0.0.1", "fe80::1", "fd00::1", "::1"] {
            check(ServiceCatalog.isLocalHost(host), "Local host: \(host)")
        }
        for host in ["httpforever.com", "8.8.8.8", "172.32.0.1", "192.169.1.1", "2001:db8::1"] {
            check(!ServiceCatalog.isLocalHost(host), "Internet host: \(host)")
        }

        let target = DiagnosticTarget(url: URL(string: "http://nas.local:8080/dashboard")!)!
        check(target.host == "nas.local" && target.port == 8080 && !target.secure && target.path == "/dashboard", "Diagnostic target from URL")
        check(target.hostHeader == "nas.local:8080" && target.isLocal, "Host header keeps a non-default port")
        check(DiagnosticTarget(url: URL(string: "https://[fd00::1]/")!)?.hostHeader == "[fd00::1]", "IPv6 host header uses brackets")
        check(DiagnosticTarget(url: URL(string: "about:blank")!) == nil, "Only HTTP and HTTPS can be diagnosed")
        check(DiagnosticTarget(url: URL(string: "http://10.0.0.5/login.html?next=%2F")!)?.path == "/login.html?next=%2F", "Request path keeps the query")
        let base = URL(string: "http://10.0.0.1/")!
        check(Redirects.next(from: base, status: 301, location: "https://10.0.0.1/")?.absoluteString == "https://10.0.0.1/", "Absolute redirect")
        check(Redirects.next(from: base, status: 302, location: "/login?x=1")?.absoluteString == "http://10.0.0.1/login?x=1", "Relative redirect resolves against the page")
        check(Redirects.next(from: base, status: 304, location: "/") == nil && Redirects.next(from: base, status: 200, location: "/") == nil, "304 and 200 aren’t redirects")
        let response = "HTTP/1.1 404 Not Found\r\nserver: nginx/1.25\r\nContent-Length: 0\r\n\r\nServer: body"
        check(DiagnosticsText.statusCode(in: response) == 404, "Parse HTTP status code")
        check(DiagnosticsText.header("Server", in: response) == "nginx/1.25", "Parse header case-insensitively, ignoring the body")
        check(DiagnosticsText.statusCode(in: "SSH-2.0-OpenSSH_9.6\r\n") == nil, "Non-HTTP banner has no status")
        check(DiagnosticsText.advice(for: .refused, target: target, device: .iPhone).contains("port 8080"), "Refused advice names the port")
        check(DiagnosticsText.advice(for: .nameNotFound, target: target, device: .iPhone).contains(".local"), "Lookup advice explains .local names")
        check(DiagnosticsText.advice(for: .unreachable, target: target, device: .iPad).contains("this iPad and the device"), "Advice names the iPad")
        check(DiagnosticsText.wrongInterface(device: .mac).hasPrefix("This Mac isn’t on Wi-Fi"), "Advice names the Mac")
        let macPermission = DiagnosticsText.advice(for: .permissionDenied, target: target, device: .mac)
        check(macPermission.contains("System Settings › Privacy & Security › Local Network") && !macPermission.contains("iOS"),
              "Mac permission advice points to System Settings")
        check(DiagnosticsText.advice(for: .permissionDenied, target: target, device: .iPhone).contains("If iOS just asked, tap Allow"),
              "iPhone permission advice is unchanged")
        let steps = [DiagnosticStep(kind: .network, status: .passed, detail: "Wi-Fi"), DiagnosticStep(kind: .port, status: .failed, detail: "Refused", advice: "Start it.")]
        let report = DiagnosticsText.report(url: URL(string: "http://nas.local:8080/")!, steps: steps)
        check(report.contains("✓ Network: Wi-Fi") && report.contains("✗ Port: Refused\n  Start it."), "Report lists each step and advice")

        check(DeviceStore.key("Studio.LOCAL.") == "studio.local" && DeviceStore.key("[FD00::1]") == "fd00::1", "Device keys are normalized")
        check(DeviceStore.isIPAddress("10.0.2.2") && DeviceStore.isIPAddress("fd00::1") && !DeviceStore.isIPAddress("studio.local") && !DeviceStore.isIPAddress("1.2.3.999"), "Detect IP addresses")
        check(DeviceStore.defaultName(for: "studio.local") == "studio", "Default name drops .local")
        check(DeviceStore.defaultName(for: "10.0.0.232", hostname: "brothera1b2c3d4.localdomain.") == "brothera1b2c3d4", "IP uses reverse-lookup name")
        check(DeviceStore.defaultName(for: "10.0.0.232") == "10.0.0.232" && DeviceStore.defaultName(for: "httpforever.com") == "httpforever.com", "Default name falls back to the host")
        let devicesFile = directory.appending(path: "devices.json")
        let devices = DeviceStore(fileURL: devicesFile)
        let studio = URL(string: "http://studio.local:8888/")!
        check(devices.label(for: studio) == "studio:8888", "Label without a known IP")
        devices.record(address: "10.0.2.2", for: "studio.local")
        check(devices.label(for: studio) == "studio:8888 · 10.0.2.2:8888", "Label shows name, port, and IP")
        check(devices.label(for: URL(string: "http://studio.local:32400/web")!) == "studio:32400/web · 10.0.2.2:32400", "Label keeps the path")
        check(devices.rename("STUDIO.local", to: "  Desk PC "), "Rename device")
        check(devices.label(for: studio) == "Desk PC:8888 · 10.0.2.2:8888", "Custom name is shared across host spellings")
        devices.record(address: "10.0.2.9", for: "studio.local")
        let reloaded = DeviceStore(fileURL: devicesFile)
        check(reloaded.label(for: studio) == "Desk PC:8888 · 10.0.2.9:8888", "Name survives an IP change and relaunch")
        check(reloaded.rename("studio.local", to: "") && reloaded.customName(for: "studio.local") == nil, "Empty name restores the default")
        check(reloaded.rename("studio.local", to: "studio") && reloaded.customName(for: "studio.local") == nil, "Default name is not stored as custom")
        reloaded.record(address: "10.0.0.232", for: "10.0.0.232")
        check(reloaded.label(for: URL(string: "http://10.0.0.232/")!) == "10.0.0.232:80", "IP bookmarks don’t repeat the IP")
        reloaded.record(hostname: "brothera1b2c3d4.localdomain", for: "10.0.0.232")
        check(reloaded.label(for: URL(string: "http://10.0.0.232/")!) == "brothera1b2c3d4:80", "IP bookmark shows reverse-lookup name")
        check(reloaded.label(for: URL(string: "http://nas.local/")!, address: "10.0.0.5") == "nas:80 · 10.0.0.5:80", "Discovery address is used when none is stored")

        check(reloaded.label(for: URL(string: "http://nas.local:80/")!) == "nas:80", "Explicit default HTTP port stays visible")
        check(reloaded.label(for: URL(string: "https://nas.local/")!) == "nas:443", "Implicit HTTPS port stays visible")
        check(reloaded.label(for: URL(string: "http://[fd00::1]/")!) == "[fd00::1]:80", "IPv6 labels bracket the address")
        check(reloaded.label(for: URL(string: "http://nas.local:8888/")!, address: "fd00::2") == "nas:8888 · [fd00::2]:8888", "IPv6 fallback includes the port")

        check(!TabPolicy.opensNewTab(currentTabIsBlank: true, preference: .newTab), "A blank tab is filled, not left behind")
        check(TabPolicy.opensNewTab(currentTabIsBlank: false, preference: .newTab), "New Tab preference opens a tab")
        check(!TabPolicy.opensNewTab(currentTabIsBlank: false, preference: .currentTab), "Current Tab preference replaces the page")
        let tabStore = TabStore(fileURL: directory.appending(path: "tabs.json"))
        check(tabStore.load() == nil, "No saved tabs on first launch")
        let savedTabs = SavedTabs(tabs: [
            SavedTab(id: UUID(), url: "http://studio.local:8888/", title: "Grafana", state: Data([1, 2, 3])),
            SavedTab(id: UUID(), url: nil, title: "", state: nil)
        ], selected: 7)
        tabStore.save(savedTabs)
        let loadedTabs = tabStore.load()
        check(loadedTabs?.tabs == savedTabs.tabs, "Tabs and their history survive relaunch")
        check(loadedTabs?.selected == 1, "Selected tab index is clamped")
        tabStore.clear()
        check(tabStore.load() == nil, "Clearing removes saved tabs")
        try Data("{".utf8).write(to: tabStore.fileURL)
        check(tabStore.load() == nil, "Damaged tab file starts fresh")

        let cache = DiscoveryCache(fileURL: directory.appending(path: "discovered.json"))
        check(cache.load() == nil, "No discovery cache before the first scan")
        let scan = DiscoveryScan(date: Date(timeIntervalSince1970: 1_800_000_000), network: "en0|10.0.0.1", services: [nas, printerIPP])
        cache.save(scan)
        check(cache.load() == scan, "Last scan survives relaunch")
        var trimmed = scan
        trimmed.services.removeAll { $0.id == nas.id }
        cache.save(trimmed)
        check(cache.load()?.services == [printerIPP], "Removing one result is saved")
        cache.clear()
        check(cache.load() == nil, "Clear Results deletes the cache")

        check(PortScanPreset.off.ports.isEmpty && PortScanPreset.standard.ports == [80, 443], "Off and Standard port lists")
        check(PortScanPreset.common.ports.count == 22 && Set(PortScanPreset.common.ports).count == 22 && PortScanPreset.common.ports.contains(32400), "Common list has 22 distinct ports")
        let lan = IPv4Range(cidr: "10.0.2.183/22")!
        check(lan.cidr == "10.0.0.0/22" && lan.count == 1022 && lan.description == "10.0.0.1 – 10.0.3.254", "Parse a /22 from any address in it")
        let lanHosts = lan.hosts(excluding: "10.0.2.183")
        check(lanHosts.count == 1021 && lanHosts.first == "10.0.0.1" && lanHosts.last == "10.0.3.254" && !lanHosts.contains("10.0.2.183"), "Hosts skip network, broadcast and the phone")
        check(IPv4Range.scanRange(network: "10.0.0.0/22", deviceIP: "10.0.2.183") == lan, "Networks up to 1,024 addresses are scanned whole")
        check(IPv4Range.scanRange(network: "172.16.0.0/16", deviceIP: "172.16.9.40")?.cidr == "172.16.9.0/24", "Large networks fall back to the phone’s /24")
        check(IPv4Range(cidr: "10.0.0.1/32")?.hosts().isEmpty == true && IPv4Range(cidr: "nonsense") == nil && IPv4Range(cidr: "10.0.0.256/24") == nil, "Reject unusable ranges")
        let plan = PortScanPlan(preset: .common, range: lan, deviceIP: "10.0.2.183")
        check(plan.addressCount == 1021 && plan.connectionCount == 22462, "Plan counts every selected port on every address")
        let targets = plan.targets
        check(targets.count == plan.connectionCount && Set(targets.map { ServiceCatalog.endpointKey(host: $0.host, port: $0.port) }).count == targets.count, "Every scan endpoint is checked exactly once")
        check(lanHosts.allSatisfy { host in Set(targets.filter { $0.host == host }.map(\.port)) == Set(PortScanPreset.common.ports) }, "Every host receives every preset port without a liveness prerequisite")
        check(targets.contains { $0.host == "10.0.3.46" && $0.port == 8888 }, "A service on 8888 is checked without responses from 80 or 443")
        check(targets.allSatisfy { $0.host != plan.deviceIP && lanHosts.contains($0.host) }, "Targets stay in the confirmed range and skip this device")
        let standardPlan = PortScanPlan(preset: .standard, range: lan, deviceIP: plan.deviceIP)
        check(standardPlan.connectionCount == 2042 && standardPlan.targets.allSatisfy { [80, 443].contains($0.port) }, "Standard scans only its selected ports on every host")
        check(PortScanPlan(preset: .off, range: lan, deviceIP: plan.deviceIP).targets.isEmpty, "Off has no scan targets")
        check(plan.needsConfirmation(confirmedCount: nil) && !plan.needsConfirmation(confirmedCount: 1021) && !plan.needsConfirmation(confirmedCount: 4000) && plan.needsConfirmation(confirmedCount: 253), "Confirm again only for a larger network")
        check(PortScan.prefersHTTPS(port: 9443) && !PortScan.prefersHTTPS(port: 9000), "HTTPS-first ports")
        check(DiagnosticsText.htmlTitle(in: "HTTP/1.1 200 OK\r\n\r\n<html><head><TITLE lang=en>\n  Portainer &amp; Co\n</TITLE>") == "Portainer & Co", "Page title, any case, entities decoded")
        check(DiagnosticsText.htmlTitle(in: "<html><title></title>") == nil && DiagnosticsText.htmlTitle(in: "no html") == nil, "Missing title")
        let scannedPrinter = DiscoveredService(name: "Brother Admin", type: "_http._tcp", url: URL(string: "http://10.0.0.232/")!, foundBy: .portScan)
        let scannedGrafana = DiscoveredService(name: "Grafana", type: "_http._tcp", url: URL(string: "http://10.0.3.46:3000/")!, foundBy: .portScan)
        check(ServiceCatalog.mergedWithScan(bonjour: [brother], scanned: [scannedPrinter, scannedGrafana]) == [brother, scannedGrafana], "Bonjour wins over the same address and port")
        func finding(_ url: String, _ status: Int, title: String? = nil, server: String? = nil, location: String? = nil) -> WebFinding {
            let parsed = URL(string: url)!
            return WebFinding(host: parsed.host!, port: ServiceCatalog.port(of: parsed), url: parsed, status: status, title: title, server: server, location: location)
        }
        let unifiRedirect = finding("http://10.0.0.1/", 301, title: "301 Moved Permanently", location: "https://10.0.0.1/")
        let unifi = finding("https://10.0.0.1/", 200, title: "UniFi OS")
        let badRequest = finding("http://10.0.0.1:8080/", 400, title: "HTTP Status 400 – Bad Request")
        let loginRedirect = finding("http://10.0.0.5/", 302, server: "gSOAP/2.8", location: "/login.html")
        let lighttpdHTTP = finding("http://10.0.2.202/", 200, server: "lighttpd/1.4.54")
        let lighttpdHTTPS = finding("https://10.0.2.202/", 200, server: "lighttpd/1.4.54")
        let collapsed = PortScan.collapse([unifiRedirect, unifi, badRequest, loginRedirect, lighttpdHTTP, lighttpdHTTPS])
        check(collapsed == [unifi, loginRedirect, lighttpdHTTPS], "Drop 400s, redirects to found pages, and HTTP copies of HTTPS pages")
        check(PortScan.collapse([unifiRedirect]) == [unifiRedirect], "A redirect to a page that wasn’t found is kept")
        check(PortScan.name(for: unifi, deviceName: "unifi") == "UniFi OS", "Page title names the row")
        check(PortScan.name(for: loginRedirect, deviceName: "camera") == "camera:80", "Redirects use the device name, not the placeholder title")
        check(PortScan.name(for: finding("http://10.0.3.46:3000/", 200), deviceName: "studio") == "studio:3000", "Device name keeps a non-web port")
        check(PortScan.name(for: lighttpdHTTPS, deviceName: nil) == "lighttpd/1.4.54", "Server software when nothing better")
        check(PortScan.name(for: finding("http://10.0.3.166/", 200), deviceName: nil) == "Web app on port 80", "Port as the last resort")
        check(HTTPStatus.line(404) == "404 Not Found" && HTTPStatus.line(503) == "503 Service Unavailable" && HTTPStatus.line(599) == "599", "Status lines use standard phrases, or just the code")
        let notFound = PageResponse(method: "GET", url: "http://studio.local:8888/missing", statusCode: 404,
                                    headers: [ResponseHeader(name: "Content-Length", value: "0"), ResponseHeader(name: "Server", value: "nginx/1.25")])
        check(notFound.isError && notFound.header("server") == "nginx/1.25", "Response header lookup ignores case")
        check(notFound.report == "GET http://studio.local:8888/missing\nStatus: 404 Not Found\n\nContent-Length: 0\nServer: nginx/1.25", "Response report is verbatim")
        check(notFound.summary == "GET http://studio.local:8888/missing\nContent-Length: 0\nServer: nginx/1.25", "Error summary lists request and key headers")
        check(ErrorText.details(domain: "NSURLErrorDomain", code: -1004, url: "http://10.0.0.5:81/", underlying: (domain: "kCFErrorDomainCFNetwork", code: -1004))
              == "Error: NSURLErrorDomain -1004\nUnderlying: kCFErrorDomainCFNetwork -1004\nURL: http://10.0.0.5:81/", "Load errors show exact domain, code and URL")
        check(BlockedPorts.message(for: URL(string: "http://nas.local:22/")!)?.contains("port 22") == true, "SSH port is explained, not left blank")
        check(BlockedPorts.message(for: URL(string: "http://nas.local:8080/")!) == nil && BlockedPorts.message(for: URL(string: "http://nas.local/")!) == nil, "Web ports load normally")
        let oldCache = Data(#"{"name":"NAS","type":"_http._tcp","url":"http://nas.local/"}"#.utf8)
        check((try? JSONDecoder().decode(DiscoveredService.self, from: oldCache))?.foundBy == nil, "Scans saved before port scanning still load")
        print("Passed \(count) core checks (address parsing, bookmark persistence, discovery, diagnostics, device names, tabs, and port scan).")
    }
}
