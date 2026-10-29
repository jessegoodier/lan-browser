# LAN Browser support

For help, bug reports, or privacy questions, [contact the developer through GitHub Issues](https://github.com/jessegoodier/lan-browser/issues). A GitHub account is required to post. Issues are public: do not include passwords, private server addresses, personal browsing records, or other sensitive information.

In the app, open **Settings** (the gear button on the bookmark screen) for help, the offline privacy policy, website-data deletion, and **Run Browser Check**. The browser check works offline and offers a sample download to test Save to Files.

## Connection troubleshooting

- Home server: use the same Wi-Fi as the server. Check its address and port. Try that address in Safari; if both fail, check server availability, DNS, firewall, and guest-network isolation.
- Wi-Fi sign-in: open **HTTP Forever Captive Portal**. A sign-in page appears only on a network that intercepts HTTP and requires authentication. The app cannot guarantee interception or bypass the network’s requirements.
- HTTPS on a local address: if a device’s certificate isn’t trusted (self-signed, expired, or wrong name), the page still opens with a red “!” strip. Tap it to see the certificate details, and compare the SHA-256 fingerprint with the device. Internet sites with invalid certificates are rejected; fix the certificate on the site, or use Safari.
- Downloads: keep the app open until the save completes. Choose a destination in Files; exported files must be deleted through Files or your storage provider.
- Login problems: **Settings > Clear Cookies & Website Data** signs you out, removes website storage, and closes your tabs. Your bookmarks and exported files remain.
- Connection problems: run **Why can’t I connect?** from Page Info (ⓘ), the **Diagnose** button on a “Page unavailable” screen, or **Check Connection** in a bookmark’s long-press menu. To ask for help, tap **Copy Report** and paste the text into your issue. The report may include your device’s IP address and the addresses you tested, so remove any private addresses before posting.
- Local Network permission: if discovery, bookmark status dots, or diagnostics report that Local Network access is denied, open **Settings › Privacy & Security › Local Network › LAN Browser** and turn it on. On a Mac, open **System Settings › Privacy & Security › Local Network** and turn on LAN Browser.
- Out-of-date On This Network list: tap **Scan Again** in the section’s ••• menu, or pull down on the bookmark list (on a Mac, use Scan Again). **Clear Results** in the same menu removes the list.
- Device missing from On This Network: a device that doesn’t advertise itself with Bonjour can be found by turning on **Port Scan** in **Settings › Local Network** and confirming it. If the list says the port scan needs confirming for this network, tap **Review**.
- Wrong device name: rename the device from Page Info (ⓘ), or choose **Rename Device…** from a bookmark’s or On This Network row’s long-press menu. Leaving the name empty restores the default.

[Privacy policy](LANBrowser/privacy_policy.md)
