import SwiftUI
import MobileCore

@main
struct HerdrMobileApp: App {
    @State private var session: MobileSession
    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HerdrMobileFirstSlice", isDirectory: true)
        do {
            _session = State(initialValue: MobileSession(drafts: try DraftStore(file: root.appendingPathComponent("drafts-v1.json"))))
        } catch {
            _session = State(initialValue: MobileSession(drafts: nil, draftError: "초안 저장소를 열지 못했습니다. 기존 파일을 보존했습니다."))
        }
    }
    var body: some Scene {
        WindowGroup { RootView(session: session).tint(.indigo) }
    }
}
