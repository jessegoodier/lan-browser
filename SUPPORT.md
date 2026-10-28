# LAN Browser support

For help, bug reports, or privacy questions, [contact the developer through GitHub Issues](https://github.com/jessegoodier/lan-browser/issues). A GitHub account is required to post. Issues are public: do not include passwords, private server addresses, personal browsing records, or other sensitive information.

In the app, open **Bookmarks > Help & Privacy** for help, the offline privacy policy, website-data deletion, and **Run Browser Check**. The browser check works offline and offers a sample download to test Save to Files.

## Connection troubleshooting

- Home server: use the same Wi-Fi as the server. Check its address and port. Try that address in Safari; if both fail, check server availability, DNS, firewall, and guest-network isolation.
- Wi-Fi sign-in: open **HTTP Forever Captive Portal**. A sign-in page appears only on a network that intercepts HTTP and requires authentication. The app cannot guarantee interception or bypass the network’s requirements.
- HTTPS: invalid certificates are not bypassed. Fix the certificate on your server.
- Downloads: keep the app open until the save completes. Choose a destination in Files; exported files must be deleted through Files or your storage provider.
- Login problems: **Help & Privacy > Clear Cookies & Website Data** signs you out and removes website storage. Your bookmarks and exported files remain.

[Privacy policy](LANBrowser/privacy_policy.md)
