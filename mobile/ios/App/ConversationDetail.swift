import SwiftUI
import MobileCore

struct ConversationDetail: View {
    let session: MobileSession
    let conversation: Conversation
    let contextID: UUID
    @State private var text = ""
    @State private var capturedScope: DraftScope?
    @State private var lastSavedRevision = 0
    private var validTarget: Bool { session.contextID == contextID && session.current(conversation) != nil }
    var body: some View {
        VStack(spacing: 0) {
            ConnectionBanner(session: session).padding(.horizontal)
            if !validTarget {
                ContentUnavailableView("대화 대상이 바뀌었습니다", systemImage: "arrow.triangle.2.circlepath", description: Text("이전 초안은 원래 연결과 세션에 보존했습니다. 대화 목록에서 다시 열어 주세요."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        PhaseView(session: session)
                        let messages = session.snapshot.capabilities.readMessages ? session.snapshot.messages.filter { $0.conversationId == conversation.id } : []
                        if messages.isEmpty {
                            ContentUnavailableView(session.limitedHistory ? "대화 이력 연동 준비 중" : "대화를 시작해 보세요", systemImage: "bubble.left.and.bubble.right", description: Text(session.limitedHistory ? "팀 상태만 연결되었습니다. 대화가 없다는 뜻은 아닙니다." : session.isLocalDemo ? "DEMO 메시지는 기기 안에서만 접수됩니다." : "Fixture Relay가 DEMO 메시지만 접수합니다."))
                        }
                        ForEach(messages) { message in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(message.role == "user" ? "나" : session.snapshot.mode == "demo" ? "DEMO 에이전트" : "에이전트")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(message.text).textSelection(.enabled)
                                if message.state == "demo-accepted" {
                                    Text("DEMO 접수 · 에이전트 답변 아님").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.role == "user" ? Color.indigo.opacity(0.09) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }.padding()
                }
                VStack(alignment: .leading, spacing: 8) {
                    if let notice = session.notice { Text(notice).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("receipt-state") }
                    if let error = session.draftError { Text(error).font(.caption).foregroundStyle(.red) }
                    TextField("초안 작성", text: Binding(get: { text }, set: { value in
                        text = value
                        persistCurrentText()
                    }), axis: .vertical)
                        .lineLimit(2...6).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("conversation-draft")
                    HStack {
                        Text("\(text.unicodeScalars.count) / 4,000").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Button(session.submitting ? "접수 확인 중…" : "DEMO 보내기", systemImage: "paperplane") {
                            if persistCurrentText() {
                                Task { await session.sendDemo(conversation) }
                            }
                        }.buttonStyle(.borderedProminent)
                            .disabled(!session.canComposeDemo || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.unicodeScalars.count > 4_000 || session.draftError != nil)
                    }
                    if session.snapshot.mode != "demo" { Text("읽기 전용 · 초안은 보존되며 실제 전송과 승인은 지원하지 않습니다.").font(.caption).foregroundStyle(.secondary) }
                }.padding().background(.bar)
            }
        }.navigationTitle(conversation.title).navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if validTarget {
                    capturedScope = session.scope(conversation)
                    text = session.draft(conversation)
                    lastSavedRevision = session.draftRevision
                }
            }
            .onChange(of: session.draftRevision) { _, revision in
                if validTarget, capturedScope == session.scope(conversation), session.draft(conversation).isEmpty {
                    text = ""
                    lastSavedRevision = revision
                }
            }
            .onDisappear {
                if let capturedScope {
                    // Do not overwrite a newer send result or another connection's draft.
                    session.flushDraft(text, conversation: conversation, contextID: contextID,
                                       capturedScope: capturedScope, expectedRevision: lastSavedRevision)
                }
            }
    }

    @discardableResult
    private func persistCurrentText() -> Bool {
        guard let capturedScope else { return false }
        let saved = session.flushDraft(text, conversation: conversation, contextID: contextID, capturedScope: capturedScope)
        if saved { lastSavedRevision = session.draftRevision }
        return saved
    }
}
