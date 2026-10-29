import UIKit
import WebKit

/// Standalone simulator app: exercises real Keychain writes and dismissed-alert state.
@main
final class PasswordSaveChecks: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { @MainActor in
            do {
                try await runChecks()
                FileHandle.standardOutput.write(Data("PASSWORD_SAVE_CHECKS_PASSED\n".utf8))
                exit(0)
            } catch {
                // Error domains/codes identify failures without printing credential values.
                let error = error as NSError
                FileHandle.standardOutput.write(Data("PASSWORD_SAVE_CHECKS_FAILED \(error.domain) \(error.code)\n".utf8))
                exit(1)
            }
        }
        return true
    }

    private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        let passed = try condition()
        precondition(passed, message)
    }

    @MainActor
    private func runChecks() async throws {
        let preference = UserDefaults.standard.object(forKey: PasswordPolicy.enabledKey)
        UserDefaults.standard.set(true, forKey: PasswordPolicy.enabledKey)
        defer { UserDefaults.standard.set(preference, forKey: PasswordPolicy.enabledKey) }
        let session = BrowserSession()
        let origin = PasswordOrigin(URL(string: "http://192.0.2.1:8080/login")!)!
        let saved = SavedPassword(origin: origin, username: "test-user")
        defer { try? PasswordStore.delete(saved) }
        let initial = PasswordOffer(tabID: session.selectedID, origin: origin, username: saved.username, password: "initial-test-value")
        session.offerPassword(initial)
        // This is SwiftUI’s dismissal callback, before the Save button’s action.
        session.passwordOffer = nil
        session.savePassword(initial)
        try expect(PasswordStore.password(for: saved) == initial.password, "Save must survive alert dismissal")

        let replacement = PasswordOffer(tabID: session.selectedID, origin: origin, username: saved.username, password: "replacement-test-value")
        session.offerPassword(replacement)
        session.passwordOffer = nil // Not Now.
        try expect(PasswordStore.password(for: saved) == initial.password, "Not Now must retain the old password")
        session.savePassword(replacement)
        try expect(PasswordStore.password(for: saved) == replacement.password, "Save must update the existing password")
        try expect(PasswordStore.list().filter { $0.id == saved.id }.count == 1, "Updating must not duplicate the saved entry")

        let ipv6 = PasswordOrigin(URL(string: "https://[fd00::1]:8443/login")!)!
        let unicode = SavedPassword(origin: ipv6, username: "test-用户名/:")
        defer { try? PasswordStore.delete(unicode) }
        let unicodeOffer = PasswordOffer(tabID: session.selectedID, origin: ipv6, username: unicode.username, password: "秘密-test")
        try PasswordStore.save(unicodeOffer)
        try expect(PasswordStore.list().contains { $0.id == unicode.id }, "IPv6 and Unicode metadata must round-trip")
        try expect(PasswordStore.password(for: unicode) == unicodeOffer.password, "Unicode password must round-trip")

        try await runAutofillChecks(session)

        UserDefaults.standard.set(false, forKey: PasswordPolicy.enabledKey)
        session.savePassword(initial)
        try expect(PasswordStore.password(for: saved) == replacement.password, "Disabling offers must prevent a pending save")
        try PasswordStore.delete(saved)
        try expect(!PasswordStore.list().contains { $0.id == saved.id }, "Deleting must remove the saved entry")
    }
}

extension PasswordSaveChecks {
    @MainActor
    private func runAutofillChecks(_ session: BrowserSession) async throws {
        let preference = UserDefaults.standard.object(forKey: PasswordPolicy.autofillKey)
        UserDefaults.standard.set(true, forKey: PasswordPolicy.autofillKey)
        defer { UserDefaults.standard.set(preference, forKey: PasswordPolicy.autofillKey) }
        let origin = PasswordOrigin(URL(string: "http://127.0.0.1:8893/login")!)!
        let saved = SavedPassword(origin: origin, username: "autofill-test-user")
        defer { try? PasswordStore.delete(saved) }
        try PasswordStore.save(PasswordOffer(tabID: session.selectedID, origin: origin, username: saved.username, password: "autofill-test-value"))
        let webView = session.selectedTab.webView
        let controller = UIViewController()
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = controller
        window?.makeKeyAndVisible()
        webView.frame = controller.view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(webView)
        session.selectedTab.navigate(to: URL(string: "http://127.0.0.1:8893/login")!)
        try await waitFor(webView, "document.querySelector('input[type=password]')?.value === 'autofill-test-value'")
        let filledUsername = try await webView.evaluateJavaScript("document.querySelector('input[name=username]').value") as? String
        try expect(filledUsername == saved.username, "A real WebKit form must receive the saved username")

        // Changing the host must not expose credentials, even to the same server and port.
        session.selectedTab.navigate(to: URL(string: "http://localhost:8893/login")!)
        try await waitFor(webView, "location.hostname === 'localhost' && !!document.querySelector('input[type=password]')")
        try await Task.sleep(for: .milliseconds(400))
        let otherHost = try await webView.evaluateJavaScript("document.querySelector('input[type=password]').value") as? String
        try expect(otherHost == "", "Real WebKit AutoFill must not cross hosts")

        UserDefaults.standard.set(false, forKey: PasswordPolicy.autofillKey)
        session.selectedTab.navigate(to: URL(string: "http://127.0.0.1:8893/login")!)
        try await waitFor(webView, "location.hostname === '127.0.0.1' && !!document.querySelector('input[type=password]')")
        try await Task.sleep(for: .milliseconds(400))
        let disabled = try await webView.evaluateJavaScript("document.querySelector('input[type=password]').value") as? String
        try expect(disabled == "", "Turning AutoFill off must prevent native Keychain filling")

        UserDefaults.standard.set(true, forKey: PasswordPolicy.autofillKey)
        session.selectedTab.navigate(to: URL(string: "http://127.0.0.1:8893/next")!)
        try await waitFor(webView, "document.title === 'Next page'")
        _ = try await webView.evaluateJavaScript("document.body.insertAdjacentHTML('beforeend', '<form><input name=username autocomplete=username><input type=password autocomplete=current-password><button>Sign In</button></form>')")
        try await waitFor(webView, "document.querySelector('input[type=password]')?.value === 'autofill-test-value'")
        session.passwordOffer = nil
        _ = try await webView.evaluateJavaScript("document.querySelector('form').requestSubmit()")
        for _ in 0..<100 {
            if session.passwordOffer != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try expect(session.passwordOffer?.username == saved.username, "Submitting an autofilled form must still offer to save")
        session.passwordOffer = nil
        controller.view.subviews.forEach { $0.removeFromSuperview() }
    }

    @MainActor
    private func waitFor(_ webView: WKWebView, _ condition: String) async throws {
        for _ in 0..<100 {
            if (try? await webView.evaluateJavaScript(condition)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "PasswordSaveChecks.WebKitTimeout", code: 1)
    }
}
