import SwiftUI
import UIKit
import MobileCore

struct RootView: View {
    private enum Tab: Hashable { case teams, conversations, tasks, settings }
    @State private var selectedTab: Tab = .teams
    let session: MobileSession
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { TeamsView(session: session) }
                .id("teams-\(session.contextID)")
                .tabItem { Label("팀", systemImage: "person.3") }
                .tag(Tab.teams)
            NavigationStack { ConversationsView(session: session, teamID: nil) }
                .id("conversations-\(session.contextID)")
                .tabItem { Label("대화", systemImage: "bubble.left.and.bubble.right") }
                .tag(Tab.conversations)
            NavigationStack { TasksView(session: session) }
                .id("tasks-\(session.contextID)")
                .tabItem { Label("작업", systemImage: "checklist") }
                .tag(Tab.tasks)
            NavigationStack { SettingsView(session: session) }
                .tabItem { Label("설정", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
    }
}

struct ConnectionBanner: View {
    let session: MobileSession
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(session.modeLabel, systemImage: session.isLocalDemo ? "testtube.2" : "network")
                .font(.subheadline.weight(.semibold))
            Text(session.isLocalDemo ? "기기 안의 예시입니다. 실제 메시지는 전송되지 않습니다." : session.snapshot.mode == "demo" ? "Fixture Relay · DEMO 접수만 체험하며 실제 에이전트로 전송하지 않습니다." : session.limitedHistory ? "팀 상태만 연결됨 · 대화와 작업 이력은 연동 준비 중" : "수동 새로고침 · 메시지 전송과 런타임 승인 미지원")
                .font(.caption).foregroundStyle(.secondary)
            if !session.isLocalDemo {
                Text(session.isReady ? "Relay 연결됨 · 에이전트 응답 완료와 별개" : "Relay 연결 미확인 · 이전 목록이 남을 수 있습니다")
                    .font(.caption).foregroundStyle(session.isReady ? .green : .orange)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
    }
}

struct PhaseView: View {
    let session: MobileSession
    var body: some View {
        switch session.phase {
        case .loading:
            HStack { ProgressView(); Text("팀 상태를 불러오는 중…") }.padding(.vertical)
        case .offline:
            VStack(alignment: .leading, spacing: 10) {
                Label("오프라인", systemImage: "wifi.slash").font(.headline)
                Text("네트워크와 Relay 실행 상태를 확인해 주세요. 초안은 보존됩니다.").font(.subheadline)
                Button("다시 연결") { Task { await session.refresh() } }
            }.padding(.vertical)
        case .failed(let description):
            VStack(alignment: .leading, spacing: 10) {
                Label("연결 오류", systemImage: "exclamationmark.triangle").font(.headline)
                Text(description).font(.subheadline)
                Button("다시 시도") { Task { await session.refresh() } }
            }.padding(.vertical)
        case .ready: EmptyView()
        }
    }
}

// Cache the six original 512px cells once; UIKit also decodes Xcode-optimized PNGs.
@MainActor
private enum SheepImages {
    private static let cells: [UIImage?] = {
        guard let url = Bundle.main.url(forResource: "sheep-minimal-v5", withExtension: "png"),
              let atlas = UIImage(contentsOfFile: url.path)?.cgImage,
              atlas.width == 1536, atlas.height == 1024 else { return Array(repeating: nil, count: 6) }
        return (0..<6).map { index in
            let rect = CGRect(x: CGFloat((index % 3) * 512), y: CGFloat((index / 3) * 512), width: 512, height: 512)
            guard let cell = atlas.cropping(to: rect) else { return nil }
            return UIImage(cgImage: cell, scale: 1, orientation: .up)
        }
    }()

    static func image(row: Int, column: Int) -> UIImage? {
        guard (0..<2).contains(row), (0..<3).contains(column) else { return nil }
        return cells[row * 3 + column]
    }
}

struct SheepAvatar: View {
    var provider = "codex"
    var status = "working"
    var size: CGFloat = 52
    private var sleeping: Bool { ["sleeping", "idle", "waiting"].contains(status) }
    var body: some View {
        let frame = SheepAtlas(provider: provider, status: status)
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image = SheepImages.image(row: frame.row, column: frame.column) {
                    Image(uiImage: image).renderingMode(.original)
                        .resizable().scaledToFit()
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "photo.badge.exclamationmark")
                        Text("이미지 없음").font(.system(size: 8))
                    }.foregroundStyle(.secondary)
                        .accessibilityLabel("양 이미지 로드 실패")
                }
            }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 14))
            Image(systemName: sleeping ? "moon.zzz.fill" : status == "working" ? "hammer.fill" : "circle.fill")
                .font(.system(size: 11, weight: .bold)).padding(4)
                .background(.background, in: Circle()).foregroundStyle(sleeping ? Color.secondary : Color.indigo)
        }.accessibilityLabel("\(provider), \(statusLabel(status))")
    }
}

func statusLabel(_ state: String) -> String {
    switch state {
    case "working": return "작업 중"
    case "sleeping", "idle": return "쉬는 중"
    case "waiting": return "대기"
    case "blocked": return "막힘"
    case "needs-user": return "사용자 확인 필요"
    case "done", "complete", "completed": return "완료"
    case "queued": return "예정"
    default: return state
    }
}

struct TeamsView: View {
    let session: MobileSession
    var body: some View {
        List {
            Section { ConnectionBanner(session: session); PhaseView(session: session) }
            ForEach(session.snapshot.teams) { team in
                Section {
                    NavigationLink {
                        ConversationsView(session: session, teamID: team.id)
                    } label: {
                        Label("팀 대화 보기", systemImage: "bubble.left.and.bubble.right")
                    }
                    ForEach(session.snapshot.agents.filter { $0.teamId == team.id }) { agent in
                        HStack(spacing: 12) {
                            SheepAvatar(provider: agent.provider, status: agent.status)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(agent.name).font(.headline)
                                Text(agent.role).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(statusLabel(agent.status)).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                } header: { Text("\(team.title) · \(team.memberCount)명") }
            }
            if session.snapshot.teams.isEmpty && session.isReady {
                ContentUnavailableView("연결된 팀이 없습니다", systemImage: "person.3", description: Text("설정에서 연결 주소를 확인해 주세요."))
            }
        }.navigationTitle("팀")
            .toolbar { if !session.isLocalDemo { Button("새로고침", systemImage: "arrow.clockwise") { Task { await session.refresh() } }.disabled(session.phase == .loading) } }
    }
}

struct ConversationsView: View {
    let session: MobileSession
    let teamID: String?
    private var conversations: [Conversation] { session.snapshot.conversations.filter { teamID == nil || $0.teamId == teamID } }
    var body: some View {
        List {
            Section { ConnectionBanner(session: session); PhaseView(session: session) }
            ForEach(["group", "direct"], id: \.self) { kind in
                let rows = conversations.filter { $0.kind == kind }
                Section(kind == "group" ? "그룹 대화" : "개인 대화") {
                    if rows.isEmpty {
                        Text(session.limitedHistory ? "팀 상태만 연결됨 · 대화 이력 연동 준비 중" : "아직 대화가 없습니다.")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    ForEach(rows) { conversation in
                        NavigationLink(value: conversation) {
                            HStack(spacing: 12) {
                                Image(systemName: kind == "group" ? "person.2.fill" : "bubble.left.fill").foregroundStyle(.indigo)
                                Text(conversation.title)
                                Spacer()
                                if conversation.unreadCount > 0 { Text("\(conversation.unreadCount)").font(.caption.monospacedDigit()).foregroundStyle(.white).padding(6).background(.indigo, in: Circle()) }
                            }.padding(.vertical, 8)
                        }
                    }
                }
            }
        }.navigationTitle("대화")
            .navigationDestination(for: Conversation.self) { ConversationDetail(session: session, conversation: $0, contextID: session.contextID) }
    }
}

struct TasksView: View {
    let session: MobileSession
    var body: some View {
        List {
            Section { ConnectionBanner(session: session); PhaseView(session: session) }
            if session.snapshot.tasks.isEmpty {
                ContentUnavailableView(session.limitedHistory ? "작업 이력 연동 준비 중" : "등록된 작업이 없습니다", systemImage: "checklist", description: Text(session.limitedHistory ? "팀 상태만 연결되었습니다. 실제 작업 수를 의미하지 않습니다." : "팀에서 배분한 작업이 여기에 표시됩니다."))
            }
            ForEach(session.snapshot.tasks) { task in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(task.id).font(.caption.monospaced()).foregroundStyle(.secondary); Spacer(); Text(statusLabel(task.state)).font(.caption.weight(.semibold)) }
                    Text(task.title).font(.headline)
                    Text(task.owner).font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            }
        }.navigationTitle("작업")
    }
}
