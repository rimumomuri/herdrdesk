import Foundation

public extension Snapshot {
    static var demo: Snapshot {
        Snapshot(schemaVersion: 1, mode: "demo", connection: "offline", capabilities: Capabilities(readMessages: true, sendMessages: true, runtimeApproval: false),
                 teams: [Team(id: "demo-desk", title: "HerdrDesk", memberCount: 2)],
                 agents: [Agent(address: "demo-lead", session: "demo:1", role: "lead", teamId: "demo-desk", name: "제작 총괄", provider: "codex", status: "working"), Agent(address: "demo-review", session: "demo:2", role: "review", teamId: "demo-desk", name: "검토 담당", provider: "claude", status: "sleeping")],
                 conversations: [Conversation(id: "group:demo", title: "팀 대화", kind: "group", teamId: "demo-desk", address: "demo-lead", session: "demo:1", role: "lead", unreadCount: 0), Conversation(id: "direct:demo-lead", title: "제작 총괄", kind: "direct", teamId: "demo-desk", address: "demo-lead", session: "demo:1", role: "lead", unreadCount: 1), Conversation(id: "direct:demo-review", title: "검토 담당", kind: "direct", teamId: "demo-desk", address: "demo-review", session: "demo:2", role: "review", unreadCount: 0)],
                 messages: [Message(id: "demo-welcome", conversationId: "group:demo", role: "assistant", text: "아이폰에서 팀과 작업을 확인하세요. 이 대화는 합성 DEMO입니다.", createdAt: "2026-11-20T00:00:00Z", state: "received")],
                 tasks: [TaskItem(id: "DEMO-01", teamId: "demo-desk", title: "아이폰 첫 개발본 만들기", state: "working", owner: "제작 총괄"), TaskItem(id: "DEMO-02", teamId: "demo-desk", title: "첫 화면 검토 기다리기", state: "waiting", owner: "검토 담당")])
    }
}
