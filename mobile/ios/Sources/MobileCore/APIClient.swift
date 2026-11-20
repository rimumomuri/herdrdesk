import Foundation

public enum ClientError: Error, Equatable, LocalizedError {
    case invalidEndpoint, missingToken, unsupportedSchema, http(Int), tooLarge, invalidMessage, readOnly, staleTarget, invalidReceipt
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "HTTPS 루트 주소가 필요합니다. HTTP는 Simulator의 localhost만 허용됩니다."
        case .missingToken: return "페어링 토큰을 입력해 주세요."
        case .unsupportedSchema: return "지원하지 않는 API 버전 또는 모드입니다."
        case .http(let status): return "연결 요청 실패 (HTTP \(status)). 설정을 확인해 주세요."
        case .tooLarge: return "응답 크기 제한을 초과했습니다."
        case .invalidMessage: return "메시지는 4,000자, JSON 16KiB 이내로 입력해 주세요."
        case .readOnly: return "실연결은 읽기 전용입니다."
        case .staleTarget: return "대화 대상이 바뀌었습니다. 초안을 보존했습니다."
        case .invalidReceipt: return "접수 응답을 확인할 수 없습니다. 자동 재시도하지 않습니다."
        }
    }
}
public struct Endpoint: Hashable, Sendable {
    public let url: URL
    public var identity: String { url.absoluteString }
    public init(_ raw: String, simulator: Bool) throws {
        guard var parts = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              parts.scheme == "https" || (simulator && parts.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host))
        else { throw ClientError.invalidEndpoint }
        parts.scheme = parts.scheme?.lowercased(); parts.host = host.lowercased(); parts.path = ""
        guard let value = parts.url else { throw ClientError.invalidEndpoint }
        url = value
    }
    public static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
public struct APIClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)
    public let endpoint: Endpoint
    private let token: String
    private let transport: Transport
    public init(endpoint: Endpoint, token: String, transport: @escaping Transport = { request in try await APIClient.network(request) }) {
        self.endpoint = endpoint; self.token = token; self.transport = transport
    }
    private func request(path: String, body: Data? = nil) async throws -> Data {
        guard !token.isEmpty, !token.contains("\r"), !token.contains("\n") else { throw ClientError.missingToken }
        var request = URLRequest(url: endpoint.url.appendingPathComponent(path))
        request.httpMethod = body == nil ? "GET" : "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        // Exactly one invocation: no retry on timeout, stale target or HTTP error.
        let (data, status) = try await transport(request)
        guard (200..<300).contains(status) else { throw ClientError.http(status) }
        guard data.count <= 2_000_000 else { throw ClientError.tooLarge }
        return data
    }
    public func snapshot() async throws -> Snapshot { try Snapshot.decode(await request(path: "v1/snapshot")) }
    public func submitDemo(_ message: MessageSubmission, snapshot: Snapshot) async throws -> Receipt {
        guard snapshot.mode == "demo", snapshot.capabilities.sendMessages else { throw ClientError.readOnly }
        guard snapshot.conversations.contains(where: {
            $0.id == message.conversationId && $0.address == message.address && $0.session == message.session && $0.role == message.role
        }) else { throw ClientError.staleTarget }
        let data = try await request(path: "v1/messages", body: JSONEncoder().encode(message))
        let receipt = try JSONDecoder().decode(Receipt.self, from: data)
        guard receipt.id == message.id, receipt.mode == "demo", receipt.state == "demo-accepted" else { throw ClientError.invalidReceipt }
        return receipt
    }
    public static func network(_ request: URLRequest) async throws -> (Data, Int) {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        let delegate = BoundedSession()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ClientError.http(0) }
        guard response.expectedContentLength <= 2_000_000 else { throw ClientError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2_000_000 else { throw ClientError.tooLarge }
            data.append(byte)
        }
        return (data, response.statusCode)
    }
}
// Never forward a bearer token through a redirect or fall back to HTTP.
private final class BoundedSession: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
