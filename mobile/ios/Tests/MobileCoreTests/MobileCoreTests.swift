import XCTest
import Security
@testable import MobileCore

final class MobileCoreTests: XCTestCase {
    func testHTTPIsRestrictedToExplicitSimulatorLoopback() throws {
        for url in ["http://example.com", "http://127.0.0.1.evil.test", "http://192.168.0.1", "https://user:pass@example.com", "https://example.com/?token=x", "https://example.com/path"] {
            XCTAssertThrowsError(try Endpoint(url, simulator: true))
        }
        XCTAssertThrowsError(try Endpoint("http://localhost:8765", simulator: false))
        XCTAssertEqual(try Endpoint("http://127.0.0.1:8765", simulator: true).identity, "http://127.0.0.1:8765")
        XCTAssertEqual(try Endpoint("https://example.com/", simulator: false).identity, "https://example.com")
    }

    func testContractDecodesAndRejectsUnsupportedVersion() throws {
        let value = try Snapshot.decode(Data(Self.fixture.utf8))
        XCTAssertEqual(value.conversations.first?.session, "100:1")
        XCTAssertEqual(value.messages.first?.state, "received")
        for mode in ["live-readonly", "live"] {
            XCTAssertEqual(try Snapshot.decode(Data(Self.fixture.replacingOccurrences(of: #""mode":"demo""#, with: "\"mode\":\"\(mode)\"").utf8)).mode, mode)
        }
        XCTAssertThrowsError(try Snapshot.decode(Data(Self.fixture.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2").utf8)))
        XCTAssertThrowsError(try Snapshot.decode(Data(Self.fixture.replacingOccurrences(of: "\"mode\":\"demo\"", with: "\"mode\":\"unknown\"").utf8)))
    }

    func testDraftSurvivesRestartAndIsolatesEndpointConversationSessionAndRole() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = root.appendingPathComponent("drafts.json")
        let scope = DraftScope(endpoint: "https://one.test", mode: "live", conversation: "direct:a", address: "a", session: "100:1", role: "lead")
        let store = try DraftStore(file: file)
        try store.save("보존할 초안", for: scope)
        XCTAssertEqual(try DraftStore(file: file).text(for: scope), "보존할 초안")
        for other in [
            DraftScope(endpoint: "https://two.test", mode: "live", conversation: "direct:a", address: "a", session: "100:1", role: "lead"),
            DraftScope(endpoint: "https://one.test", mode: "live", conversation: "group:a", address: "a", session: "100:1", role: "lead"),
            DraftScope(endpoint: "https://one.test", mode: "live", conversation: "direct:a", address: "a", session: "100:2", role: "lead"),
            DraftScope(endpoint: "https://one.test", mode: "demo", conversation: "direct:a", address: "a", session: "100:1", role: "lead"),
            DraftScope(endpoint: "https://one.test", mode: "live", conversation: "direct:a", address: "a", session: "100:1", role: "worker")
        ] { XCTAssertEqual(store.text(for: other), "") }
    }

    func testRequestIncludesBearerAndOnlyReadsSnapshot() async throws {
        let endpoint = try Endpoint("https://relay.test", simulator: false)
        let client = APIClient(endpoint: endpoint, token: "synthetic-test-only") { request in
            XCTAssertEqual(request.url?.absoluteString, "https://relay.test/v1/snapshot")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-only")
            return (Data(Self.fixture.utf8), 200)
        }
        let snapshot = try await client.snapshot()
        XCTAssertEqual(snapshot.teams.first?.id, "herdrdesk")
    }

    func testHTTPFailureAndTimeoutNeverRetry() async throws {
        let count = Counter()
        let endpoint = try Endpoint("https://relay.test", simulator: false)
        let client = APIClient(endpoint: endpoint, token: "synthetic") { _ in
            await count.increment()
            throw URLError(.timedOut)
        }
        do { _ = try await client.snapshot(); XCTFail("Timeout should surface") } catch {}
        let calls = await count.value
        XCTAssertEqual(calls, 1)
        let unauthorized = APIClient(endpoint: endpoint, token: "synthetic") { _ in (Data(), 401) }
        do { _ = try await unauthorized.snapshot(); XCTFail("401 should fail") }
        catch { XCTAssertEqual(error as? ClientError, .http(401)) }
    }

    func testMessageUUIDAndAcknowledgementDoNotBecomeAssistantReply() throws {
        let snapshot = try Snapshot.decode(Data(Self.fixture.utf8))
        let conversation = try XCTUnwrap(snapshot.conversations.first)
        let first = try MessageSubmission(conversation: conversation, text: "합성 초안")
        let second = try MessageSubmission(conversation: conversation, text: "합성 초안")
        XCTAssertNotNil(UUID(uuidString: first.id))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.session, "100:1")
        XCTAssertEqual(first.id, first.id.lowercased())
        XCTAssertNoThrow(try MessageSubmission(conversation: conversation, text: String(repeating: "가", count: 4000)))
        XCTAssertThrowsError(try MessageSubmission(conversation: conversation, text: String(repeating: "a", count: 4001)))
        XCTAssertThrowsError(try MessageSubmission(conversation: conversation, text: String(repeating: "\u{0001}", count: 4000)))
        XCTAssertEqual(Receipt(id: first.id, state: "demo-accepted", mode: "demo").displayState, "DEMO 접수 · 에이전트 답변 아님")
        XCTAssertThrowsError(try MessageSubmission(conversation: conversation, text: "  \n"))
    }

    func testAtlasUsesClaudeAliasesAndSleepingColumn() {
        XCTAssertEqual(SheepAtlas(provider: "claude-code", status: "working").row, 1)
        XCTAssertEqual(SheepAtlas(provider: "claude", status: "sleeping").row, 1)
        XCTAssertEqual(SheepAtlas(provider: "codex", status: "working").row, 0)
        XCTAssertEqual(SheepAtlas(provider: "codex", status: "sleeping").column, 1)
        XCTAssertEqual(SheepAtlas(provider: "codex", status: "working").column, 0)
    }

    func testOversizedAndEmptyTokenAreRejected() async throws {
        let endpoint = try Endpoint("https://relay.test", simulator: false)
        let empty = APIClient(endpoint: endpoint, token: "") { _ in
            XCTFail("Missing token must never reach transport")
            return (Data(), 200)
        }
        do { _ = try await empty.snapshot(); XCTFail("Missing token should fail") }
        catch { XCTAssertEqual(error as? ClientError, .missingToken) }
        let oversized = APIClient(endpoint: endpoint, token: "synthetic") { _ in (Data(repeating: 32, count: 2_000_001), 200) }
        do { _ = try await oversized.snapshot(); XCTFail("Oversize should fail") }
        catch { XCTAssertEqual(error as? ClientError, .tooLarge) }
    }

    func testDemoPOSTRejectsLiveAndStaleTargetsBeforeTransport() async throws {
        let client = APIClient(endpoint: try Endpoint("https://relay.test", simulator: false), token: "synthetic") { _ in
            XCTFail("Live/stale submission must not reach transport")
            return (Data(), 200)
        }
        var snapshot = try Snapshot.decode(Data(Self.fixture.utf8))
        let message = try MessageSubmission(conversation: XCTUnwrap(snapshot.conversations.first), text: "합성")
        snapshot.mode = "live-readonly"
        do { _ = try await client.submitDemo(message, snapshot: snapshot); XCTFail("Live must be read only") }
        catch { XCTAssertEqual(error as? ClientError, .readOnly) }
        snapshot.mode = "demo"
        snapshot.conversations[0].session = "100:2"
        do { _ = try await client.submitDemo(message, snapshot: snapshot); XCTFail("Stale session must fail") }
        catch { XCTAssertEqual(error as? ClientError, .staleTarget) }
    }

    func testCorruptDraftFileIsNotOverwritten() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("broken draft storage".utf8).write(to: file)
        XCTAssertThrowsError(try DraftStore(file: file))
        XCTAssertEqual(try String(contentsOf: file), "broken draft storage")
    }

    @MainActor func testDemoSendKeepsReceiptSeparateAndLiveConnectDisablesSend() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = MobileSession(drafts: try DraftStore(file: file))
        let conversation = try XCTUnwrap(session.snapshot.conversations.first)
        session.setDraft("합성 메시지", conversation: conversation)
        session.simulate(conversation)
        XCTAssertEqual(session.snapshot.messages.last?.role, "user")
        XCTAssertEqual(session.snapshot.messages.last?.state, "demo-accepted")
        XCTAssertEqual(session.draft(conversation), "")
        session.setDraft("남길 초안", conversation: conversation)
        let client = APIClient(endpoint: try Endpoint("https://relay.test", simulator: false), token: "synthetic") { _ in
            throw URLError(.notConnectedToInternet)
        }
        await session.connect(client: client)
        XCTAssertEqual(session.phase, .offline)
        XCTAssertFalse(session.canComposeDemo)
        XCTAssertTrue(session.snapshot.messages.isEmpty)
        XCTAssertEqual(session.draft(conversation), "")
        session.useDemo()
        XCTAssertEqual(session.draft(conversation), "남길 초안")
    }

    @MainActor func testLateSnapshotCannotReplaceNewConnectionMode() async throws {
        let gate = SnapshotGate()
        let session = MobileSession(drafts: nil)
        let client = APIClient(endpoint: try Endpoint("https://relay.test", simulator: false), token: "synthetic") { _ in
            await gate.wait()
            return (Data(Self.fixture.utf8), 200)
        }
        let pending = Task { await session.connect(client: client) }
        await gate.waitUntilStarted()
        XCTAssertEqual(session.phase, .loading)
        session.useDemo()
        await gate.release()
        await pending.value
        XCTAssertTrue(session.isLocalDemo)
        XCTAssertEqual(session.endpointIdentity, "local-demo")
        XCTAssertEqual(session.snapshot.teams.first?.id, "demo-desk")
    }

    @MainActor func testRelayDemoPostProducesOnlyUserReceipt() async throws {
        let posts = Counter()
        let session = MobileSession(drafts: try DraftStore(file: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let client = APIClient(endpoint: try Endpoint("https://relay.test", simulator: false), token: "synthetic") { request in
            if request.httpMethod == "GET" { return (Data(Self.fixture.utf8), 200) }
            await posts.increment()
            XCTAssertEqual(request.url?.path, "/v1/messages")
            let sent = try JSONDecoder().decode(MessageSubmission.self, from: XCTUnwrap(request.httpBody))
            XCTAssertEqual(sent.text, "합성 Relay 메시지")
            return (try JSONEncoder().encode(Receipt(id: sent.id, state: "demo-accepted", mode: "demo")), 200)
        }
        await session.connect(client: client)
        XCTAssertTrue(session.canComposeDemo)
        let conversation = try XCTUnwrap(session.snapshot.conversations.first)
        session.setDraft("합성 Relay 메시지", conversation: conversation)
        await session.sendDemo(conversation)
        let count = await posts.value
        XCTAssertEqual(count, 1)
        XCTAssertEqual(session.snapshot.messages.filter { $0.role == "assistant" }.count, 1)
        XCTAssertEqual(session.snapshot.messages.last?.role, "user")
        XCTAssertEqual(session.snapshot.messages.last?.state, "demo-accepted")
        XCTAssertEqual(session.draft(conversation), "")
        XCTAssertFalse(session.submitting)
    }

    @MainActor func testRelayTimeoutPreservesDraftAndDoesNotRetry() async throws {
        let posts = Counter()
        let session = MobileSession(drafts: try DraftStore(file: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let client = APIClient(endpoint: try Endpoint("https://relay.test", simulator: false), token: "synthetic") { request in
            if request.httpMethod == "GET" { return (Data(Self.fixture.utf8), 200) }
            await posts.increment()
            throw URLError(.timedOut)
        }
        await session.connect(client: client)
        let conversation = try XCTUnwrap(session.snapshot.conversations.first)
        session.setDraft("미확인 초안", conversation: conversation)
        await session.sendDemo(conversation)
        let count = await posts.value
        XCTAssertEqual(count, 1)
        XCTAssertEqual(session.draft(conversation), "미확인 초안")
        XCTAssertEqual(session.snapshot.messages.count, 1)
        XCTAssertEqual(session.notice, "전송 상태 미확인 · 자동 재시도 없음. 초안을 보존했습니다.")
    }

    @MainActor func testPendingDemoPostBlocksDoubleTapAndDiscardsOldContextReceipt() async throws {
        let gate = SnapshotGate()
        let posts = Counter()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = MobileSession(drafts: try DraftStore(file: file))
        let client = APIClient(endpoint: try Endpoint("https://relay.test", simulator: false), token: "synthetic") { request in
            if request.httpMethod == "GET" { return (Data(Self.fixture.utf8), 200) }
            await posts.increment()
            let sent = try JSONDecoder().decode(MessageSubmission.self, from: XCTUnwrap(request.httpBody))
            await gate.wait()
            return (try JSONEncoder().encode(Receipt(id: sent.id, state: "demo-accepted", mode: "demo")), 200)
        }
        await session.connect(client: client)
        let conversation = try XCTUnwrap(session.snapshot.conversations.first)
        let originalScope = session.scope(conversation)
        session.setDraft("연결 전환 초안", conversation: conversation)
        let pending = Task { await session.sendDemo(conversation) }
        await gate.waitUntilStarted()
        XCTAssertTrue(session.submitting)
        await session.sendDemo(conversation)
        let count = await posts.value
        XCTAssertEqual(count, 1)
        session.useDemo()
        await gate.release()
        await pending.value
        XCTAssertEqual(session.snapshot.messages.count, 1)
        XCTAssertNil(session.notice)
        XCTAssertEqual(try DraftStore(file: file).text(for: originalScope), "연결 전환 초안")
    }

    func testKeychainIsEndpointScopedAndUsesDeviceOnlyProtection() throws {
        let endpoint = try Endpoint("https://relay.test", simulator: false)
        let operations = KeychainOperations(update: { query, values in
            XCTAssertEqual((query as NSDictionary)[kSecAttrAccount] as? String, "https://relay.test")
            XCTAssertEqual((values as NSDictionary)[kSecAttrAccessible] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
            return errSecItemNotFound
        }, add: { query in
            XCTAssertEqual((query as NSDictionary)[kSecAttrService] as? String, "dev.herdr.mobile.firstslice.pairing.v1")
            XCTAssertEqual((query as NSDictionary)[kSecValueData] as? Data, Data("synthetic-only".utf8))
            return errSecSuccess
        }, read: { query in
            XCTAssertEqual((query as NSDictionary)[kSecAttrAccount] as? String, "https://relay.test")
            return (errSecSuccess, Data("synthetic-only".utf8))
        })
        let vault = TokenVault(operations: operations)
        try vault.save("synthetic-only", endpoint: endpoint)
        XCTAssertEqual(try vault.load(endpoint: endpoint), "synthetic-only")
    }

    func testKeychainFailureSurfacesAndMissingTokenReturnsNil() throws {
        let endpoint = try Endpoint("https://relay.test", simulator: false)
        let operations = KeychainOperations(update: { _, _ in errSecAuthFailed }, add: { _ in
            XCTFail("Authentication failure must not fall back to add")
            return errSecSuccess
        }, read: { _ in (errSecItemNotFound, nil) })
        let vault = TokenVault(operations: operations)
        XCTAssertThrowsError(try vault.save("synthetic-only", endpoint: endpoint))
        XCTAssertNil(try vault.load(endpoint: endpoint))
    }

    @MainActor func testNavigationFlushPreservesExactDraftAndRejectsChangedScopeOrRevision() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = MobileSession(drafts: try DraftStore(file: file))
        let conversation = try XCTUnwrap(session.snapshot.conversations.first)
        let context = session.contextID
        let scope = session.scope(conversation)
        session.setDraft("202611208", conversation: conversation)
        XCTAssertTrue(session.flushDraft("202611208888", conversation: conversation, contextID: context, capturedScope: scope, expectedRevision: session.draftRevision))
        XCTAssertEqual(try DraftStore(file: file).text(for: scope), "202611208888")
        let savedRevision = session.draftRevision
        session.setDraft("", conversation: conversation)
        XCTAssertFalse(session.flushDraft("202611208888", conversation: conversation, contextID: context, capturedScope: scope, expectedRevision: savedRevision))
        XCTAssertEqual(session.draft(conversation), "")
        let client = APIClient(endpoint: try Endpoint("https://other-relay.test", simulator: false), token: "synthetic") { _ in
            (Data(Self.fixture.utf8), 200)
        }
        await session.connect(client: client)
        XCTAssertFalse(session.flushDraft("202611208888", conversation: conversation, contextID: context, capturedScope: scope))
        XCTAssertEqual(session.draft(conversation), "")
        XCTAssertEqual(try DraftStore(file: file).text(for: scope), "")
    }

    static let fixture = #"{"schemaVersion":1,"mode":"demo","connection":"live","capabilities":{"readMessages":true,"sendMessages":true,"runtimeApproval":false},"teams":[{"id":"herdrdesk","title":"HerdrDesk","memberCount":2}],"agents":[{"address":"synthetic-lead","session":"100:1","role":"synthetic-lead","teamId":"herdrdesk","name":"Lead","provider":"codex","status":"working"}],"conversations":[{"id":"direct:synthetic-lead","title":"Lead","kind":"direct","teamId":"herdrdesk","address":"synthetic-lead","session":"100:1","role":"synthetic-lead","unreadCount":0}],"messages":[{"id":"synthetic-reply","conversationId":"direct:synthetic-lead","role":"assistant","text":"Synthetic fixture","createdAt":"2026-11-20T00:00:00Z","state":"received"}],"tasks":[{"id":"synthetic-task","teamId":"herdrdesk","title":"Synthetic task","state":"working","owner":"Lead"}]}"#
}
private actor Counter {
    var value = 0
    func increment() { value += 1 }
}

private actor SnapshotGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false
    func wait() async {
        started = true
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }
    func release() { continuation?.resume(); continuation = nil }
}
