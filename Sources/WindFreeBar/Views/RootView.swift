import SwiftUI

struct RootView: View {
    @Environment(ACStore.self) private var store

    var body: some View {
        Group {
            switch store.phase {
            case .ready:
                ControlPanel()
            case .loading:
                StatusCard(symbol: "air.conditioner.horizontal", title: "Connecting…", busy: true)
            case .signingIn:
                VStack(spacing: 0) {
                    StatusCard(symbol: "person.badge.key", title: "Finish signing in in your browser", busy: true)
                    Button("Cancel") { store.cancelSignIn() }
                        .padding(.bottom, 24)
                }
            case .signedOut:
                SignInCard()
            case .needsClient:
                ClientSetupCard()
            case .noDevice:
                StatusCard(symbol: "questionmark.circle", title: "No air conditioner found in this SmartThings location")
            }
        }
        .frame(width: 372)
        // Poll faster only while the panel is actually on screen.
        .background(WindowVisibilityReader { store.isPanelVisible = $0 })
    }
}

private struct StatusCard: View {
    let symbol: String
    let title: LocalizedStringKey
    var busy = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if busy { ProgressView().controlSize(.small) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}

private struct SignInCard: View {
    @Environment(ACStore.self) private var store

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "air.conditioner.horizontal")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text("Connect SmartThings").font(.title3.weight(.semibold))
                Text("Sign in once and pick the location with your air conditioner. The app keeps itself signed in after that.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Button("Sign in with SmartThings") { Task { await store.signIn() } }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            QuitButton()
        }
        .padding(28)
    }
}

private struct ClientSetupCard: View {
    @Environment(ACStore.self) private var store
    @ViewState private var clientId = ""
    @ViewState private var clientSecret = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SmartThings OAuth client").font(.headline)
            Text("Create one with `smartthings apps:create` (OAuth-In app, redirect URI `windfreebar://oauth`, scopes `r:devices:*` `x:devices:*` `r:locations:*`) and paste its credentials.")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Client ID", text: $clientId)
            SecureField("Client secret", text: $clientSecret)
            HStack {
                QuitButton()
                Spacer()
                Button("Save") { Task { await store.saveClient(id: clientId, secret: clientSecret) } }
                    .buttonStyle(.glassProminent)
                    .disabled(clientId.isEmpty || clientSecret.isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
    }
}

struct QuitButton: View {
    var body: some View {
        Button("Quit") { NSApp.terminate(nil) }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.callout)
    }
}
