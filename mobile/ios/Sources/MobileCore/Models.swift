import Foundation

public struct Snapshot: Codable, Sendable {
    public var schemaVersion: Int
    public var mode: String
    public var connection: String
    public var capabilities: Capabilities
    public var teams: [Team]
    public var agents: [Agent]
    public var conversations: [Conversation]
    public var messages: [Message]
    public var tasks: [TaskItem]

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 2_000_000 else { throw ClientError.tooLarge }
        let result = try JSONDecoder().decode(Self.self, from: data)
        guard result.schemaVersion == 1, ["demo", "live-readonly", "live"].contains(result.mode) else { throw ClientError.unsupportedSchema }
        return result
    }
}
public struct Capabilities: Codable, Sendable {
    public var readMessages: Bool
    public var sendMessages: Bool
    public var runtimeApproval: Bool
}
public struct Team: Codable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var memberCount: Int
}
public struct Agent: Codable, Identifiable, Sendable {
    public var id: String { address + ":" + session }
    public var address: String
    public var session: String
    public var role: String
    public var teamId: String
    public var name: String
    public var provider: String
    public var status: String
}
public struct Conversation: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var kind: String
    public var teamId: String
    public var address: String
    public var session: String
    public var role: String
    public var unreadCount: Int
}
public struct Message: Codable, Identifiable, Sendable {
    public var id: String
    public var conversationId: String
    public var role: String
    public var text: String
    public var createdAt: String
    public var state: String
    public init(id: String, conversationId: String, role: String, text: String, createdAt: String, state: String) {
        self.id = id; self.conversationId = conversationId; self.role = role; self.text = text; self.createdAt = createdAt; self.state = state
    }
}
public struct TaskItem: Codable, Identifiable, Sendable {
    public var id: String
    public var teamId: String
    public var title: String
    public var state: String
    public var owner: String
}
public struct MessageSubmission: Codable, Sendable {
    public let id: String
    public let conversationId: String
    public let address: String
    public let session: String
    public let role: String
    public let text: String
    public init(conversation: Conversation, text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.unicodeScalars.count <= 4_000 else { throw ClientError.invalidMessage }
        id = UUID().uuidString.lowercased()
        conversationId = conversation.id; address = conversation.address
        session = conversation.session; role = conversation.role; self.text = text
        guard try JSONEncoder().encode(self).count <= 16_384 else { throw ClientError.invalidMessage }
    }
}
public struct Receipt: Codable, Sendable {
    public let id: String
    public let state: String
    public let mode: String
    public init(id: String, state: String, mode: String) { self.id = id; self.state = state; self.mode = mode }
    public var displayState: String {
        mode == "demo" && state == "demo-accepted" ? "DEMO 접수 · 에이전트 답변 아님" : "전송 상태 미확인 · 자동 재시도 없음"
    }
}
