import Foundation
import Observation

public enum LoadPhase: Equatable {
    case loading, ready, offline, failed(String)
}

@MainActor @Observable
public final class MobileSession {
    public private(set) var snapshot = Snapshot.demo
    public private(set) var phase: LoadPhase = .ready
    public private(set) var contextID = UUID()
    public private(set) var endpointIdentity = "local-demo"
    public private(set) var isLocalDemo = true
    public private(set) var notice: String?
    public private(set) var draftRevision = 0
    public private(set) var draftError: String?
    public private(set) var submitting = false
    @ObservationIgnored private var submissionID: UUID?
    @ObservationIgnored private let drafts: DraftStore?
    @ObservationIgnored private var client: APIClient?
    @ObservationIgnored private var generation = UUID()

    public init(drafts: DraftStore?, draftError: String? = nil) {
        self.drafts = drafts; self.draftError = draftError
    }
    public var modeLabel: String {
        isLocalDemo ? "DEMO · 합성 데이터" : snapshot.mode == "demo" ? "RELAY DEMO · 합성 데이터" : "실연결 · 읽기 전용"
    }
    public var limitedHistory: Bool { !isLocalDemo && (snapshot.mode == "live-readonly" || !snapshot.capabilities.readMessages) }
    public var canComposeDemo: Bool { snapshot.mode == "demo" && snapshot.capabilities.sendMessages && phase == .ready && !submitting }
    public var isReady: Bool { phase == .ready }
    public func useDemo() {
        generation = UUID(); contextID = UUID(); client = nil; submissionID = nil; submitting = false
        endpointIdentity = "local-demo"; isLocalDemo = true
        snapshot = .demo; phase = .ready; notice = nil
    }
    public func connect(client: APIClient) async {
        generation = UUID(); contextID = UUID(); self.client = client; submissionID = nil; submitting = false
        endpointIdentity = client.endpoint.identity; isLocalDemo = false
        snapshot = Snapshot(schemaVersion: 1, mode: "live-readonly", connection: "offline", capabilities: Capabilities(readMessages: false, sendMessages: false, runtimeApproval: false), teams: [], agents: [], conversations: [], messages: [], tasks: [])
        notice = nil
        await refresh()
    }
    public func refresh() async {
        guard let client else { return }
        let requestGeneration = UUID(); generation = requestGeneration
        phase = .loading; notice = nil
        do {
            let result = try await client.snapshot()
            guard generation == requestGeneration else { return }
            snapshot = result
            phase = result.connection == "live" ? .ready : .offline
        } catch {
            guard generation == requestGeneration else { return }
            if let urlError = error as? URLError, [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .timedOut].contains(urlError.code) {
                phase = .offline
            } else {
                // Never display raw server bodies, endpoint credentials or arbitrary transport errors.
                phase = .failed((error as? ClientError)?.localizedDescription ?? "연결을 확인할 수 없습니다. 설정을 확인해 주세요.")
            }
        }
    }
    public func current(_ conversation: Conversation) -> Conversation? {
        snapshot.conversations.first { $0 == conversation }
            ?? snapshot.conversations.first { $0.id == conversation.id && $0.address == conversation.address && $0.session == conversation.session && $0.role == conversation.role }
    }
    public func scope(_ conversation: Conversation) -> DraftScope {
        DraftScope(endpoint: endpointIdentity, mode: isLocalDemo ? "local-demo" : snapshot.mode, conversation: conversation.id, address: conversation.address, session: conversation.session, role: conversation.role)
    }
    public func draft(_ conversation: Conversation) -> String {
        _ = draftRevision
        return drafts?.text(for: scope(conversation)) ?? ""
    }
    public func setDraft(_ text: String, conversation: Conversation) {
        guard let drafts else { draftError = "초안 저장소를 열 수 없습니다. 기존 파일을 보존했습니다."; return }
        do { try drafts.save(text, for: scope(conversation)); draftRevision += 1; draftError = nil }
        catch { draftError = "초안을 저장하지 못했습니다. 저장 공간과 잠금 상태를 확인해 주세요." }
    }
    @discardableResult
    public func flushDraft(_ text: String, conversation: Conversation, contextID: UUID, capturedScope: DraftScope, expectedRevision: Int? = nil) -> Bool {
        guard self.contextID == contextID, current(conversation) != nil,
              scope(conversation) == capturedScope,
              expectedRevision == nil || expectedRevision == draftRevision else { return false }
        setDraft(text, conversation: conversation)
        return draftError == nil
    }
    public func sendDemo(_ conversation: Conversation) async {
        guard !submitting else { return }
        guard canComposeDemo, current(conversation) != nil else { notice = "대상 또는 연결이 바뀌었습니다. 초안을 보존했습니다."; return }
        if isLocalDemo { simulate(conversation); return }
        guard let client else { return }
        let context = contextID
        let originalScope = scope(conversation)
        let originalText = draft(conversation)
        let operation = UUID()
        submissionID = operation; submitting = true; notice = nil
        defer {
            if submissionID == operation { submissionID = nil; submitting = false }
        }
        do {
            let message = try MessageSubmission(conversation: conversation, text: originalText)
            let receipt = try await client.submitDemo(message, snapshot: snapshot)
            guard contextID == context, scope(conversation) == originalScope,
                  current(conversation) != nil, snapshot.mode == "demo" else { return }
            snapshot.messages.append(Message(id: message.id, conversationId: message.conversationId, role: "user", text: message.text, createdAt: ISO8601DateFormatter().string(from: Date()), state: receipt.state))
            notice = receipt.displayState
            if draft(conversation) == originalText { setDraft("", conversation: conversation) }
        } catch {
            guard contextID == context, scope(conversation) == originalScope, current(conversation) != nil else { return }
            if let problem = error as? ClientError {
                notice = problem.localizedDescription + " 초안을 보존했습니다."
            } else {
                notice = "전송 상태 미확인 · 자동 재시도 없음. 초안을 보존했습니다."
            }
        }
    }
    public func simulate(_ conversation: Conversation) {
        guard isLocalDemo, canComposeDemo, current(conversation) != nil else { notice = "대상 또는 연결이 바뀌었습니다. 초안을 보존했습니다."; return }
        do {
            let message = try MessageSubmission(conversation: conversation, text: draft(conversation))
            // Local simulation only. No API POST and no synthetic assistant response.
            snapshot.messages.append(Message(id: message.id, conversationId: message.conversationId, role: "user", text: message.text, createdAt: ISO8601DateFormatter().string(from: Date()), state: "demo-accepted"))
            notice = Receipt(id: message.id, state: "demo-accepted", mode: "demo").displayState
            setDraft("", conversation: conversation)
        } catch { notice = ClientError.invalidMessage.localizedDescription }
    }
}
