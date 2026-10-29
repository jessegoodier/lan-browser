# LAN Browser

A small iPhone browser with tabs for home services and captive-portal Wi-Fi. Built with SwiftUI and WebKit; requires iOS 17.0 or later. Intended for iPhone 17 Pro on iOS 27.0.1. The project uses the installed Xcode 27.1 and has no dependencies to install.

Plain HTTP is the point. Home servers often have no certificate, and hotel, cafe, train, and airport networks can only show their sign-in page by intercepting an HTTP request. HTTPS sites turn that interception into a certificate warning. [HTTP Forever](http://httpforever.com/) is a public plain-HTTP page made for that captive-portal case.

LAN Browser is intended exclusively for use on trusted home networks. It isn’t meant for browsing websites that are expected to be secure, such as banking, email or shopping. To reach home devices it loads plain HTTP pages and opens devices even when their certificates aren’t trusted, so when you’re on a network you don’t trust, use Safari. The first launch shows a “For Trusted Home Networks” notice that stays until you tap **I Understand**; the same text is at the top of **Settings › Help & Support › Using LAN Browser**.

## What is included

- Bookmarks start page on fresh launch and in new tabs, seeded with **HTTP Forever Captive Portal — http://httpforever.com/**. Use it to reach a Wi-Fi sign-in page, then add your own LAN bookmarks.
- Bottom address bar; omitted schemes default to HTTP. Explicit HTTPS and server redirects work normally.
- Back, Forward, Reload/Stop, swipe navigation, loading state, and retryable errors.
- Add, edit, delete, and reorder bookmarks, stored on the device.
- Persistent website cookies and storage. No browsing-history database, apart from the open tabs saved for Restore Tabs on Launch.
- Downloads through WebKit followed by **Save to Files**, with a destination choice for each file. Files are temporarily staged in the app and cleaned up after export or cancellation.
- System appearance, accessible control labels, and portrait/landscape layouts.

The **Bookmarks** (book) button opens the bookmark list; while it is showing, the globe button returns to the current page. Swipe right on a bookmark or long-press it to edit; the long-press menu also has **Rename Device…**. Swipe left to delete, or tap **Edit** to delete/reorder.

## Tabs

Tabs work much like Safari’s. A new tab opens on the bookmark list. Tapping a bookmark or an On This Network row opens it in a new tab, or fills the current tab if that tab is blank. The default is set in **Settings › Open Bookmarks In** (New Tab or Current Tab). Long-press a bookmark for the other choice, **Open in New Tab** or **Open in Current Tab**. Links that open a new window (`target="_blank"` or `window.open`) open a new tab.

The **Tabs** button opens the tab switcher: a grid of page thumbnails with ✕ to close a tab, **New Tab**, and **Done**. Long-press the Tabs button for **New Tab** and **Close Tab**. Closing the last tab leaves one blank tab.

With **Restore Tabs on Launch** on (the default), open tabs are saved on the device in `tabs.json` in Application Support, with each tab’s address, title, and Back/Forward history, and restored at launch. A restored tab loads only when you switch to it. Turning the setting off deletes the file, and so does **Clear Cookies & Website Data**. Saved tabs are never sent anywhere.

## Local network features

Both features are optional and off until you turn on **Local Network Features**. Use the card at the top of the bookmark list (“Find devices on this network”) or the switch in **Settings**. Turning it on triggers the iOS Local Network permission prompt. While the switch is off, the app does not browse the network.

- **On This Network** is a list, below your bookmarks, of web apps advertised with Bonjour (mDNS) on your network. Web apps you’ve already bookmarked are left out. A match needs the same port and the same host name or IP, so a printer saved as `10.0.0.232` doesn’t appear again as `brotherE6576F3F.local`, while a second app on another port of a bookmarked device is still listed. Tapping **+** moves an app out of this list and into your bookmarks. The app scans once automatically the first time **Local Network Features** is turned on (or the first time the bookmark list opens after updating with the feature already on). After that it scans only when you ask: **Scan Again** in the section’s ••• menu or in Settings, or pull down on the bookmark list. A scan stops on its own once results settle (about two seconds with nothing new, and at most about ten seconds). While it runs, new rows are added at the end so nothing moves under your finger; when it finishes, the list is sorted by name. The last scan is saved on the device and shown until you scan again or clear it. The section shows when it was scanned. If you have moved to a different network since, a note says so, but the app does not rescan by itself. Clear the list with **Clear Results** in the ••• menu or **Clear Discovered Services** in Settings, or swipe left on a row (or long-press it and choose **Remove from List**) to remove one row until the next scan. Each row has a status dot (green, red, or grey) from the same TCP checks used for bookmarks. Tap **+** to copy an entry into your bookmarks. It browses generic web servers (`_http._tcp`, `_https._tcp`), Home Assistant, Plex, network printers (IPP/IPPS admin pages), OctoPrint, ESPHome, and WLED.
- **Bookmark status dots** show whether each bookmark’s host and port accept a TCP connection. Green means the connection succeeded within 3 seconds. Red means it was refused, timed out, or the name did not resolve. Grey means a check is running. With the feature off, no dots are shown. Checks run when the bookmark list appears, on pull-to-refresh, and when the network changes. There is no background polling. Checks contact only the addresses you saved, including public ones such as httpforever.com.
- **Device names** replace the raw URL on bookmark and On This Network rows. A row shows the friendly name, then any non-default port and path, then the most recently seen IP, such as “omarchy:8888 · 10.0.2.2”. The default name is the host name without local suffixes (`.local`, `.localdomain`, `.lan`, `.home.arpa`, `.home`, `.internal`), so `omarchy.local` shows as “omarchy”. A bookmark saved by IP takes its name from a reverse DNS lookup when one answers, otherwise from the IP. Rename a device in the **Device** section at the top of Page Info (ⓘ), or long-press a bookmark or On This Network row and choose **Rename Device…**. Leaving the name empty restores the default. One name applies to every bookmark on that host. A name is tied to the host name, so it follows the device when its IP changes. Bookmarks saved by IP are keyed by that IP instead. iOS does not let apps read MAC addresses, so names cannot be tied to hardware. IPs and reverse-lookup names are learned only while **Local Network Features** is on, from discovery, the port scan, bookmark status checks, and when Page Info opens. With the feature off, rows show only the name, port, and path.
- **Tap +** on an On This Network row now saves the device’s Bonjour host name URL, such as `http://omarchy.local:8888/`, instead of its IP, so the bookmark keeps working when the router assigns a new IP. If the host name cannot be resolved, it falls back to the IP.
- **Port Scan** finds web apps that don’t advertise with Bonjour. It is in **Settings › Local Network**, shown when **Local Network Features** is on, with three choices: **Off** (Bonjour only, the default), **Standard Web** (ports 80 and 443), and **Common Web Apps** (22 ports: 80 81 443 1880 3000 3001 5000 5001 7878 8000 8008 8080 8081 8096 8123 8443 8888 8989 9000 9090 9443 32400). Nothing is port-scanned until you confirm. Picking Standard Web or Common Web Apps opens a sheet, “Scan Ports on This Network?”, that shows the address range and count (for example, 10.0.0.1 – 10.0.3.254, 1,021 addresses, with your iPhone’s own address skipped), every port, roughly how many connections the scan makes, and that it runs only when you tap **Scan Again** or pull down. The choice is saved only when you tap **Confirm**, and **Cancel** leaves it unchanged. Choosing **Off** takes effect immediately. The range is your iPhone’s whole IPv4 network when it has at most 1,024 addresses, and otherwise only the 254 addresses around the iPhone. The port scan runs only as part of a scan you start, with **Scan Again** in the On This Network ••• menu or in Settings, or a pull down on the bookmark list. It never runs on its own or as part of the automatic first scan. A scan first tries ports 80 and 443 on each address to find devices that are on (a device that is on answers even when a port is closed), then tries the chosen ports on those devices and on Bonjour finds. Progress shows “Checking addresses · 312 of 2,042”, “Checking ports…”, or “Reading pages…”, with a **Cancel** button that keeps the previous results. A scan of a network of about 1,000 addresses typically takes 10–30 seconds.
- **Port scan results** merge into On This Network. Rows found only by the port scan carry a small “port scan” tag. Tapping **+** on one saves its IP address URL, such as `https://10.0.0.1/`, because the port scan has no Bonjour host name to save; HTTPS pages are read even with self-signed certificates, and page reading follows redirects (up to 5). Opening one shows an untrusted certificate with a red “!” (see Errors are shown in full). A row is titled with the title of the page the redirects end on, otherwise the device’s network name from a reverse DNS lookup (for example, “nest-audio:8008”), otherwise the server software, otherwise “Web app on port N”. If Bonjour found the same address and port, the Bonjour row is shown instead. Redirect-only answers to another found page, “400 Bad Request” answers, and HTTP copies of an identical HTTPS page are left out. Bookmarked host-or-IP and port stay hidden, as before. The section’s scan line shows what the last scan covered, such as “Scanned 5 minutes ago · 5:23 PM · Bonjour + 22 ports”. If your iPhone later joins a network with more addresses than the one you confirmed, a scan runs Bonjour only, and the section shows “The port scan needs confirming for this network.” with a **Review** button that opens the same sheet.

Discovery and the port scan run only when you ask, plus one automatic Bonjour scan the first time the feature is turned on. Status checks run only while the bookmark list is open and the app is in the foreground. Discovery uses local multicast only, and the port scan connects only to addresses on your own network. Both stay on your network. Nothing from discovery, the port scan, status checks, or diagnostics is sent to the developer or any third party.

## Errors are shown in full

- **Any main-page response other than 200** makes the response the first line of the page: a strip above the page content (never covering it) with the status (for example `HTTP 404 Not Found`) and the exact method and URL, so a blank error page is never silent. If the error response can’t be displayed as a page (for example a 404 sent as `application/octet-stream`), it is never saved as a download; the error screen is headed with the status and lists the request, Content-Type, Content-Length and Server, with **Response Details**. **Details** lists the status and every response header as received, with **Copy Response Details**; **Diagnose** opens the connection checks. Page Info also has a **Response** section. The status code is exactly what the server sent; WebKit doesn’t pass on the server’s own reason phrase (HTTP/2 has none), so the phrase is the standard one for that code. iOS may normalize header names and doesn’t keep their order, so headers are sorted by name.
- **A page that fails to load** shows the system’s message plus the exact error domain and code, any underlying error, and the failing URL (for example `NSURLErrorDomain -1004`, `kCFErrorDomainCFNetwork -1004`, `http://127.0.0.1:8899/`). The text can be selected and copied.
- **Ports browsers refuse to load** (the Fetch standard’s blocked ports, such as 22, 25, 548 and 554) are explained instead of leaving a blank page; WebKit drops these without reporting an error.
- **Untrusted certificates on local addresses** open anyway. When an HTTPS page on a local-network address (private IPv4 such as 10.x, 172.16–31.x or 192.168.x, link-local, `.local` names, single-word host names, or localhost) has a certificate iOS can’t verify (self-signed, expired, or wrong name), the first line of the page is a strip with a red “!” reading “Certificate not trusted” and the host. Tap it to see the system’s exact trust error and error code, and for each certificate in the chain its subject, common name, valid from and until (iOS 18 and later), key type and size, serial number and SHA-256 fingerprint. **Copy Certificate Details** copies them. Page Info’s Connection section says “Encrypted (HTTPS), but the certificate isn’t trusted” and has **Show Certificate**. **Internet sites with invalid certificates are still rejected** with the system’s normal error.

## Connection diagnostics

**Why can’t I connect?** checks each step in order, and each failure shows plain-language advice. The steps are **Network** (Wi-Fi, cellular, or none, and the device IP), **Local Network Access** (for local addresses only), **Name Lookup** (what the name resolves to through iOS’s DNS resolver), **Port** (TCP connect, refused or timed out), and **Web Server** (a single GET over a raw connection: status code, server header, and for HTTPS whether the certificate is trusted). Web Server follows redirects (up to 5, relative or absolute `Location`, with the query kept; 304 isn’t a redirect) and lists every hop, such as “HTTP 301 Moved Permanently → https://10.0.0.1/”, then the final response. It warns if the chain stopped after 5 redirects, which usually means a loop. Its advice for an untrusted certificate says that local addresses open anyway and suggests comparing the fingerprint with the device. Later steps are skipped after a failure.

Open it from the Page Info (ⓘ) sheet, the **Diagnose** button next to **Retry** on the “Page unavailable” screen, or **Check Connection** in a bookmark’s long-press menu. It runs only when you ask. It does not need the Local Network Features switch, although checking a local address may trigger the iOS permission prompt. **Copy Report** copies a text summary for support requests.

## App Store preparation

See [App Store submission](APP_STORE_SUBMISSION.md) for listing copy, review instructions, HTTP exception justification, and release checks. [Support](SUPPORT.md) and the [privacy policy](LANBrowser/privacy_policy.md) provide the public support and policy pages once published to the repository.

Open **Settings** (the gear button on the bookmark screen). It has four groups: **Browsing** (**Open Bookmarks In** and **Restore Tabs on Launch**); **Local Network** (the **Local Network Features** switch, **Port Scan** (shown while the switch is on), **Scan Again**, **Clear Discovered Services**, and **Reset Device Names**, which asks for confirmation and forgets custom names, remembered IPs, and looked-up host names but keeps bookmarks); **Privacy** (**Clear Cookies & Website Data** and the bundled offline **Privacy Policy**); and **Help & Support** (the **Using LAN Browser** help page, **Run Browser Check**, **Ask for Help or Report a Problem** on GitHub Issues, and the app version). The browser check renders locally and offers a sample Save to Files download without a LAN server or internet connection.

## 1. Run it on your iPhone first

1. Open **LANBrowser.xcodeproj** in Xcode. Select the **LANBrowser** scheme if necessary.
2. Open **Xcode > Settings > Accounts** and add the Apple Account associated with your paid developer membership.
3. In the project navigator, select the blue project icon, select the **LANBrowser** target, and open **Signing & Capabilities**.
4. Leave **Automatically manage signing** enabled. Select your paid developer **Team**.
5. The initial bundle identifier is **com.jesse.lanbrowser**. If it is unavailable, replace it with a unique identifier you control, for example **com.yourname.lanbrowser**. Keep the same identifier for the App Store Connect record and all later uploads.
6. Connect your unlocked iPhone to your Mac using a data-capable USB cable. Accept **Trust This Computer** on the phone and any pairing prompts in Xcode.
7. If requested, enable **Settings > Privacy & Security > Developer Mode** on the iPhone, restart, and confirm enabling it. This is for direct Xcode installation; TestFlight installation does not require it.
8. Select your iPhone in the run destination menu next to the scheme. If it is missing, open **Window > Devices and Simulators** and finish pairing/device preparation. Install an iOS platform component in Xcode Settings if Xcode requests it.
9. Press **⌘R**. Xcode will sign, install, and launch LAN Browser. Resolve any signing issue shown in Signing & Capabilities before continuing.
10. Connect the phone to your home Wi-Fi. Tap **HTTP Forever Captive Portal** and confirm [http://httpforever.com/](http://httpforever.com/) loads. On a network that requires sign-in, that same bookmark should be replaced by the captive-portal login page.

You can subsequently launch the installed app from its Home Screen icon without the USB cable. On later fresh launches it opens bookmarks; returning to the app from the background keeps the page.

### If a home service does not load

- Open **Why can’t I connect?** from the Page Info (ⓘ) sheet, the **Diagnose** button next to **Retry** on the “Page unavailable” screen, or **Check Connection** in a bookmark’s long-press menu. It reports which step fails.
- If it reports Local Network permission denied, open **Settings › Privacy & Security › Local Network › LAN Browser** and turn it on.
- Try the exact address in Safari on the same iPhone. The app uses iOS’s normal DNS resolver and does not invent an IP address for a hostname. **On This Network** shows the services found by your last scan on the current network; use **Scan Again** to refresh it.
- If Safari also fails, try **http://YOUR_SERVER_LAN_IP:PORT/**. If the IP works, fix your home DNS or edit the bookmark to use the IP. A `.local` address is another option only if that machine actually advertises one.
- Ensure the service listens on the LAN interface rather than only `127.0.0.1`, its firewall permits the port, and the phone is not on an isolated guest Wi-Fi network.
- The ATS settings allow HTTP inside the browser. They do not repair DNS or bypass server authentication. A local device with an untrusted certificate still opens, marked with a red “!” (see Errors are shown in full), but internet sites with invalid certificates are rejected.

### If a captive portal does not appear

- Stay on **http://httpforever.com/**. Opening an HTTPS site usually produces a certificate warning instead of the login page, and that warning should not be bypassed.
- Join the Wi-Fi network again, then reload HTTP Forever. Some portals only intercept the first plain-HTTP request after association.

## 2. Install through your personal TestFlight group

Do this after the direct device test succeeds. Your own account can be an internal tester; no public invitation or external beta review is needed for this route.

1. Open [App Store Connect](https://appstoreconnect.apple.com/), sign in, and choose **My Apps > + > New App**.
2. Select **iOS**, choose a primary language, and enter **LAN Browser** as the name. If that App Store Connect name is unavailable, choose another record name; the installed app can still display LAN Browser.
3. Choose the exact **Bundle ID** selected in Xcode. If it is not yet listed, register the explicit App ID in [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) using your developer team, then return to the new-app form. Use a simple unique SKU such as **lan-browser-001** and create the record.
4. In Xcode, select an iOS device destination such as **Any iOS Device (arm64)**, then choose **Product > Archive**. Use your normal signed Release configuration; do not disable signing.
5. When Organizer opens, select the new archive and choose **Distribute App**. Choose the TestFlight internal-testing route if offered. Otherwise choose **App Store Connect > Upload** and restrict the build to internal testing if offered. Leave automatic signing enabled and complete validation/upload.
6. Wait for processing in **App Store Connect > My Apps > your app > TestFlight**. If Apple shows a missing agreement, compliance question, or other processing issue, resolve the specific item shown before adding the build.
7. Under **Internal Testing**, create a group such as **Personal**. Add your own App Store Connect account to the group. As the paid account holder, your account has an eligible role.
8. Add the processed build to the group. Optionally enable automatic distribution for subsequent builds. Suggested testing notes: “Home LAN and captive-portal browser. On home Wi-Fi, open HTTP Forever at http://httpforever.com/. On a sign-in network, confirm the portal replaces that page. Test bookmark editing and Save to Files downloads.”
9. Install Apple’s **TestFlight** app on your iPhone. Open the internal-testing invitation on that phone, accept it, and install LAN Browser.
10. Open LAN Browser from TestFlight and repeat the HTTP Forever, LAN, and download checks below. Keep the same bundle identifier when moving from the development build to TestFlight.

**Each TestFlight build expires after 90 days.** Before expiration, increase the target’s **General > Identity > Build** number (for example, 1 → 2), archive, upload, and add the replacement to your internal group. You can leave Version at 1.0 while increasing Build. Keep backups of important bookmarks before uninstalling: deleting the app removes its local data.

Apple references: [distribution from Xcode](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases), [internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers), [TestFlight lifecycle and expiration](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

## Validation

Run the core checks from Terminal in this directory:

```sh
Scripts/check.sh
```

These compile the actual address parser and bookmark store for macOS and check hostname/port parsing, HTTP/HTTPS, malformed inputs, persistence, edits, ordering, deletion, corrupt files, and write failures. They also check Bonjour service-to-URL mapping, duplicate merging, local-address detection, HTTP response parsing, diagnostic advice and report text, device naming and labels, and that `NSBonjourServices` in Info.plist matches `ServiceCatalog.types`. They also cover saved tabs, the tab-opening rule, and the discovery cache, and validate the property lists and Xcode project syntax. They also cover port-scan ranges, confirmation rules, page-title parsing, and result clean-up. They do not launch WebKit or replace the physical-device checks.

Unsigned device build, useful without selecting a signing team:

```sh
xcodebuild -project LANBrowser.xcodeproj -scheme LANBrowser \
  -configuration Debug -sdk iphoneos -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

An unsigned build cannot be installed on your iPhone or uploaded to TestFlight. Normal Xcode installation/archive must use your developer team.

### Physical-device acceptance checks

- From the bookmark screen, open **Settings** (gear). Verify the privacy policy is readable offline and that **Ask for Help or Report a Problem** opens GitHub Issues.
- Run **Browser Check** offline, save the sample file, and open it in Files.
- Sign in to a test website, then use **Clear Cookies & Website Data** in Settings. Confirm the website session is signed out, all tabs close except one blank tab, and bookmarks/exported files remain.

- First launch shows **HTTP Forever Captive Portal** in bookmarks. Open it and confirm [http://httpforever.com/](http://httpforever.com/) loads over HTTP. On a captive network, confirm the sign-in page appears instead.
- Add a home-service bookmark such as `192.168.1.20:8080`, open it, and verify the service loads over HTTP.
- Navigate between pages; check Back, Forward, Reload, Stop, and swipe navigation. A new-window link should open in a new tab.
- Tabs: tap a bookmark and confirm it opens in a new tab, and that opening one from a blank tab fills that tab. Create and close tabs from the Tabs switcher and from the Tabs button’s long-press menu. Set **Open Bookmarks In** to Current Tab and confirm a bookmark replaces the current page. Open a few tabs with some history, force-quit, and relaunch: the tabs return, and a restored tab loads only when you switch to it. Turn **Restore Tabs on Launch** off, relaunch, and confirm tabs are not restored.
- Enter an HTTPS page and test a server’s HTTP-to-HTTPS redirect; the bar should reflect the resulting address.
- Add/edit a bookmark; reorder and delete bookmarks. Force-quit and relaunch: the edited list survives and the app opens bookmarks. Deleting every bookmark should leave an empty list after relaunch.
- Test with the keyboard visible, in landscape, in dark mode, and with larger system text.
- Visit an unreachable address, then use Edit Address or Retry to recover. Tap **Diagnose** and confirm the failing step and advice make sense; try a closed port, a misspelled `.local` name, and a self-signed HTTPS device.
- First launch shows the “For Trusted Home Networks” notice once. Tap **I Understand**, force-quit, relaunch, and confirm it doesn’t return.
- Open a self-signed HTTPS device on your network, such as a router or NAS at `https://YOUR_DEVICE_LAN_IP/`. Confirm the page opens with the red “!” strip, and that the certificate sheet shows its SHA-256 fingerprint.
- Open [https://self-signed.badssl.com/](https://self-signed.badssl.com/) and confirm it is still rejected with the system’s normal error.
- Tap **Diagnose** on an `http://` address that redirects to `https://`, such as `http://YOUR_DEVICE_LAN_IP/`. Confirm the Web Server step lists both hops.
- Turn on **Local Network Features** from the bookmark-list card. Confirm the iOS Local Network prompt appears once, **On This Network** lists devices that advertise a web page, **+** saves one as a bookmark, and status dots turn green or red. Relaunch the app: the saved scan should appear with its scan time, and no new scan should start. **Scan Again** or a pull down on the bookmark list should start one. Deny the permission in the iOS Settings app and confirm the list and diagnostics explain how to turn it back on. Turn the switch off and confirm the list and dots disappear.
- On a clean install, turn on **Local Network Features** for the first time. The automatic first scan never port-scans, so its scan line should show Bonjour only.
- Pick **Common Web Apps** in **Settings › Local Network › Port Scan**. Confirm the sheet shows the right address range, the 22 ports, and the connection count, and that **Cancel** reverts the picker. Choose it again and tap **Confirm**.
- After confirming, tap **Scan Again**. Progress should appear with a **Cancel** button, and web apps that don’t advertise over Bonjour should be listed with a “port scan” tag. Relaunch the app: the saved results appear with their scan time, and no new scan starts. Start another scan and tap **Cancel** partway through: the previous list should remain.
- Rename a device from Page Info (ⓘ), then rename one from a bookmark’s long-press menu with **Rename Device…**. Confirm every bookmark on that host updates. Tap **+** on a discovered device and confirm the new bookmark uses a `.local` URL.
- To test discovery without a home server, run the fixture below and advertise it from the Mac with `dns-sd -R "LAN Fixture" _http._tcp local 8889`.
- Download a file, choose an On My iPhone or iCloud Drive destination, and open it in Files. Download the same name twice to check the system’s conflict handling. Cancel a Save to Files picker and verify browsing still works.
- Test a failed download, a file from a logged-in service if available, and multiple downloads. Each successful download should get its own destination picker.
- Repeat the key checks using the TestFlight build.

Optional local fixture for redirects, download links, attachment responses, blob downloads, new-window links, and JavaScript dialogs:

```sh
python3 Tests/serve_fixture.py
```

Keep the Terminal running and, from the phone on the same Wi-Fi, open `http://YOUR_MAC_LAN_IP:8889/`. Allow incoming connections if macOS requests them. This fixture serves only generated test pages/files. Stop it with Control-C.

## Implementation notes

The app has no analytics, advertising, cloud backend, or app-account system. Browsed websites make their own normal network requests. Bookmarks live in Application Support, alongside `devices.json` (custom device names, last-seen IPs, and reverse-lookup names), `discovered.json` (the last On This Network scan), and `tabs.json` (open tabs, while Restore Tabs on Launch is on). None of it is sent to the developer or anyone else. Website data is managed by WebKit. Download staging files live in the temporary directory and are removed after saving/cancellation or the next launch after an interrupted session.

`NSAllowsLocalNetworking` supports local hostnames/IPs. `NSAllowsArbitraryLoadsInWebContent` permits HTTP navigation and resources within WebKit, including redirects to other hostnames, without globally disabling ATS for unrelated app networking. Apple documents [local networking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking), [web-content HTTP exceptions](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloadsinwebcontent), and the [WebKit exception to local-network permission](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy). Local network discovery and the port scan are opt-in. With **Local Network Features** on, the app browses Bonjour services when you scan and makes TCP connections to saved bookmarks and discovered devices. The port scan connects only to addresses on your own network, and only after you confirm it and start a scan. Connection diagnostics make DNS, TCP, and HTTP requests to the address you check, only when you run them. Without the switch, the app does not browse the network. WebKit page loads are exempt from the iOS Local Network prompt; the native features above trigger it. Invalid HTTPS certificates are accepted only for local-network addresses, in the server-trust challenge of `BrowserTab`; each such override is recorded and shown with the red “!”. Internet sites keep normal certificate validation.

The encryption declaration reflects use of Apple’s built-in HTTPS support with no custom encryption. Revisit it if custom cryptography is added. The privacy manifest declares no tracking and no app-collected data. Its only required-reason API is UserDefaults (reason `CA92.1`), which stores the Local Network Features switch, whether its card was dismissed, the Settings choices (Port Scan, Open Bookmarks In, and Restore Tabs on Launch), and whether the first-use notice was accepted (`trustedNetworkNoticeAccepted`).

Foreground downloads only: keep the app open while downloading. Resuming downloads after termination, background transfers, and bookmark sync are outside this version.
