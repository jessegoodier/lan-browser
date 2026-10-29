import SwiftUI

private typealias ViewState<Value> = SwiftUI.State<Value>

struct SavedPasswordsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ViewState private var passwords: [SavedPassword] = []
    @ViewState private var revealed: String?
    @ViewState private var revealedID: String?
    @ViewState private var errorMessage: String?

    var body: some View {
        List {
            if passwords.isEmpty {
                Text("No passwords have been saved.").foregroundStyle(.secondary)
            }
            ForEach(passwords) { saved in
                VStack(alignment: .leading, spacing: 8) {
                    Text(saved.origin.label).font(.headline)
                    Text(saved.username.isEmpty ? "No username" : saved.username)
                    if revealedID == saved.id, let revealed {
                        Text(revealed).textSelection(.enabled).privacySensitive()
                    }
                    Button(revealedID == saved.id ? "Hide Password" : "Show Password") {
                        revealed = nil
                        if revealedID == saved.id { revealedID = nil; return }
                        do {
                            revealed = try PasswordStore.password(for: saved)
                            revealedID = saved.id
                        } catch { errorMessage = "Couldn’t read this password. \(error.localizedDescription)" }
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        do {
                            try PasswordStore.delete(saved)
                            revealed = nil
                            revealedID = nil
                            load()
                        } catch { errorMessage = "Couldn’t delete this password. \(error.localizedDescription)" }
                    }
                }
            }
            Section {
                Text("Passwords are stored in this device’s Keychain. They aren’t synced to iCloud. AutoFill Saved Passwords fills matching login forms when enabled in Settings. Select a revealed password to copy it. Delete saved passwords here before uninstalling; Keychain items may survive app deletion.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Saved Passwords")
        .onAppear(perform: load)
        .onDisappear { revealed = nil; revealedID = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { revealed = nil; revealedID = nil }
        }
        .alert("Saved Passwords", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) { errorMessage = nil } } message: { Text(errorMessage ?? "") }
    }

    private func load() {
        do { passwords = try PasswordStore.list() }
        catch { errorMessage = "Couldn’t load saved passwords. \(error.localizedDescription)" }
    }
}
