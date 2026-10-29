Privacy Policy — LAN Browser
Last updated: October 28, 2026 (password-saving and AutoFill update)

Developer collection
LAN Browser has no developer-operated backend, app accounts, advertising SDKs, or analytics SDKs. The developer does not receive your browsing history, bookmarks, form entries, or downloaded files through the app. The app does not track you across other companies’ apps or websites for advertising.

Browsing and third-party websites
When you open a website or home service, WebKit sends requests to that destination. The destination and its service providers can receive your IP address, request details, and any information you submit, such as login credentials or form entries. Websites may load third-party resources, use cookies and local storage, or perform their own analytics and tracking under their own privacy policies. LAN Browser does not control those websites. HTTP connections are not encrypted; other parties on the network may be able to read or modify their traffic. Use HTTPS when supported. LAN Browser is intended for trusted home networks; on a network you don’t trust, use Safari.

Data on your device
Bookmarks are stored in the app’s local storage until you edit or delete them or delete the app. WebKit stores cookies, caches, and other website data so that websites can remember sessions and preferences. Apart from open tabs saved for Restore Tabs on Launch, LAN Browser does not maintain a separate browsing-history database. Use Settings > Clear Cookies & Website Data to remove WebKit’s stored website data, sign out of websites, and delete saved tabs. This does not delete information already received by a website; contact that website to request deletion or change consent preferences. Deleting the app removes its local app data; operating-system backups may retain copies according to your backup settings.

Tabs
When Restore Tabs on Launch is on, which is the default, the addresses, titles, and Back/Forward history of your open tabs are saved on the device so they can be restored at launch. Turning the setting off, or using Clear Cookies & Website Data, deletes the saved tabs. Saved tabs are never sent to the developer or anyone else.

Saved passwords
Offer to Save Passwords is on by default in Settings (the gear). Each supported login-form submission offers Save or Not Now, including on HTTP pages and for previously saved credentials. Saving stores the username and password in this device’s Keychain, separated by scheme, host, port and username; saving again updates that entry. Passwords are available only while the device is unlocked and aren’t synced to iCloud or migrated to another device. Settings > Saved Passwords lets you reveal, copy and delete them. AutoFill Saved Passwords is also on by default and can be turned off separately in Settings. It fills supported main-page login forms for the exact saved scheme, host and port, including HTTP pages, without submitting the form. An entered username selects its matching account; an empty form uses the most recently saved account. Existing password text is preserved. Filled credentials are available to that website’s scripts before you submit.  Turning offers off and clearing website data keep saved passwords. Keychain entries may survive app deletion, so delete saved passwords before uninstalling. Embedded sign-in frames, HTTP authentication dialogs and some custom forms aren’t supported. Saving a password does not encrypt HTTP traffic. Credential capture is handled locally and credentials are never sent to the developer. Saving happens only after you choose Save. The save-offer and AutoFill preferences are stored in UserDefaults; credentials are not stored in the app’s JSON files or preferences.

Downloads
Downloads are temporarily staged inside the app before you choose a destination in Save to Files. Staged files are removed after export or cancellation, or at the next launch following an interrupted session. Exported files remain in the destination you selected, including a cloud storage provider if you chose one. Delete exported files through Files or the selected storage provider.

Local network
Local network features are off until you turn them on in the app. Without the switch on, the app does not browse the network. When on, the app uses Bonjour (local multicast DNS) to find web apps advertised on your current network. It scans once automatically the first time you turn the feature on, and after that only when you ask. The optional port scan is off until you choose a preset in Settings > Local Network > Port Scan and confirm it. It connects only to addresses on your own local network, and only as part of a scan you start; it never runs in the automatic first scan. The last scan, including the device names, page titles, and addresses it found, is saved on the device until you scan again or clear it. Apart from that saved scan, discovered services are not saved unless you add one as a bookmark. Bonjour discovery and the port scan stay on your local network. Status checks contact only your bookmarked addresses and the devices found on your network, including public ones such as httpforever.com. Connection diagnostics run only when you ask and contact the address you are checking. Name lookups use iOS’s normal DNS resolver. On local-network addresses, the app opens HTTPS pages whose certificates iOS can’t verify, marking them with a red “!”; internet sites with invalid certificates are still rejected. Nothing from discovery, the port scan, status checks, or diagnostics is sent to the developer or any third party, and nothing is collected. The setting is stored on your device. Device names you set, the last-seen IP for each host name, and names from reverse DNS lookups are stored in the app’s local storage on your device and are never sent to the developer or anyone else. The system asks for Local Network permission before these features can work. Its prompt also mentions checking common web ports if you confirm the port scan. You can change that permission in Settings on an iPhone or iPad, or in System Settings on a Mac.

Platform services and support
Apple may process App Store, backup, or diagnostic information according to its policies and your device settings. Debug builds used for development log website diagnostic details to the local Xcode console; this diagnostic logging is excluded from Release builds distributed through the App Store.

If you contact support through GitHub Issues, GitHub processes your account and submission under its privacy policy. Issues are public, and the developer can read and respond to information you post. Do not post passwords, private addresses, browsing records, or other sensitive information. You can edit or delete your own issue content using GitHub’s controls, subject to GitHub’s policies.

Children
LAN Browser is a general-purpose browser and is not specifically directed to children. Visited websites have their own content and privacy practices. Parents and guardians should supervise access as appropriate.

Changes and contact
Updates to this policy will be published with a revised date. For privacy questions or app support, contact the developer through:
https://github.com/jessegoodier/lan-browser/issues

Online policy:
https://github.com/jessegoodier/lan-browser/blob/main/LANBrowser/privacy_policy.md
