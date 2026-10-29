# LAN Browser

[![CI](https://github.com/jessegoodier/lan-browser/actions/workflows/ci.yml/badge.svg)](https://github.com/jessegoodier/lan-browser/actions/workflows/ci.yml) [![CodeQL](https://github.com/jessegoodier/lan-browser/actions/workflows/codeql.yml/badge.svg)](https://github.com/jessegoodier/lan-browser/actions/workflows/codeql.yml) [![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/jessegoodier/lan-browser/badge)](https://scorecard.dev/viewer/?uri=github.com/jessegoodier/lan-browser) [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A small iPhone and iPad browser with tabs for home services and captive-portal Wi-Fi. Built with SwiftUI and WebKit, it requires iOS or iPadOS 17.0 or later and has no dependencies. The iPad app also runs on Apple silicon Macs.

LAN Browser is free and will never have paid features, subscriptions, or ads. It’s built for the community of home-networking enthusiasts who run their own servers, routers and smart-home devices.

Plain HTTP is the point. Home servers often have no certificate, and hotel, cafe, train, and airport networks can only show their sign-in page by intercepting an HTTP request. HTTPS sites turn that interception into a certificate warning. [HTTP Forever](http://httpforever.com/) is a public plain-HTTP page made for that captive-portal case.

LAN Browser is intended exclusively for use on trusted home networks. It isn’t meant for browsing websites that are expected to be secure, such as banking, email or shopping. To reach home devices it loads plain HTTP pages and opens devices even when their certificates aren’t trusted, so when you’re on a network you don’t trust, use Safari. The first launch shows a “For Trusted Home Networks” notice that stays until you tap **I Understand**; the same text is at the top of **Settings › Help & Support › Using LAN Browser**.

## What is included

- Bookmarks start page on fresh launch and in new tabs, seeded with **HTTP Forever Captive Portal — http://httpforever.com/**. Use it to reach a Wi-Fi sign-in page, then add your own LAN bookmarks.
- Bottom address bar on iPhone and in narrow iPad windows, or a top bar at full width on iPad and Mac (see [iPad and Mac](#ipad-and-mac)). Omitted schemes default to HTTP. Explicit HTTPS and server redirects work normally.
- Back, Forward, Reload/Stop, swipe navigation, loading state, and retryable errors.
- Add, edit, delete, and reorder bookmarks, stored on the device.
- Persistent website cookies and storage. No browsing-history database, apart from the open tabs saved for Restore Tabs on Launch.
- Downloads through WebKit followed by **Save to Files**, with a destination choice for each file. Files are temporarily staged in the app and cleaned up after export or cancellation.
- System appearance, accessible control labels, and portrait/landscape layouts.

The **Bookmarks** (book) button opens the bookmark list; while it is showing, the globe button returns to the current page. Swipe right on a bookmark or long-press it to edit; the long-press menu also has **Rename Device…**. Swipe left to delete, or tap **Edit** to delete or reorder.

## iPad and Mac

On iPad, and on a Mac, a window at full width shows a Safari-style top bar instead of the bottom toolbar. Back and Forward are on the left, the address field is in the middle, and Reload, Page Info, Bookmarks and Tabs are on the right. In Split View, Slide Over and other narrow windows, the bottom toolbar and address sheet return, as on iPhone.

With a hardware keyboard, these shortcuts work on iPad and on a Mac:

- **⌘L** Open Location
- **⌘T** New Tab
- **⌘W** Close Tab
- **⌘R** Reload
- **⌘.** Stop
- **⌘[** Back
- **⌘]** Forward
- **⌘D** Add Bookmark
- **⌘⇧\\** Show All Tabs
- **⌘,** Settings

The iPad app runs on Apple silicon Macs as **My Mac (Designed for iPad)**. Intel Macs are not supported, and there is no separate Mac app.

- Local Network access is turned on in **System Settings › Privacy & Security › Local Network**. The app has no **Open Settings** button for it on a Mac.
- A Mac has no pull down gesture. Use **Scan Again** instead, in the On This Network ••• menu or in Settings.

## Tabs

Tabs work much like Safari’s. A new tab opens on the bookmark list. Tapping a bookmark or an On This Network row opens it in a new tab, or fills the current tab if that tab is blank. The default is set in **Settings › Open Bookmarks In** (New Tab or Current Tab). Long-press a bookmark for the other choice, **Open in New Tab** or **Open in Current Tab**. Links that open a new window (`target="_blank"` or `window.open`) open a new tab.

The **Tabs** button opens the tab switcher: a grid of page thumbnails with ✕ to close a tab, **New Tab**, and **Done**. Long-press the Tabs button for **New Tab** and **Close Tab**. Closing the last tab leaves one blank tab.

With **Restore Tabs on Launch** on (the default), open tabs are saved on the device in `tabs.json` in Application Support, with each tab’s address, title, and Back/Forward history, and restored at launch. A restored tab loads only when you switch to it. Turning the setting off deletes the file, and so does **Clear Cookies & Website Data**. Saved tabs are never sent anywhere.

## Local network features

Both features are optional and off until you turn on **Local Network Features**. Use the card at the top of the bookmark list (“Find devices on this network”) or the switch in **Settings**. Turning it on triggers the Local Network permission prompt. While the switch is off, the app does not browse the network.

- **On This Network** is a list, below your bookmarks, of web apps advertised with Bonjour (mDNS) on your network. Web apps you’ve already bookmarked are left out. A match needs the same port and the same host name or IP, so a printer saved as `10.0.0.232` doesn’t appear again as `brotherA1B2C3D4.local`, while a second app on another port of a bookmarked device is still listed. Tapping **+** moves an app out of this list and into your bookmarks. The app scans once automatically the first time **Local Network Features** is turned on. After that it scans only when you ask: **Scan Again** in the section’s ••• menu or in Settings, or pull down on the bookmark list (on a Mac, use Scan Again). A scan stops on its own once results settle (about two seconds with nothing new, and at most about ten seconds). While it runs, new rows are added at the end so nothing moves under your finger; when it finishes, the list is sorted by name. The last scan is saved on the device and shown until you scan again or clear it. The section shows when it was scanned. If you have moved to a different network since, a note says so, but the app does not rescan by itself. Clear the list with **Clear Results** in the ••• menu or **Clear Discovered Services** in Settings, or swipe left on a row (or long-press it and choose **Remove from List**) to remove one row until the next scan. Each row has a status dot (green, red, or grey) from the same TCP checks used for bookmarks. Tap **+** to copy an entry into your bookmarks. It browses generic web servers (`_http._tcp`, `_https._tcp`), Home Assistant, Plex, network printers (IPP/IPPS admin pages), OctoPrint, ESPHome, and WLED.
- **Bookmark status dots** show whether each bookmark’s host and port accept a TCP connection. Green means the connection succeeded within 3 seconds. Red means it was refused, timed out, or the name did not resolve. Grey means a check is running. With the feature off, no dots are shown. Checks run when the bookmark list appears, on pull-to-refresh, and when the network changes. There is no background polling. Checks contact only the addresses you saved, including public ones such as httpforever.com.
- **Device names** replace the raw URL on bookmark and On This Network rows. A row shows the friendly name, then any non-default port and path, then the most recently seen IP, such as “studio:8888 · 10.0.2.2”. The default name is the host name without local suffixes (`.local`, `.localdomain`, `.lan`, `.home.arpa`, `.home`, `.internal`), so `studio.local` shows as “studio”. A bookmark saved by IP takes its name from a reverse DNS lookup when one answers, otherwise from the IP. Rename a device in the **Device** section at the top of Page Info (ⓘ), or long-press a bookmark or On This Network row and choose **Rename Device…**. Leaving the name empty restores the default. One name applies to every bookmark on that host. A name is tied to the host name, so it follows the device when its IP changes. Bookmarks saved by IP are keyed by that IP instead. iOS does not let apps read MAC addresses, so names cannot be tied to hardware. IPs and reverse-lookup names are learned only while **Local Network Features** is on, from discovery, the port scan, bookmark status checks, and when Page Info opens. With the feature off, rows show only the name, port, and path.
- **Tap +** on an On This Network row saves the device’s Bonjour host name URL, such as `http://studio.local:8888/`, rather than its IP, so the bookmark keeps working when the router assigns a new IP. If the host name cannot be resolved, the IP is used instead.
- **Port Scan** finds web apps that don’t advertise with Bonjour. It is in **Settings › Local Network**, shown when **Local Network Features** is on, with three choices: **Off** (Bonjour only, the default), **Standard Web** (ports 80 and 443), and **Common Web Apps** (22 ports: 80 81 443 1880 3000 3001 5000 5001 7878 8000 8008 8080 8081 8096 8123 8443 8888 8989 9000 9090 9443 32400). Nothing is port-scanned until you confirm. Picking Standard Web or Common Web Apps opens a sheet, “Scan Ports on This Network?”, that shows the address range and count (for example, 10.0.0.1 – 10.0.3.254, 1,021 addresses, with this device’s own address skipped), every port, roughly how many connections the scan makes, and that it runs only when you tap **Scan Again** or pull down. The choice is saved only when you tap **Confirm**, and **Cancel** leaves it unchanged. Choosing **Off** takes effect immediately. The range is this device’s whole IPv4 network when it has at most 1,024 addresses, and otherwise only the 254 addresses around the device. The port scan runs only as part of a scan you start, with **Scan Again** in the On This Network ••• menu or in Settings, or a pull down on the bookmark list. It never runs on its own or as part of the automatic first scan. A scan first tries ports 80 and 443 on each address to find devices that are on (a device that is on answers even when a port is closed), then tries the chosen ports on those devices and on Bonjour finds. Progress shows “Checking addresses · 312 of 2,042”, “Checking ports…”, or “Reading pages…”, with a **Cancel** button that keeps the previous results. A scan of a network of about 1,000 addresses typically takes 10–30 seconds.
- **Port scan results** merge into On This Network. Rows found only by the port scan carry a small “port scan” tag. Tapping **+** on one saves its IP address URL, such as `https://10.0.0.1/`, because the port scan has no Bonjour host name to save. HTTPS pages are read even with self-signed certificates, and page reading follows redirects (up to 5). Opening one shows an untrusted certificate with a red “!” (see [Errors are shown in full](#errors-are-shown-in-full)). A row is titled with the title of the page the redirects end on, otherwise the device’s network name from a reverse DNS lookup (for example, “nest-audio:8008”), otherwise the server software, otherwise “Web app on port N”. If Bonjour found the same address and port, the Bonjour row is shown instead. Redirect-only answers to another found page, “400 Bad Request” answers, and HTTP copies of an identical HTTPS page are left out. Bookmarked host-or-IP and port stay hidden. The section’s scan line shows what the last scan covered, such as “Scanned 5 minutes ago · 5:23 PM · Bonjour + 22 ports”. If this device later joins a network with more addresses than the one you confirmed, a scan runs Bonjour only, and the section shows “The port scan needs confirming for this network.” with a **Review** button that opens the same sheet.

Discovery and the port scan run only when you ask, plus one automatic Bonjour scan the first time the feature is turned on. Status checks run only while the bookmark list is open and the app is in the foreground. Discovery uses local multicast only, and the port scan connects only to addresses on your own network. Both stay on your network. Nothing from discovery, the port scan, status checks, or diagnostics is sent to the developer or any third party.

## Errors are shown in full

- **Any main-page response other than 200** makes the response the first line of the page: a strip above the page content (never covering it) with the status (for example `HTTP 404 Not Found`) and the exact method and URL, so a blank error page is never silent. If the error response can’t be displayed as a page (for example a 404 sent as `application/octet-stream`), it is never saved as a download; the error screen is headed with the status and lists the request, Content-Type, Content-Length and Server, with **Response Details**. **Details** lists the status and every response header as received, with **Copy Response Details**; **Diagnose** opens the connection checks. Page Info also has a **Response** section. The status code is exactly what the server sent; WebKit doesn’t pass on the server’s own reason phrase (HTTP/2 has none), so the phrase is the standard one for that code. iOS may normalize header names and doesn’t keep their order, so headers are sorted by name.
- **A page that fails to load** shows the system’s message plus the exact error domain and code, any underlying error, and the failing URL (for example `NSURLErrorDomain -1004`, `kCFErrorDomainCFNetwork -1004`, `http://127.0.0.1:8899/`). The text can be selected and copied.
- **Ports browsers refuse to load** (the Fetch standard’s blocked ports, such as 22, 25, 548 and 554) are explained instead of leaving a blank page; WebKit drops these without reporting an error.
- **Untrusted certificates on local addresses** open anyway. When an HTTPS page on a local-network address (private IPv4 such as 10.x, 172.16–31.x or 192.168.x, link-local, `.local` names, single-word host names, or localhost) has a certificate iOS can’t verify (self-signed, expired, or wrong name), the first line of the page is a strip with a red “!” reading “Certificate not trusted” and the host. Tap it to see the system’s exact trust error and error code, and for each certificate in the chain its subject, common name, valid from and until (iOS 18 and later), key type and size, serial number and SHA-256 fingerprint. **Copy Certificate Details** copies them. Page Info’s Connection section says “Encrypted (HTTPS), but the certificate isn’t trusted” and has **Show Certificate**. **Internet sites with invalid certificates are still rejected** with the system’s normal error.

## Connection diagnostics

**Why can’t I connect?** checks each step in order, and each failure shows plain-language advice. The steps are **Network** (Wi-Fi, cellular, or none, and the device IP), **Local Network Access** (for local addresses only), **Name Lookup** (what the name resolves to through iOS’s DNS resolver), **Port** (TCP connect, refused or timed out), and **Web Server** (a single GET over a raw connection: status code, server header, and for HTTPS whether the certificate is trusted). Web Server follows redirects (up to 5, relative or absolute `Location`, with the query kept; 304 isn’t a redirect) and lists every hop, such as “HTTP 301 Moved Permanently → https://10.0.0.1/”, then the final response. It warns if the chain stopped after 5 redirects, which usually means a loop. Its advice for an untrusted certificate says that local addresses open anyway and suggests comparing the fingerprint with the device. Later steps are skipped after a failure.

Open it from the Page Info (ⓘ) sheet, the **Diagnose** button next to **Retry** on the “Page unavailable” screen, or **Check Connection** in a bookmark’s long-press menu. It runs only when you ask. It does not need the Local Network Features switch, although checking a local address may trigger the iOS permission prompt. **Copy Report** copies a text summary for support requests.

## Settings

Open **Settings** (the gear button on the bookmark screen). It has four groups: **Browsing** (**Open Bookmarks In** and **Restore Tabs on Launch**); **Local Network** (the **Local Network Features** switch, **Port Scan** (shown while the switch is on), **Scan Again**, **Clear Discovered Services**, and **Reset Device Names**, which asks for confirmation and forgets custom names, remembered IPs, and looked-up host names but keeps bookmarks); **Privacy** (**Clear Cookies & Website Data** and the bundled offline **Privacy Policy**); and **Help & Support** (the **Using LAN Browser** help page, **Run Browser Check**, **Ask for Help or Report a Problem** on GitHub Issues, and the app version). The browser check renders locally and offers a sample Save to Files download without a LAN server or internet connection.

## Building from source

Requirements: Xcode with the iOS 17 SDK or later. There are no dependencies to install.

1. Open `LANBrowser.xcodeproj` in Xcode and select the **LANBrowser** scheme.
2. Select the **LANBrowser** target, open **Signing & Capabilities**, and choose your own **Team**.
3. Change the bundle identifier, which is set to **com.jesse.lanbrowser**, to one you control, such as **com.yourname.lanbrowser**.
4. Choose an iPhone or iPad simulator, a connected iPhone or iPad, or **My Mac (Designed for iPad)** as the run destination, and press **⌘R**. Installing directly on an iPhone or iPad requires Developer Mode (**Settings › Privacy & Security › Developer Mode**).

To build for the simulator without a signing team:

```sh
xcodebuild -project LANBrowser.xcodeproj -scheme LANBrowser \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO build
```

Unsigned builds can’t be installed on an iPhone, iPad or Mac, or uploaded to TestFlight. Those need a signing team.

## Troubleshooting

### If a home service does not load

- Open **Why can’t I connect?** from the Page Info (ⓘ) sheet, the **Diagnose** button next to **Retry** on the “Page unavailable” screen, or **Check Connection** in a bookmark’s long-press menu. It reports which step fails.
- If it reports Local Network permission denied, open **Settings › Privacy & Security › Local Network › LAN Browser** and turn it on. On a Mac, open **System Settings › Privacy & Security › Local Network** and turn on LAN Browser.
- Try the exact address in Safari on the same device. The app uses iOS’s normal DNS resolver and does not invent an IP address for a hostname. **On This Network** shows the services found by your last scan on the current network; use **Scan Again** to refresh it.
- If Safari also fails, try **http://YOUR_SERVER_LAN_IP:PORT/**. If the IP works, fix your home DNS or edit the bookmark to use the IP. A `.local` address is another option only if that machine actually advertises one.
- Ensure the service listens on the LAN interface rather than only `127.0.0.1`, its firewall permits the port, and the device is not on an isolated guest Wi-Fi network.
- The ATS settings allow HTTP inside the browser. They do not repair DNS or bypass server authentication. A local device with an untrusted certificate still opens, marked with a red “!” (see [Errors are shown in full](#errors-are-shown-in-full)), but internet sites with invalid certificates are rejected.

### If a captive portal does not appear

- Stay on **http://httpforever.com/**. Opening an HTTPS site usually produces a certificate warning instead of the login page, and that warning should not be bypassed.
- Join the Wi-Fi network again, then reload HTTP Forever. Some portals only intercept the first plain-HTTP request after association.

## Testing

`Scripts/check.sh` compiles the Foundation-only logic for macOS and runs its checks: address parsing, bookmarks, Bonjour service mapping, diagnostic parsing, device names, saved tabs, the discovery cache, and port-scan logic. It also lints the property lists and the Xcode project file. It does not launch WebKit, so it doesn’t replace on-device testing.

```sh
Scripts/check.sh
```

Manual on-device checks and the local test fixture are described in [docs/TESTING.md](docs/TESTING.md).

## Privacy and implementation notes

The app has no analytics, advertising, cloud backend, or app-account system. Browsed websites make their own normal network requests. Bookmarks live in Application Support, alongside `devices.json` (custom device names, last-seen IPs, and reverse-lookup names), `discovered.json` (the last On This Network scan), and `tabs.json` (open tabs, while Restore Tabs on Launch is on). None of it is sent to the developer or anyone else. Website data is managed by WebKit. Download staging files live in the temporary directory and are removed after saving/cancellation or the next launch after an interrupted session.

`NSAllowsLocalNetworking` supports local hostnames/IPs. `NSAllowsArbitraryLoadsInWebContent` permits HTTP navigation and resources within WebKit, including redirects to other hostnames, without globally disabling ATS for unrelated app networking. Apple documents [local networking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking), [web-content HTTP exceptions](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloadsinwebcontent), and the [WebKit exception to local-network permission](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy). Local network discovery and the port scan are opt-in. With **Local Network Features** on, the app browses Bonjour services when you scan and makes TCP connections to saved bookmarks and discovered devices. The port scan connects only to addresses on your own network, and only after you confirm it and start a scan. Connection diagnostics make DNS, TCP, and HTTP requests to the address you check, only when you run them. Without the switch, the app does not browse the network. WebKit page loads are exempt from the iOS Local Network prompt; the native features above trigger it. Invalid HTTPS certificates are accepted only for local-network addresses, in the server-trust challenge of `BrowserTab`; each such override is recorded and shown with the red “!”. Internet sites keep normal certificate validation.

The encryption declaration reflects use of Apple’s built-in HTTPS support with no custom encryption. Revisit it if custom cryptography is added. The privacy manifest declares no tracking and no app-collected data. Its only required-reason API is UserDefaults (reason `CA92.1`), which stores the Local Network Features switch, whether its card was dismissed, the Settings choices (Port Scan, Open Bookmarks In, and Restore Tabs on Launch), and whether the first-use notice was accepted (`trustedNetworkNoticeAccepted`).

Foreground downloads only: keep the app open while downloading. Resuming downloads after termination, background transfers, and bookmark sync are outside this version.

## Security

Report vulnerabilities privately, as described in [SECURITY.md](SECURITY.md), rather than in a public issue. CodeQL, OpenSSF Scorecard and zizmor check the code and the GitHub Actions workflows, Dependabot keeps the pinned actions current, and every action is pinned to a full commit SHA.

## Support

For help, see [SUPPORT.md](SUPPORT.md). The [privacy policy](LANBrowser/privacy_policy.md) is also bundled with the app and shown offline in **Settings**.

## Contributing

Issues and pull requests are welcome; see [AGENTS.md](AGENTS.md) for project layout and conventions. Pull requests use a checklist (`.github/pull_request_template.md`) covering `Scripts/check.sh`, the simulator build, and the privacy and networking rules. CI must pass.

## License

LAN Browser is released under the [MIT License](LICENSE).

## Saved passwords

Offer to Save Passwords is on by default in Settings (the gear). Each supported login-form submission offers Save or Not Now, including on HTTP pages and for previously saved credentials. Saving stores the username and password in this device’s Keychain, separated by scheme, host, port and username; saving again updates that entry. Passwords are available only while the device is unlocked and aren’t synced to iCloud or migrated to another device. Settings > Saved Passwords lets you reveal, copy and delete them. AutoFill Saved Passwords is also on by default and can be turned off separately in Settings. It fills supported main-page login forms for the exact saved scheme, host and port, including HTTP pages, without submitting the form. An entered username selects its matching account; an empty form uses the most recently saved account. Existing password text is preserved. Filled credentials are available to that website’s scripts before you submit.  Turning offers off and clearing website data keep saved passwords. Keychain entries may survive app deletion, so delete saved passwords before uninstalling. Embedded sign-in frames, HTTP authentication dialogs and some custom forms aren’t supported. Saving a password does not encrypt HTTP traffic.
