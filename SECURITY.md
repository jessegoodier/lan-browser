# Security policy

## Supported versions

Only the latest App Store release and the `main` branch receive security fixes. Earlier releases are not patched. To get a fix, update LAN Browser from the App Store.

## Reporting a vulnerability

Report vulnerabilities privately through GitHub’s private vulnerability reporting: https://github.com/jessegoodier/lan-browser/security/advisories/new

Don’t open a public issue, pull request or discussion about a vulnerability. A public report exposes every user before a fix exists.

Include, where you can:

- The LAN Browser version (shown in **Settings › Help & Support**), your iOS version and your device.
- Steps to reproduce the problem.
- The impact: what an attacker could read, send, change or run.
- Whether the attack needs a malicious device or network on the same LAN, a malicious web page, or something else.

The developer acknowledges each report within 7 days and aims to fix the problem or explain the decision within 90 days. Disclosure is coordinated with the reporter. A public advisory is published once a fix is available, and credit is offered in that advisory if you want it.

## Scope

In scope:

- A certificate override that applies to a host outside the local network, such as an internet site.
- Native networking (Bonjour, port scanning, status checks, DNS lookups) that runs without **Local Network Features** turned on, or a port scan that runs without a confirmed scan.
- A port scan that reaches addresses outside the phone’s own network range.
- Data leaving the device. Bookmarks, device names, addresses, discovery results and saved tabs stay on the device.
- JavaScript or page content escaping WebKit’s sandbox through app code, such as an unintended message handler or bridge.
- Saved data files (`bookmarks.json`, `devices.json`, `tabs.json` and `discovered.json`) that are parsed unsafely, for example a file that crashes the app or runs code.

Out of scope, by design and as documented in the README:

- Plain HTTP being allowed in web content. Plain HTTP is intentional, for home servers and captive portals.
- An HTTPS page on a local-network address with an untrusted certificate that opens with a visible red “!” warning.
- Vulnerabilities in WebKit or iOS. Report those to Apple at https://security.apple.com.
- Issues that require a jailbroken device.

## Security design

- There are no third-party dependencies. The app uses only Apple’s frameworks.
- There is no backend, analytics or account system. Nothing from the app itself is sent to the developer or a third party. Browsed websites make their own normal requests.
- App Transport Security stays on. The only exceptions are `NSAllowsLocalNetworking`, for local hostnames and IP addresses, and `NSAllowsArbitraryLoadsInWebContent`, for plain HTTP inside WebKit pages.
- Certificate overrides apply only to local-network hosts. Each override is recorded and shown with a red “!” warning.
- `Scripts/policy_check.sh` runs in CI and fails the build if any of the guarantees above is loosened: an added ATS exception, tracking or collected data in the privacy manifest, a package dependency, or a certificate override outside the local-host check.
- CI runs CodeQL, OpenSSF Scorecard, zizmor (a GitHub Actions workflow security audit) and dependency review.
- GitHub Actions are pinned to full commit SHAs, and Dependabot keeps those pins current.
