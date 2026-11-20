import SwiftUI
import MobileCore

struct SettingsView: View {
    let session: MobileSession
    @AppStorage("firstslice.relay.root") private var address = ""
    @State private var token = ""
    @State private var error: String?
    @State private var connecting = false

    var body: some View {
        Form {
            Section { ConnectionBanner(session: session); PhaseView(session: session) }
            Section("연결 모드") {
                Button("DEMO 보기 · 네트워크 사용 안 함") { session.useDemo(); error = nil; token = "" }
                    .disabled(connecting)
                Text("DEMO의 팀·대화·작업과 메시지는 모두 합성 예시입니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Mac Relay · 명시적 읽기 연결") {
                TextField("https://relay.example", text: $address)
                    .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("relay-address")
                SecureField("페어링 토큰", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .privacySensitive().accessibilityIdentifier("pairing-token")
                Button("토큰 저장 후 읽기 연결") { Task { await connect(useSavedToken: false) } }
                    .disabled(connecting || token.isEmpty || address.isEmpty)
                Button("저장된 토큰으로 읽기 연결") { Task { await connect(useSavedToken: true) } }
                    .disabled(connecting || address.isEmpty)
                if connecting { ProgressView("연결 확인 중…") }
                if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
                Text("토큰은 이 앱 전용 Keychain에 저장합니다. HTTPS가 필요하며 Simulator의 localhost 개발만 HTTP를 허용합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("첫 개발본의 범위") {
                Label("수동 새로고침으로 팀 상태 조회", systemImage: "arrow.clockwise")
                Label("실제 메시지 전송 미지원", systemImage: "paperplane.circle")
                Label("런타임 승인 미지원", systemImage: "lock.shield")
                Text("연결 또는 세션이 바뀌면 초안을 분리합니다. 타임아웃 뒤 자동 재전송하지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("연결 설정")
    }

    @MainActor private func connect(useSavedToken: Bool) async {
        connecting = true; error = nil
        defer { connecting = false }
        do {
            let endpoint = try Endpoint(address, simulator: Endpoint.isSimulator)
            let vault = TokenVault()
            let secret: String
            if useSavedToken {
                guard let saved = try vault.load(endpoint: endpoint), !saved.isEmpty else { throw ClientError.missingToken }
                secret = saved
            } else {
                guard !token.isEmpty, !token.contains("\r"), !token.contains("\n") else { throw ClientError.missingToken }
                try vault.save(token, endpoint: endpoint)
                secret = token
            }
            token = ""
            await session.connect(client: APIClient(endpoint: endpoint, token: secret))
        } catch let problem as ClientError { error = problem.localizedDescription }
        catch VaultError.unavailable(let status) {
            #if DEBUG
            self.error = "Keychain 저장/조회 실패 (OSStatus \(status)). 연결 요청은 보내지 않았습니다."
            #else
            self.error = "Keychain을 열 수 없습니다. 연결 요청은 보내지 않았습니다."
            #endif
        }
        catch { self.error = "Keychain을 열 수 없습니다. 기기 잠금을 확인해 주세요." }
    }
}
