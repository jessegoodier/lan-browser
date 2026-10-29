# AGENTS.md

Guidance for coding agents working in this repository.

## What this is

LAN Browser is a small tabbed iPhone browser (SwiftUI + WebKit) for home-network web apps and captive-portal Wi-Fi. Plain HTTP is a feature, not a bug. There is no backend and no analytics. It is meant only for trusted home networks, as the first-use notice says. Minimum iOS is **17.0** (pinned at project and target level). It builds with current Xcode; there are no dependencies to install.

This file doubles as the contributor guide: it describes the layout, commands and conventions that both people and coding agents should follow.

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
| `DiagnosticsLogic.swift` | Diagnostic step types, advice text, HTTP status/header/`<title>` parsing, report text; `PageResponse` (a non-200 main-page response with its headers), `HTTPStatus` (standard reason phrases), `ErrorText` (exact error domain/code/URL), `Redirects` and `BlockedPorts` (the Fetch “bad ports” WebKit drops silently) |
| `NetworkProbe.swift` | Native checks: TCP connect, raw HTTP GET (with TLS trust recording), DNS lookup, network snapshot, and `NetworkProbe.follow` for redirect chains (`Redirects.limit` = 5; used by diagnostics and the port scan’s page reading) |
| `Certificates.swift` | `CertificateSummary`, `CertificateIssue`: chain details (subject, common name, validity, key, serial, SHA-256 fingerprints) and report text for untrusted local certificates |
| `LocalNetwork.swift` | Opt-in Bonjour discovery (`NWBrowser`), run on demand after one automatic first scan, the two-pass port scan once confirmed, and bookmark reachability dots |
| `PortScan.swift` | Pure port-scan logic: `PortScanPreset`, `IPv4Range` (capped at 1,024 addresses), `PortScanPlan` (a confirmed scan), `WebFinding` (a page that answered), and `PortScan.collapse` and `PortScan.name` (result clean-up and row titles) |
| `DiscoveryCache.swift` | `DiscoveryScan` in discovered.json: the last On This Network scan, kept until the next scan or clear |
| `ConnectionDiagnostics.swift` | Runs the “Why can’t I connect?” steps |
| `NetworkViews.swift` | Opt-in card, On This Network section, status dot, port-scan confirmation sheet, diagnostics views, the response strip and details (`ResponseBanner`, `ResponseDetailsView`), and the certificate strip and details (`CertificateStrip`, `CertificateDetailsView`) |
| `SettingsView.swift` | Settings sheet, help page, privacy policy view, and `TrustedNetworkNotice` (the first-use notice, also shown at the top of the help page) |

Other locations:
- `Tests/CoreChecks.swift` is a standalone `@main` executable using `precondition`. There is no XCTest target.
- `Tests/serve_fixture.py` is a manual test server on port 8889.
- `docs/TESTING.md` lists manual on-device checks.
- `LICENSE` is MIT.
- `.github/workflows/`: `ci.yml` (check.sh and an unsigned simulator build), `codeql.yml` (Swift, Actions, Python), `scorecard.yml`, `zizmor.yml` (workflow security audit), `dependency-review.yml`.
- `Scripts/policy_check.sh` (run by `check.sh`) fails if ATS gains an exception, the privacy manifest declares tracking or collected data, a package dependency appears, or `URLCredential(trust:)` is used outside `BrowserTab` or without the `isLocalHost` check. Changing those guarantees means changing this script and the docs together.
- `SECURITY.md` is the vulnerability policy; `.github/dependabot.yml` updates GitHub Actions.

## Commands

```sh
Scripts/check.sh   # compiles Foundation-only sources + CoreChecks for macOS, runs them, lints plists/pbxproj, runs policy_check.sh
xcodebuild -project LANBrowser.xcodeproj -scheme LANBrowser \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build
```

To test discovery manually:
1. Run `python3 Tests/serve_fixture.py`.
2. Run `dns-sd -R "LAN Fixture" _http._tcp local 8889` on the Mac.
3. Turn on Local Network Features in the app.

The simulator sees the Mac’s LAN. The Local Network permission prompt only behaves realistically on a device.

### Testing without UI automation

There is no XCUITest target and simulator taps can’t be scripted here, so test by setting state and taking screenshots:
- **Simulator state:** write JSON into the app container before launch. Get the folder with `xcrun simctl get_app_container <sim> com.jesse.lanbrowser data`, then use `Library/Application Support/LANBrowser/`:
  - `tabs.json` opens a given URL in the selected tab, which loads on launch.
  - `discovered.json` shows a saved scan.
  - Set preferences with `xcrun simctl spawn <sim> defaults write com.jesse.lanbrowser <key> …`, for example `localNetworkFeatures`, `localNetworkAutoScanned`, `trustedNetworkNoticeAccepted` or `portScanPreset`.
  - Capture with `xcrun simctl io <sim> screenshot`.
- **Network code** (`LocalNetwork`, `ConnectionDiagnostics`, `NetworkProbe`) also compiles for macOS. Build it with a small `@main` runner under `build/` (gitignored) using the same `swiftc` flags as `Scripts/check.sh`, then run it against the real LAN.
- **Test servers:** a few lines of Python `http.server` can return a specific status or body, e.g. a blank 404 or a 404 sent as `application/octet-stream`.
- **zsh:** don’t name a shell loop variable `path`. In zsh it is tied to `PATH` and breaks every later command.

## Conventions

- **Xcode project:** `project.pbxproj` uses hand-numbered IDs, not synchronized folders. Every new file needs a PBXFileReference, a PBXBuildFile, a group child and a Sources (or Resources) entry. Continue the existing ID sequence.
- **Testable logic:** keep pure logic in Foundation-only files (no UIKit, WebKit or SwiftUI) and add them to `Scripts/check.sh` with checks in `CoreChecks.swift`. It currently compiles `Address`, `Bookmarks`, `ServiceCatalog`, `DiagnosticsLogic`, `DeviceNames`, `TabStore`, `DiscoveryCache` and `PortScan`.
- **Concurrency:** use Swift 5 mode with `SWIFT_STRICT_CONCURRENCY = complete`. Models are `@MainActor final class … : ObservableObject` with `@Published`; don’t switch to `@Observable`. `NetworkProbe` bridges Network.framework callbacks with `Once`, a resume-exactly-once continuation helper.
- **State wrapper:** in view files, use `@ViewState`, a private `typealias ViewState<Value> = SwiftUI.State<Value>` that avoids a same-named SDK macro. Redeclare it in each new view file.
- **Style:** comments are sparse and explain *why*. User-facing copy is full sentences with curly apostrophes (’). Errors shown to users are `String?` messages, not typed error UI.
- **Bookmark schema:** `bookmarks.json` must keep decoding. Any new `Bookmark` field must be optional or decoded with `decodeIfPresent`, because a decode failure leaves the file untouched and shows an error.
- **Seed bookmark:** `CoreChecks` asserts it is exactly `[.httpForever]`.
- **Workflows:** pin every action to a full commit SHA with a `# vX.Y.Z` comment, set `permissions: {}` at the top level and grant the least each job needs, use `persist-credentials: false` on checkout, and never interpolate `${{ }}` expressions into `run:` scripts (pass them through `env:`). zizmor runs on every PR and must stay clean.

## Privacy and networking rules

- WebKit page loads are exempt from the iOS Local Network prompt. Native networking (`NWBrowser`, `NWConnection`, `getaddrinfo` on `.local`) triggers it.
- **Status dots** run only when the user has turned on **Local Network Features** (UserDefaults key `localNetworkFeatures`), the bookmark list is visible and the app is active. Don’t add background or automatic native probing.
- **Discovery** runs only when the user has turned on **Local Network Features**. It runs one automatic scan the first time the feature is turned on (or the first time the bookmark list opens after updating with it on), then only from a user action: **Scan Again** or pull-to-refresh. Don’t add automatic Bonjour or port scans.
- **Port scan** (`PortScan.swift`, run from `LocalNetwork.swift`): never port-scan without a confirmed `PortScanPlan`, never from the automatic first scan, only from a user-started scan, and only addresses in the phone’s own network range (capped at 1,024).
- **Diagnostics** run only when the user opens them.
- **Never a blank page:** any main-frame HTTP response other than 200 must be shown, as the strip above the page or, if it can’t be displayed, as the error screen headed by the status.
  - Error responses are never turned into downloads.
  - Load failures show the exact error domain, code, underlying error and URL.
  - Browser-blocked ports are explained before WebKit drops them silently.
  - The status code and header values are shown verbatim. Reason phrases are the standard ones, because WebKit doesn’t expose the server’s, and the UI says so.
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
  - `docs/TESTING.md`, when a manual check changes
