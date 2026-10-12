import AppKit
import Foundation

enum AuthError: LocalizedError {
    case noClient
    case notSignedIn
    case cancelled
    case badCallback(String)
    case tokenEndpoint(Int, String)

    var errorDescription: String? {
        switch self {
        case .noClient: "No SmartThings OAuth client is configured."
        case .notSignedIn: "Sign in to SmartThings to continue."
        case .cancelled: "Sign-in was cancelled."
        case .badCallback(let detail): "SmartThings didn't return an authorization code (\(detail))."
        case .tokenEndpoint(let status, let body): "Token request failed (\(status)): \(body.prefix(200))"
        }
    }

    /// The refresh token is dead and only a new sign-in will fix it.
    var requiresSignIn: Bool {
        if case .tokenEndpoint(let status, let body) = self {
            return (status == 400 || status == 401) && body.contains("invalid_grant")
        }
        return false
    }
}

/// Authorization-code OAuth against SmartThings. Access tokens last 24 h and refresh tokens are
/// single-use (each refresh returns a new one), so every refresh is persisted immediately and
/// only one refresh is ever in flight.
actor TokenProvider {
    static let scopes = "r:devices:* x:devices:* r:locations:*"
    private static let tokenURL = URL(string: "https://api.smartthings.com/oauth/token")!
    /// Refresh well before expiry; an unused refresh token dies after ~29 days.
    private static let refreshMargin: TimeInterval = 6 * 3600

    private var tokens: TokenSet? = CredentialStore.loadTokens()
    private var refreshTask: Task<TokenSet, Error>?

    var isSignedIn: Bool { tokens != nil }

    /// Pass the token that just got a 401 to force a refresh; if another caller already
    /// refreshed it, the newer token is returned without spending the refresh token again.
    func accessToken(replacing rejected: String? = nil) async throws -> String {
        guard let current = tokens else { throw AuthError.notSignedIn }
        if let rejected, rejected != current.accessToken { return current.accessToken }
        if rejected == nil, current.expiresAt.timeIntervalSinceNow > Self.refreshMargin { return current.accessToken }
        return try await refresh(using: current).accessToken
    }

    func signIn() async throws {
        guard let client = CredentialStore.loadClient() else { throw AuthError.noClient }
        let code = try await BrowserAuthenticator.shared.authorize(client: client)
        tokens = try await requestTokens(client: client, form: [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": client.clientId,
            "redirect_uri": client.redirectURI,
        ])
    }

    func signOut() {
        tokens = nil
        CredentialStore.clearTokens()
    }

    private func refresh(using current: TokenSet) async throws -> TokenSet {
        if let refreshTask { return try await refreshTask.value }
        guard let client = CredentialStore.loadClient() else { throw AuthError.noClient }
        let task = Task {
            try await self.requestTokens(client: client, form: [
                "grant_type": "refresh_token",
                "client_id": client.clientId,
                "refresh_token": current.refreshToken,
            ])
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            tokens = fresh
            return fresh
        } catch let error as AuthError where error.requiresSignIn {
            signOut()
            throw error
        }
    }

    private func requestTokens(client: OAuthClient, form: [String: String]) async throws -> TokenSet {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        let basic = Data("\(client.clientId):\(client.clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.formEncoded.data(using: .utf8)

        let (data, response) = try await SmartThingsAPI.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw AuthError.tokenEndpoint(status, String(decoding: data, as: UTF8.self))
        }
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Double
            let installed_app_id: String?
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        let set = TokenSet(accessToken: r.access_token, refreshToken: r.refresh_token,
                           expiresAt: Date().addingTimeInterval(r.expires_in),
                           installedAppId: r.installed_app_id)
        try CredentialStore.saveTokens(set)
        return set
    }
}

/// Opens SmartThings' consent page in the user's own browser (their saved logins and password
/// manager work there) and waits for the `windfreebar://oauth?code=…&state=…` redirect, which
/// macOS routes back to the app through the URL scheme in Info.plist.
@MainActor
final class BrowserAuthenticator {
    static let shared = BrowserAuthenticator()

    private var pending: (state: String, scheme: String, continuation: CheckedContinuation<String, Error>)?

    func authorize(client: OAuthClient) async throws -> String {
        cancel()
        let state = UUID().uuidString
        var components = URLComponents(string: "https://api.smartthings.com/oauth/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: client.clientId),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: client.redirectURI),
            .init(name: "scope", value: TokenProvider.scopes),
            .init(name: "state", value: state),
        ]
        let scheme = URL(string: client.redirectURI)?.scheme ?? "windfreebar"
        return try await withCheckedThrowingContinuation { continuation in
            pending = (state, scheme, continuation)
            NSWorkspace.shared.open(components.url!)
        }
    }

    func cancel() {
        pending?.continuation.resume(throwing: AuthError.cancelled)
        pending = nil
    }

    func handle(_ url: URL) {
        guard let pending, url.scheme == pending.scheme else { return }
        self.pending = nil
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if item("state") != pending.state {
            pending.continuation.resume(throwing: AuthError.badCallback("state mismatch"))
        } else if let code = item("code") {
            pending.continuation.resume(returning: code)
        } else {
            pending.continuation.resume(throwing: AuthError.badCallback(item("error_description") ?? item("error") ?? "no code"))
        }
    }
}

extension Dictionary where Key == String, Value == String {
    var formEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\(value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&")
    }
}
