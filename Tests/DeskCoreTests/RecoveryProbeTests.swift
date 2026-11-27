import XCTest
@testable import DeskCore

final class RecoveryProbeTests: XCTestCase {
    let sid = "01a1cdeb-d1ea-7390-b24a-dcecf2f47a75"

    func testProcessesAreParsed() {
        let procs = RecoveryProbe.parseProcesses("  101     1 /bin/zsh\n  202   101 codex\nbad line\n")
        XCTAssertEqual(procs[202]?.ppid, 101)
        XCTAssertEqual(procs[101]?.command, "/bin/zsh")
        XCTAssertNil(procs[0])
    }

    func testAClaudeRecordMustNameTheSamePid() {
        let text = "@claude 300\n\"sessionId\":\"\(sid)\"\n\"pid\":300\n@claude 301\n\"sessionId\":\"\(sid)\"\n\"pid\":999\n@claude 302\n"
        XCTAssertEqual(RecoveryProbe.parseClaude(text), [300: sid])
    }

    func testOnlyASessionRecordFirstLineCountsForCodex() {
        let text = "@file /h/.codex/sessions/a.jsonl\n\"type\":\"session_meta\"\n\"id\":\"\(sid)\"\n@file /h/.codex/sessions/b.jsonl\n\"id\":\"\(sid)\"\n"
            + "@sid \(sid)\n/h/.claude/projects/-Users-me-shop/\(sid).jsonl\n"
        let files = RecoveryProbe.parseFiles(text)
        XCTAssertEqual(files.codex, ["/h/.codex/sessions/a.jsonl": sid])
        XCTAssertEqual(files.claude[sid], ["/h/.claude/projects/-Users-me-shop/\(sid).jsonl"])
    }

    func testCodexOpenFilesArePerProcess() {
        XCTAssertEqual(RecoveryProbe.parseCodexFiles("@codex 202\nn/h/.codex/sessions/a.jsonl\n@codex 303\n"), [202: ["/h/.codex/sessions/a.jsonl"], 303: []])
    }

    func testTheClaudeFileUnderItsProjectFolderIsPreferred() {
        let files = ["/h/.claude/projects/-Users-old/x.jsonl", "/h/.claude/projects/-Users-me-shop/x.jsonl"]
        XCTAssertEqual(RecoveryProbe.claudeFile(files, cwd: "/Users/me/shop"), files[1])
        XCTAssertNil(RecoveryProbe.claudeFile(files, cwd: "/elsewhere"))
        XCTAssertEqual(RecoveryProbe.claudeFile([files[0]], cwd: "/elsewhere"), files[0])
    }

    func testScriptsQuoteFilesAndSkipBadIds() {
        let script = RecoveryProbe.fileScript(codexFiles: ["/h/it's.jsonl"], claudeSessions: ["../x", sid])
        XCTAssertTrue(script.contains("'/h/it'\\''s.jsonl'"))
        XCTAssertFalse(script.contains("../x"))
        XCTAssertTrue(script.contains("/\(sid).jsonl"))
        XCTAssertFalse(RecoveryProbe.sessionScript(claude: [300], codex: [:]).contains("cat "))   // only the id leaves the record
    }

    func testValidationReportsWhatIsMissing() {
        func role(_ agent: String) -> RecoveryRole {
            RecoveryRole(key: agent, title: agent, machine: nil, agent: agent, sessionId: sid, sessionFile: "/f", cwd: "/c", name: nil,
                         labels: [:], parentRole: nil, lastAddress: "t1", location: nil, bypass: false, savedAt: "")
        }
        let roles = [role("codex"), role("claude-code"), role("codex")]
        let result = RecoveryProbe.parseValidation("@valid 0\ndir\nfile\n\"id\":\"\(sid)\"\n@valid 1\nfile\n@valid 2\ndir\nfile\n\"id\":\"11111111-2222-3333-4444-555555555555\"\n", roles: roles)
        XCTAssertEqual(result[0], .some(nil))
        XCTAssertEqual(result[1], .some("its working folder is missing"))
        XCTAssertEqual(result[2], .some("its conversation file belongs to another session"))
    }

    // MARK: a whole recovery against a fake Core

    final class FakeCore: HcRunning {
        var calls: [[String]] = []
        var resumed = false
        var failRun = false
        var leadStartsFirst = false   // the first start is a lead that is not verifiable yet
        var runs = 0
        let sid: String
        init(sid: String) { self.sid = sid }
        func run(_ args: [String], timeout: TimeInterval) -> HcResult {
            calls.append(args)
            func ok(_ out: String) -> HcResult { HcResult(code: 0, out: out, err: "", timedOut: false) }
            switch args.first {
            case "ls":
                let resumedRow = resumed ? #",{"address":"t9","agent":"codex","state":"live"}"# : ""
                return ok(#"{"terminals":[{"address":"t1","agent":"zsh","state":"live"}"# + resumedRow + "]}")
            case "machine": return ok(#"{"machines":[]}"#)
            case "get":
                if args[1] == "t1" { return ok(#"{"cwd":"/Users/me","labels":{"recovery.role":"shop-lead","team.id":"shop"},"foreground":{"pid":101},"argv":["/bin/zsh"]}"#) }
                return ok("{\"cwd\":\"/Users/me\",\"labels\":{\"recovery.role\":\"shop-lead\",\"recovery.launching\":\"\(sid)\"},\"foreground\":{\"pid\":202,\"cwd\":\"/Users/me/shop\",\"argv\":[\"node\",\"codex\",\"--dangerously-bypass-approvals-and-sandbox\"]},\"argv\":[\"/bin/zsh\"]}")
            case "exec":
                let script = args.last ?? ""
                if script == RecoveryProbe.processScript { return ok("101 1 zsh\n202 1 codex\n") }
                if script.contains("@codex") { return ok("@codex 202\nn/h/.codex/sessions/a.jsonl\n") }
                if script.contains("@file") { return ok("@file /h/.codex/sessions/a.jsonl\n\"type\":\"session_meta\"\n\"id\":\"\(sid)\"\n") }
                if script.contains("%s\\n' 1;") { return ok("@valid 0\ndir\nfile\n\"id\":\"\(sid)\"\n@valid 1\ndir\nfile\n\"id\":\"\(sid)\"\n") }
                if script.contains("@valid") { return ok("@valid 0\ndir\nfile\n\"id\":\"\(sid)\"\n") }
                return ok("")
            case "run":
                if failRun { return HcResult(code: 1, out: "", err: "no such space", timedOut: false) }
                runs += 1
                if leadStartsFirst && runs == 1 { return ok(#"{"address":"t8"}"#) }
                resumed = true
                return ok(#"{"address":"t9"}"#)
            default: return ok("{}")
            }
        }
    }

    func testARebootedShellIsResumedOnceAndItsLabelsRetired() throws {
        let core = FakeCore(sid: sid)
        let role = RecoveryRole(key: "shop-lead", title: "Shop lead", machine: nil, agent: "codex", sessionId: sid,
                                sessionFile: "/h/.codex/sessions/a.jsonl", cwd: "/Users/me/shop", name: nil, labels: ["team.id": "shop"],
                                parentRole: nil, lastAddress: "t1", location: nil, bypass: false, savedAt: "t0")
        let runner = RecoveryRunner(hc: core, app: nil, locale: "en", now: { "t1" })
        let before = try runner.check(RecoveryRegistry(roles: [role]))
        XCTAssertEqual(before.resumable, 1)
        let report = try runner.restore(RecoveryRegistry(roles: [role]))
        XCTAssertTrue(report.ready)
        XCTAssertEqual(core.calls.filter { $0.first == "run" }.count, 1)
        let run = try XCTUnwrap(core.calls.first { $0.first == "run" })
        XCTAssertTrue(run.contains("recovery.role=shop-lead"))
        XCTAssertTrue(run.contains("team.id=shop"))
        XCTAssertEqual(report.retired, ["t1"])
        XCTAssertTrue(core.calls.contains { $0.first == "label" && $0[1] == "t1" && $0.contains("recovery.retired-role=shop-lead") })
        // A second recovery starts nothing.
        let again = try runner.restore(RecoveryRegistry(roles: [role]))
        XCTAssertTrue(again.ready)
        XCTAssertEqual(core.calls.filter { $0.first == "run" }.count, 1)
    }

    func testTheStoreIsPrivate() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = RecoveryStore(url: folder.appendingPathComponent("recovery.json"))
        XCTAssertEqual(store.load(), RecoveryRegistry())
        try store.save(RecoveryRegistry(roles: [], savedAt: "t1"))
        XCTAssertEqual(store.load().savedAt, "t1")
        let mode = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        try? FileManager.default.removeItem(at: folder)
    }

    func testScriptsSucceedEvenWhenTheLastCheckIsFalse() {
        XCTAssertTrue(RecoveryProbe.validateScript([]).hasSuffix("true"))
        XCTAssertTrue(RecoveryProbe.sessionScript(claude: [1], codex: [:]).hasSuffix("true"))
        XCTAssertTrue(RecoveryProbe.fileScript(codexFiles: ["/a"], claudeSessions: []).hasSuffix("true"))
    }

    func testAFailedStartKeepsItsReasonInTheReport() throws {
        let core = FakeCore(sid: sid); core.failRun = true
        let role = RecoveryRole(key: "shop-lead", title: "Shop lead", machine: nil, agent: "codex", sessionId: sid,
                                sessionFile: "/h/.codex/sessions/a.jsonl", cwd: "/Users/me/shop", name: nil, labels: [:],
                                parentRole: nil, lastAddress: "t1", location: nil, bypass: false, savedAt: "t0")
        let report = try RecoveryRunner(hc: core, app: nil, locale: "en", now: { "t1" }).restore(RecoveryRegistry(roles: [role]))
        XCTAssertEqual(report.roles.first?.action, .blocked)
        XCTAssertTrue(report.roles.first?.reason.contains("no such space") ?? false)
    }

    func testTheAgentsOwnFolderIsSavedNotTheShellsStartFolder() throws {
        let runtime = try RecoveryCollector(hc: FakeCore(sid: sid), app: nil).collect()
        let core = FakeCore(sid: sid); core.resumed = true
        let resumed = try RecoveryCollector(hc: core, app: nil).collect()
        XCTAssertEqual(runtime.terminal("t1")?.cwd, "/Users/me")
        XCTAssertEqual(resumed.terminal("t9")?.cwd, "/Users/me/shop")
    }

    func testPermissionFlagsComeFromTheRunningAgent() throws {
        let core = FakeCore(sid: sid); core.resumed = true
        let runtime = try RecoveryCollector(hc: core, app: nil).collect()
        XCTAssertTrue(Recovery.bypass(runtime.terminal("t9")?.argv ?? []))
    }

    func testAParentStillRunningIsFoundByItsSession() throws {
        let parentSid = "22222222-2222-3333-4444-555555555555"
        let parent = RecoveryRole(key: "local:\(parentSid)", title: "Lead", machine: nil, agent: "codex", sessionId: parentSid, sessionFile: "/p",
                                  cwd: "/Users/me", name: nil, labels: [:], parentRole: nil, lastAddress: "t7", location: nil, bypass: false, savedAt: "")
        let runtime = RecoveryRuntime(terminals: [ObservedTerminal(address: "t7", agent: "codex", sessionId: parentSid)])
        XCTAssertEqual(RecoveryRunner.parentAddress(for: "local:\(parentSid)", in: RecoveryRegistry(roles: [parent]), runtime: runtime), "t7")
        XCTAssertNil(RecoveryRunner.parentAddress(for: nil, in: RecoveryRegistry(roles: [parent]), runtime: runtime))
    }

    func testOnlyOneRecoveryRunsAtATimeAcrossProcesses() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = RecoveryStore(url: folder.appendingPathComponent("recovery.json"))
        var inner: Error?
        try store.exclusively {
            do { try store.exclusively { } } catch { inner = error }
        }
        XCTAssertNotNil(inner)
        XCTAssertNoThrow(try store.exclusively { })
        try? FileManager.default.removeItem(at: folder)
    }

    func testAWorkerWaitsWhileItsSavedLeadIsNotRunning() throws {
        let core = FakeCore(sid: sid); core.failRun = true
        let leadSid = "22222222-2222-3333-4444-555555555555"
        let lead = RecoveryRole(key: "lead", title: "Lead", machine: nil, agent: "claude-code", sessionId: leadSid, sessionFile: "/p",
                                cwd: "/Users/me", name: nil, labels: [:], parentRole: nil, lastAddress: "t7", location: nil, bypass: false, savedAt: "")
        let worker = RecoveryRole(key: "shop-lead", title: "Worker", machine: nil, agent: "codex", sessionId: sid, sessionFile: "/h/.codex/sessions/a.jsonl",
                                  cwd: "/Users/me/shop", name: nil, labels: [:], parentRole: "lead", lastAddress: "t1", location: nil, bypass: false, savedAt: "")
        let report = try RecoveryRunner(hc: core, app: nil, locale: "en", now: { "t1" }).restore(RecoveryRegistry(roles: [worker, lead]))
        XCTAssertEqual(core.calls.filter { $0.first == "run" }.count, 1)              // only the lead was tried
        XCTAssertEqual(report.roles.first { $0.key == "shop-lead" }?.action, .blocked)
    }

    func testAWorkerJoinsTheLeadStartedInTheSameRecovery() throws {
        let core = FakeCore(sid: sid)
        let leadSid = "22222222-2222-3333-4444-555555555555"
        let lead = RecoveryRole(key: "lead", title: "Lead", machine: nil, agent: "claude-code", sessionId: leadSid, sessionFile: "/p",
                                cwd: "/Users/me", name: nil, labels: [:], parentRole: nil, lastAddress: "t7", location: nil, bypass: false, savedAt: "")
        let worker = RecoveryRole(key: "shop-lead", title: "Worker", machine: nil, agent: "codex", sessionId: sid, sessionFile: "/h/.codex/sessions/a.jsonl",
                                  cwd: "/Users/me/shop", name: nil, labels: [:], parentRole: "lead", lastAddress: "t1", location: nil, bypass: false, savedAt: "")
        core.leadStartsFirst = true
        _ = try RecoveryRunner(hc: core, app: nil, locale: "en", now: { "t1" }).restore(RecoveryRegistry(roles: [worker, lead]))
        let runs = core.calls.filter { $0.first == "run" }
        XCTAssertEqual(runs.count, 2)
        let parent = try XCTUnwrap(runs[1].firstIndex(of: "--parent"))
        XCTAssertEqual(runs[1][parent + 1], "t8")
    }
}
