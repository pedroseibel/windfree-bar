import Foundation

struct OAuthClient: Codable, Sendable {
    var clientId: String
    var clientSecret: String
    var redirectURI: String
}

struct TokenSet: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var installedAppId: String?
}

/// Owner-only JSON files in Application Support. The app is ad-hoc signed, so Keychain items
/// would re-prompt for access after every rebuild; 0600 files avoid that on a single-user Mac.
enum CredentialStore {
    static let directory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WindFreeBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return dir
    }()

    private static var clientURL: URL { directory.appendingPathComponent("oauth-client.json") }
    private static var tokensURL: URL { directory.appendingPathComponent("tokens.json") }
    private static var prefsURL: URL { directory.appendingPathComponent("prefs.json") }

    static func loadClient() -> OAuthClient? { read(clientURL) }
    static func saveClient(_ client: OAuthClient) throws { try write(client, to: clientURL) }

    static func loadTokens() -> TokenSet? { read(tokensURL) }
    static func saveTokens(_ tokens: TokenSet) throws { try write(tokens, to: tokensURL) }
    static func clearTokens() { try? FileManager.default.removeItem(at: tokensURL) }

    struct Prefs: Codable { var deviceId: String? }
    static func loadPrefs() -> Prefs { read(prefsURL) ?? Prefs() }
    static func savePrefs(_ prefs: Prefs) { try? write(prefs, to: prefsURL) }

    private static func read<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        let tmp = url.appendingPathExtension("tmp")
        FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600])
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }
}
