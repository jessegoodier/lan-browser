# AGENTS.md

Guidance for coding agents working in this repository.

## What this is

LAN Browser is a small tabbed iPhone browser (SwiftUI + WebKit) for home-network web apps and captive-portal Wi-Fi. Plain HTTP is a feature, not a bug. There are no dependencies, no backend, and no analytics. It is meant only for trusted home networks, as the first-use notice says. Minimum iOS is **17.0** (pinned at project and target level). It builds with Xcode 27.1.

## Files

All app code is in `LANBrowser/`:

| File | Purpose |
| --- | --- |
| `LANBrowserApp.swift` | App entry point |
| `BrowserScreen.swift` | Main screen, bottom toolbar, bookmark list, sheets (Page Info, bookmark editor, rename alert) |
| `BrowserModel.swift` | `BrowserSession`: tabs, selection, downloads and export queue, tab saving, clear website data. Also `PageInfo` and debug-only `PageDiagnostics` |
| `BrowserTab.swift` | One tab: lazy `WKWebView`, navigation state, page errors, new-window links (open a new tab), JS dialogs |
| `TabStore.swift` | `SavedTab`/`SavedTabs` in tabs.json, `TabPolicy`, `OpenBookmarksIn` |
| `TabViews.swift` | Tab switcher grid |
| `Bookmarks.swift` | `Bookmark` model and `BookmarkStore` (JSON in Application Support) |
| `DeviceNames.swift` | `DeviceRecord`/`DeviceStore`: friendly names, last-seen IPs and reverse-lookup names per host (devices.json); `label(for:)` builds `name:port · IP` |
| `Address.swift` | `BrowserAddress.parse`: user input to http/https URL |
| `ServiceCatalog.swift` | Bonjour types, service-to-URL mapping, duplicate merging, `isLocalHost` |
| `DiagnosticsLogic.swift` | Diagnostic step types, advice text, HTTP status/header parsing, report text |
| `NetworkProbe.swift` | Native checks: TCP connect, raw HTTP GET (with TLS trust recording), DNS lookup, network snapshot, and `NetworkProbe.follow` for redirect chains (`Redirects.limit` = 5; used by diagnostics and the port scan’s page reading) |
| `Certificates.swift` | `CertificateSummary`, `CertificateIssue`: chain details (subject, common name, validity, key, serial, SHA-256 fingerprints) and report text for untrusted local certificates |
| `LocalNetwork.swift` | Opt-in Bonjour discovery (`NWBrowser`), run on demand after one automatic first scan, the two-pass port scan once confirmed, and bookmark reachability dots |
| `PortScan.swift` | Pure port-scan logic: `PortScanPreset`, `IPv4Range` (capped at 1,024 addresses), `PortScanPlan` (a confirmed scan), `WebFinding` (a page that answered), and `PortScan.collapse` and `PortScan.name` (result clean-up and row titles) |
| `DiscoveryCache.swift` | `DiscoveryScan` in discovered.json: the last On This Network scan, kept until the next scan or clear |
| `ConnectionDiagnostics.swift` | Runs the “Why can’t I connect?” steps |
| `NetworkViews.swift` | Opt-in card, On This Network section, status dot, diagnostics views |
| `SettingsView.swift` | Settings sheet, help page, privacy policy view, and `TrustedNetworkNotice` (the first-use notice, also shown at the top of the help page) |

Other locations:
- `Tests/CoreChecks.swift` is a standalone `@main` executable using `precondition`. There is no XCTest target.
- `Tests/serve_fixture.py` is a manual test server on port 8889.
- `APP_STORE_SUBMISSION.md` is gitignored and local only.

## Commands

```sh
Scripts/check.sh   # compiles Foundation-only sources + CoreChecks for macOS, runs them, lints plists/pbxproj
xcodebuild -project LANBrowser.xcodeproj -scheme LANBrowser \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build
```

To test discovery manually:
1. Run `python3 Tests/serve_fixture.py`.
2. Run `dns-sd -R "LAN Fixture" _http._tcp local 8889` on the Mac.
3. Turn on Local Network Features in the app.

The simulator sees the Mac’s LAN. The Local Network permission prompt only behaves realistically on a device.

## Conventions

- **Xcode project:** `project.pbxproj` uses hand-numbered IDs, not synchronized folders. Every new file needs a PBXFileReference, a PBXBuildFile, a group child and a Sources (or Resources) entry. Continue the existing ID sequence.
- **Testable logic:** keep pure logic in Foundation-only files (no UIKit, WebKit or SwiftUI) and add them to `Scripts/check.sh` with checks in `CoreChecks.swift`. It currently compiles `Address`, `Bookmarks`, `ServiceCatalog`, `DiagnosticsLogic`, `DeviceNames`, `TabStore`, `DiscoveryCache` and `PortScan`.
- **Concurrency:** use Swift 5 mode with `SWIFT_STRICT_CONCURRENCY = complete`. Models are `@MainActor final class … : ObservableObject` with `@Published`; don’t switch to `@Observable`. `NetworkProbe` bridges Network.framework callbacks with `Once`, a resume-exactly-once continuation helper.
- **State wrapper:** in view files, use `@ViewState`, a private `typealias ViewState<Value> = SwiftUI.State<Value>` that avoids a same-named SDK macro. Redeclare it in each new view file.
- **Style:** comments are sparse and explain *why*. User-facing copy is full sentences with curly apostrophes (’). Errors shown to users are `String?` messages, not typed error UI.
- **Bookmark schema:** `bookmarks.json` must keep decoding. Any new `Bookmark` field must be optional or decoded with `decodeIfPresent`, because a decode failure leaves the file untouched and shows an error.
- **Seed bookmark:** `CoreChecks` asserts it is exactly `[.httpForever]`.

## Privacy and networking rules

- WebKit page loads are exempt from the iOS Local Network prompt. Native networking (`NWBrowser`, `NWConnection`, `getaddrinfo` on `.local`) triggers it.
- **Status dots** run only when the user has turned on **Local Network Features** (UserDefaults key `localNetworkFeatures`), the bookmark list is visible and the app is active. Don’t add background or automatic native probing.
- **Discovery** runs only when the user has turned on **Local Network Features**. It runs one automatic scan the first time the feature is turned on (or the first time the bookmark list opens after updating with it on), then only from a user action: **Scan Again** or pull-to-refresh. Don’t add automatic Bonjour or port scans.
- **Port scan** (`PortScan.swift`, run from `LocalNetwork.swift`): never port-scan without a confirmed `PortScanPlan`, never from the automatic first scan, only from a user-started scan, and only addresses in the phone’s own network range (capped at 1,024).
- **Diagnostics** run only when the user opens them.
- **Device names** are keyed by `DeviceStore.key(host)`: the lowercased host name, or the IP when there is no host name. iOS doesn’t expose MAC addresses to apps, so don’t key names by hardware. IP and reverse-lookup learning runs only with **Local Network Features** on, from discovery, the port scan, status checks, or a user-opened Page Info sheet. Don’t add lookups that run otherwise.
- **Bonjour types:** `NSBonjourServices` in `Info.plist` must exactly match `ServiceCatalog.types`; `check.sh` enforces this. Only add types that serve a web page.
- **HTTP probes** use raw `NWConnection`, not `URLSession`. ATS only exempts WebKit content and local hosts, so URLSession would block public plain-HTTP hosts. Certificate overrides happen only in `BrowserTab`’s server-trust challenge handler and only for `ServiceCatalog.isLocalHost` hosts. Every override is recorded in `untrustedCertificates` and must stay visible (the red “!” strip and Page Info). Never extend it to internet hosts. Diagnostics only *report* trust.
- **Privacy manifest:** `PrivacyInfo.xcprivacy` declares UserDefaults (`CA92.1`). Update it if you use another required-reason API.
- **Docs:** when networking or privacy behavior changes, update all of these together:
  - `README.md`
  - `LANBrowser/privacy_policy.md`, which is bundled and shown in the app; bump its “Last updated” date
  - The Settings and help text in `SettingsView.swift`
  - The first-use notice text (“For Trusted Home Networks”, `TrustedNetworkNotice`), which must match the top of the Using LAN Browser help page
  - `SUPPORT.md`
  - `NSLocalNetworkUsageDescription`
  - `APP_STORE_SUBMISSION.md`
