import Foundation

struct DeviceSummary: Decodable, Identifiable, Hashable, Sendable {
    let deviceId: String
    let label: String?
    let name: String?
    var id: String { deviceId }
    var displayName: String { label ?? name ?? String(localized: "Air conditioner") }
}

struct DeviceCommand: Encodable, Sendable {
    var component = "main"
    let capability: String
    let command: String
    var arguments: [JSONValue] = []
}

/// `components.main.<capability>.<attribute>` → `{ value, unit }`
typealias DeviceStatus = [String: [String: [String: AttributeState]]]

struct AttributeState: Decodable, Sendable {
    let value: JSONValue?
    let unit: String?
}

enum APIError: LocalizedError {
    case http(Int, String)
    case rateLimited(until: Date)

    var errorDescription: String? {
        switch self {
        case .rateLimited: String(localized: "SmartThings is rate limiting requests. Retrying shortly.")
        case .http(402, _), .http(403, _): String(localized: "SmartThings refused the request. Your account may need an API plan.")
        case .http(let status, let body): String(localized: "SmartThings returned \(status): \(String(body.prefix(160)))")
        }
    }
}

/// Thin REST client. SmartThings allows 12 status reads and 12 commands per device per minute.
struct SmartThingsAPI: Sendable {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config)
    }()

    let tokens: TokenProvider
    private let base = URL(string: "https://api.smartthings.com/v1/")!

    func airConditioners() async throws -> [DeviceSummary] {
        struct Page: Decodable { let items: [DeviceSummary] }
        let data = try await send("devices?capability=airConditionerMode")
        return try JSONDecoder().decode(Page.self, from: data).items
    }

    func status(of deviceId: String) async throws -> DeviceStatus {
        struct Body: Decodable { let components: DeviceStatus }
        let data = try await send("devices/\(deviceId)/status")
        return try JSONDecoder().decode(Body.self, from: data).components
    }

    /// `/status` keeps returning the last known values when the unit drops off Wi-Fi; health doesn't.
    func isOnline(_ deviceId: String) async throws -> Bool {
        struct Health: Decodable { let state: String }
        let data = try await send("devices/\(deviceId)/health")
        return try JSONDecoder().decode(Health.self, from: data).state != "OFFLINE"
    }

    func execute(_ commands: [DeviceCommand], on deviceId: String) async throws {
        struct Body: Encodable { let commands: [DeviceCommand] }
        _ = try await send("devices/\(deviceId)/commands", method: "POST",
                           body: try JSONEncoder().encode(Body(commands: commands)))
    }

    private func send(_ path: String, method: String = "GET", body: Data? = nil, rejected: String? = nil) async throws -> Data {
        let token = try await tokens.accessToken(replacing: rejected)
        var request = URLRequest(url: URL(string: path, relativeTo: base)!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await Self.session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 401, rejected == nil {
            return try await send(path, method: method, body: body, rejected: token)
        }
        if status == 429 {
            throw APIError.rateLimited(until: Date().addingTimeInterval(Self.retryDelay(http)))
        }
        guard (200..<300).contains(status) else {
            throw APIError.http(status, String(decoding: data, as: UTF8.self))
        }
        return data
    }

    private static func retryDelay(_ response: HTTPURLResponse?) -> TimeInterval {
        if let after = response?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) { return after }
        if let reset = response?.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init) {
            // Documented as milliseconds until the window resets.
            return reset > 1000 ? reset / 1000 : reset
        }
        return 30
    }
}
