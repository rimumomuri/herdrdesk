import XCTest
@testable import DeskCore

final class RecoveryTests: XCTestCase {
    let sid = "01a1cdeb-d1ea-7390-b24a-dcecf2f47a75"
    let other = "11111111-2222-3333-4444-555555555555"

    func role(_ key: String = "shop-lead", machine: String? = nil, sid: String? = nil, agent: String = "codex",
              address: String = "t1", parent: String? = nil, bypass: Bool = false) -> RecoveryRole {
        RecoveryRole(key: key, title: key, machine: machine, agent: agent, sessionId: sid ?? self.sid, sessionFile: "/x/s.jsonl",
                     cwd: "/Users/me/shop", name: nil, labels: ["recovery.role": key], parentRole: parent, lastAddress: address,
                     location: nil, bypass: bypass, savedAt: "t0")
    }
    func agentTerm(_ address: String, sid: String? = nil, role: String? = "shop-lead", agent: String = "codex",
                   labels: [String: String] = [:], argv: [String] = []) -> ObservedTerminal {
        var all = labels; if let role { all["recovery.role"] = role }
        return ObservedTerminal(address: address, name: nil, labels: all, cwd: "/Users/me/shop", argv: argv, agent: agent,
                                sessionId: sid ?? self.sid, sessionFile: "/x/s.jsonl")
    }
    func shell(_ address: String, role: String? = "shop-lead") -> ObservedTerminal {
        ObservedTerminal(address: address, labels: role.map { ["recovery.role": $0] } ?? [:], cwd: "/Users/me", shell: true)
    }

    // MARK: choose / resolve

    func testTheSameConversationRunningIsLeftAlone() {
        XCTAssertEqual(Recovery.choose(role(), agentTerm("t9"), online: true).0, .skip)
    }

    func testAShellLeftBehindIsResumed() {
        XCTAssertEqual(Recovery.choose(role(), shell("t1"), online: true).0, .resume)
    }

    func testADifferentConversationThereBlocks() {
        XCTAssertEqual(Recovery.choose(role(), agentTerm("t1", sid: other), online: true).0, .blocked)
    }

    func testAResumeAlreadyStartedIsNotStartedAgain() {
        var term = shell("t1"); term.labels["recovery.launching"] = sid
        XCTAssertEqual(Recovery.choose(role(), term, online: true).0, .pending)
    }

    func testAnUnconnectedMachineIsNotTouched() {
        let runtime = RecoveryRuntime(terminals: [], connected: [])
        let (actual, online) = try! Recovery.resolve(role(machine: "laptop"), in: runtime)
        XCTAssertNil(actual); XCTAssertFalse(online)
        XCTAssertEqual(Recovery.choose(role(machine: "laptop"), actual, online: online).0, .offline)
    }

    func testAnUnknownForegroundProgramBlocks() {
        let odd = ObservedTerminal(address: "t1", labels: ["recovery.role": "shop-lead"])
        XCTAssertEqual(Recovery.choose(role(), odd, online: true).0, .blocked)
    }

    func testTheRunningExactSessionWinsOverItsOldShell() throws {
        let runtime = RecoveryRuntime(terminals: [shell("t1"), agentTerm("t5", role: nil)])
        XCTAssertEqual(try Recovery.resolve(role(), in: runtime).0?.address, "t5")
    }

    func testTwoCopiesOfOneConversationAreRefused() {
        let runtime = RecoveryRuntime(terminals: [agentTerm("t5", role: nil), agentTerm("t6", role: nil)])
        XCTAssertThrowsError(try Recovery.resolve(role(), in: runtime))
    }

    func testNoTerminalMeansANewOne() throws {
        let plan = Recovery.plan(RecoveryRegistry(roles: [role()]), runtime: RecoveryRuntime(terminals: []), valid: { _ in nil })
        XCTAssertEqual(plan.first?.action, .create)
    }

    func testAMissingFolderOrConversationFileBlocks() {
        let plan = Recovery.plan(RecoveryRegistry(roles: [role()]), runtime: RecoveryRuntime(terminals: [shell("t1")]),
                                 valid: { _ in "working folder or conversation file is missing" })
        XCTAssertEqual(plan.first?.action, .blocked)
    }

    func testAGoneHerdrSpaceBlocks() {
        var saved = role(); saved.location = RecoveryLocation(space: "s-old", tab: nil)
        var runtime = RecoveryRuntime(terminals: [shell("t1")], spaces: ["s-new"]); runtime.layoutKnown = true
        let plan = Recovery.plan(RecoveryRegistry(roles: [saved]), runtime: runtime, valid: { _ in nil })
        XCTAssertEqual(plan.first?.action, .blocked)
    }

    func testParentsComeFirst() {
        let ordered = Recovery.ordered([role("worker", parent: "lead"), role("lead", sid: other)])
        XCTAssertEqual(ordered.map(\.key), ["lead", "worker"])
    }

    // MARK: resume command

    func testCodexResumesTheExactSessionWithoutBypassByDefault() throws {
        let command = try Recovery.resumeCommand(role(), locale: "en")
        XCTAssertTrue(command.hasPrefix("cd -- '/Users/me/shop' && exec 'codex' '--no-daemon' 'resume' '\(sid)' "))
        XCTAssertFalse(command.contains("dangerously"))
    }

    func testBypassOnlyWhenItWasRunningThatWay() throws {
        XCTAssertTrue(try Recovery.resumeCommand(role(bypass: true), locale: "en").contains("'--dangerously-bypass-approvals-and-sandbox'"))
        XCTAssertTrue(try Recovery.resumeCommand(role(agent: "claude-code", bypass: true), locale: "en").contains("'--dangerously-skip-permissions'"))
        XCTAssertTrue(Recovery.bypass(["codex", "--dangerously-bypass-approvals-and-sandbox"]))
        XCTAssertFalse(Recovery.bypass(["codex", "resume", "x"]))
    }

    func testClaudeResumesItsConversationFile() throws {
        XCTAssertTrue(try Recovery.resumeCommand(role(agent: "claude-code"), locale: "en").contains("'claude' '--resume' '/x/s.jsonl'"))
    }

    func testAQuoteInTheFolderCannotBreakOut() throws {
        var saved = role(); saved.cwd = "/Users/me/it's; rm -rf ~"
        XCTAssertTrue(try Recovery.resumeCommand(saved, locale: "en").hasPrefix("cd -- '/Users/me/it'\\''s; rm -rf ~' && exec "))
    }

    func testABadSessionIdOrAgentIsRefused() {
        XCTAssertThrowsError(try Recovery.resumeCommand(role(sid: "../../etc"), locale: "en"))
        XCTAssertThrowsError(try Recovery.resumeCommand(role(agent: "vim"), locale: "en"))
    }

    func testTheResumeMessageFollowsTheAppLanguage() throws {
        XCTAssertTrue(try Recovery.resumeCommand(role(), locale: "ko").contains("기존 대화 복구입니다"))
        XCTAssertTrue(try Recovery.resumeCommand(role(), locale: "ja").contains("既存の会話の復旧です"))
    }

    func testRunArgumentsMarkTheLaunchAndPlaceItInItsTab() throws {
        var saved = role(machine: "laptop"); saved.location = RecoveryLocation(space: "laptop/s1", tab: "laptop/b2")
        let args = try Recovery.runArguments(saved, runtime: RecoveryRuntime(terminals: [], connected: ["laptop"], spaces: ["laptop/s1"], tabs: ["laptop/b2"]),
                                             parent: nil, locale: "en", now: "t1")
        XCTAssertEqual(Array(args.prefix(8)), ["run", "--bg", "--keep", "--json", "--cwd", "/Users/me/shop", "--no-parent", "--on"])
        XCTAssertTrue(args.contains("recovery.launching=\(sid)"))
        XCTAssertTrue(args.contains("herdr.space=s1"))
        XCTAssertTrue(args.contains("herdr.tab=b2"))
        XCTAssertEqual(Array(args.suffix(3).prefix(2)), ["/bin/zsh", "-lic"])
    }

    // MARK: automatic save

    func testRunningAgentsAreSavedButCardWorkersAreNot() {
        let worker = agentTerm("t7", sid: other, role: "shop-builder-2")
        let spawned = agentTerm("t8", sid: "22222222-2222-3333-4444-555555555555", role: nil, labels: ["task.spawned": "1", "team.role": "builder"])
        let (saved, seen) = Recovery.merge(RecoveryRegistry(), runtime: RecoveryRuntime(terminals: [agentTerm("t1"), worker, spawned, shell("t2", role: nil)]),
                                           seen: [], now: "t1")
        XCTAssertEqual(saved.roles.map(\.key), ["shop-lead"])
        XCTAssertEqual(seen, ["shop-lead"])
        XCTAssertEqual(saved.savedAt, "t1")
    }

    func testAnAgentWithoutARoleLabelGetsAKeyFromItsConversation() {
        let (saved, _) = Recovery.merge(RecoveryRegistry(), runtime: RecoveryRuntime(terminals: [agentTerm("laptop/t3", role: nil)], connected: ["laptop"]),
                                        seen: [], now: "t1")
        XCTAssertEqual(saved.roles.first?.key, "laptop:\(sid)")
        XCTAssertEqual(saved.roles.first?.machine, "laptop")
    }

    func testAfterARebootTheShellsKeepTheirRoles() {
        let before = RecoveryRegistry(roles: [role()], savedAt: "t0")
        let (saved, _) = Recovery.merge(before, runtime: RecoveryRuntime(terminals: [shell("t1")]), seen: [], now: "t2")
        XCTAssertEqual(saved, before)
    }

    func testAnAgentClosedWhileTheAppWatchedIsDropped() {
        let before = RecoveryRegistry(roles: [role()], savedAt: "t0")
        let (saved, _) = Recovery.merge(before, runtime: RecoveryRuntime(terminals: []), seen: ["shop-lead"], now: "t2")
        XCTAssertTrue(saved.roles.isEmpty)
    }

    func testAMachineThatDidNotAnswerLosesNothing() {
        let before = RecoveryRegistry(roles: [role(machine: "laptop")], savedAt: "t0")
        let (saved, _) = Recovery.merge(before, runtime: RecoveryRuntime(terminals: [], connected: []), seen: ["shop-lead"], now: "t2")
        XCTAssertEqual(saved, before)
    }

    func testANewConversationForTheSameRoleReplacesTheOldOne() {
        let before = RecoveryRegistry(roles: [role()], savedAt: "t0")
        let (saved, _) = Recovery.merge(before, runtime: RecoveryRuntime(terminals: [agentTerm("t4", sid: other)]), seen: [], now: "t2")
        XCTAssertEqual(saved.roles.first?.sessionId, other)
        XCTAssertEqual(saved.roles.first?.lastAddress, "t4")
    }

    func testNothingChangedKeepsTheSaveTime() {
        let (first, seen) = Recovery.merge(RecoveryRegistry(), runtime: RecoveryRuntime(terminals: [agentTerm("t1")]), seen: [], now: "t1")
        let (second, _) = Recovery.merge(first, runtime: RecoveryRuntime(terminals: [agentTerm("t1")]), seen: seen, now: "t9")
        XCTAssertEqual(second, first)
    }

    func testTwoTerminalsClaimingOneRoleChangeNothing() {
        let before = RecoveryRegistry(roles: [role()], savedAt: "t0")
        let (saved, _) = Recovery.merge(before, runtime: RecoveryRuntime(terminals: [agentTerm("t4", sid: other), agentTerm("t5", sid: "33333333-2222-3333-4444-555555555555")]),
                                        seen: [], now: "t2")
        XCTAssertEqual(saved.roles, before.roles)
    }

    func testTheParentIsSavedAsARole() {
        var worker = agentTerm("t2", sid: other, role: "shop-reviewer"); worker.parent = "t1"
        let (saved, _) = Recovery.merge(RecoveryRegistry(), runtime: RecoveryRuntime(terminals: [agentTerm("t1"), worker]), seen: [], now: "t1")
        XCTAssertEqual(saved.roles.first { $0.key == "shop-reviewer" }?.parentRole, "shop-lead")
    }

    func testBypassIsRememberedFromTheRunningCommand() {
        let (saved, _) = Recovery.merge(RecoveryRegistry(), runtime: RecoveryRuntime(terminals: [agentTerm("t1", argv: ["/bin/zsh", "-lic", "exec codex --dangerously-bypass-approvals-and-sandbox resume x"])]),
                                        seen: [], now: "t1")
        XCTAssertEqual(saved.roles.first?.bypass, true)
    }

    // MARK: review fixes

    func testAResumedConversationStillMarkedAsStartingCountsAsRunning() {
        var term = agentTerm("t9"); term.labels["recovery.launching"] = sid
        XCTAssertEqual(Recovery.choose(role(), term, online: true).0, .skip)
    }

    func testARunningAgentWhoseSessionCannotBeReadIsKept() {
        let before = RecoveryRegistry(roles: [role()], savedAt: "t0")
        var unverified = agentTerm("t1"); unverified.sessionId = nil
        let (saved, _) = Recovery.merge(before, runtime: RecoveryRuntime(terminals: [unverified]), seen: ["shop-lead"], now: "t2")
        XCTAssertEqual(saved, before)
    }

    func testSavesWaitAfterStructureChangesAndAreSpacedOutForTurns() {
        XCTAssertEqual(Recovery.saveDelay(checked: false, structural: false, turns: false, sinceLast: 0), 2)
        XCTAssertEqual(Recovery.saveDelay(checked: true, structural: true, turns: true, sinceLast: 0), 5)
        XCTAssertEqual(Recovery.saveDelay(checked: true, structural: false, turns: true, sinceLast: 10), 50)
        XCTAssertEqual(Recovery.saveDelay(checked: true, structural: false, turns: true, sinceLast: 600), 5)
        XCTAssertNil(Recovery.saveDelay(checked: true, structural: false, turns: false, sinceLast: 0))
    }

    func testAShellLeftByARebootedRemoteMachineKeepsItsRole() {
        let before = RecoveryRegistry(roles: [role(machine: "laptop")], savedAt: "t0")
        let (saved, _) = Recovery.merge(before, runtime: RecoveryRuntime(terminals: [shell("laptop/t1")], connected: ["laptop"]), seen: ["shop-lead"], now: "t2")
        XCTAssertEqual(saved, before)
    }

    func testAMachineGoneOfflineForgetsWhatWasSeenThere() {
        let (_, seen) = Recovery.merge(RecoveryRegistry(roles: [role(machine: "laptop")]), runtime: RecoveryRuntime(terminals: [], connected: []),
                                       seen: ["shop-lead"], now: "t2")
        XCTAssertFalse(seen.contains("shop-lead"))
    }

    func testTwoUnlabelledSessionsWithTheSameStartAreBothSaved() {
        let a = agentTerm("t1", sid: "01a1cdeb-0000-7390-b24a-dcecf2f47a75", role: nil)
        let b = agentTerm("t2", sid: "01a1cdeb-1111-7390-b24a-dcecf2f47a75", role: nil)
        let (saved, _) = Recovery.merge(RecoveryRegistry(), runtime: RecoveryRuntime(terminals: [a, b]), seen: [], now: "t1")
        XCTAssertEqual(saved.roles.count, 2)
    }

    func testAnUnlabelledRolesShellAtItsLastAddressKeepsIt() {
        var saved = role(machine: "laptop"); saved.labels = [:]; saved.key = "laptop:\(sid)"; saved.lastAddress = "laptop/t3"
        let before = RecoveryRegistry(roles: [saved], savedAt: "t0")
        let (after, _) = Recovery.merge(before, runtime: RecoveryRuntime(terminals: [shell("laptop/t3", role: nil)], connected: ["laptop"]),
                                        seen: [saved.key], now: "t2")
        XCTAssertEqual(after, before)
    }

    func testASavedSpaceThatIsGoneBlocksEvenWhenNoSpaceIsLeft() {
        var saved = role(); saved.location = RecoveryLocation(space: "s-old", tab: nil)
        var runtime = RecoveryRuntime(terminals: [shell("t1")]); runtime.layoutKnown = true
        XCTAssertEqual(Recovery.plan(RecoveryRegistry(roles: [saved]), runtime: runtime, valid: { _ in nil }).first?.action, .blocked)
        XCTAssertEqual(Recovery.plan(RecoveryRegistry(roles: [saved]), runtime: RecoveryRuntime(terminals: [shell("t1")]), valid: { _ in nil }).first?.action, .resume)
    }

    func testTheSaveSignatureFollowsTeamAndTitleLabels() {
        XCTAssertNotEqual(Recovery.labelSignature(["team.id": "a", "x": "1"]), Recovery.labelSignature(["team.id": "b", "x": "1"]))
        XCTAssertEqual(Recovery.labelSignature(["team.id": "a", "x": "1"]), Recovery.labelSignature(["team.id": "a", "x": "2"]))
    }

    func testAnUnverifiedAgentStillAtItsAddressBlocksInsteadOfStartingACopy() {
        var saved = role(); saved.labels = [:]; saved.key = "local:\(sid)"
        var running = agentTerm("t1", role: nil); running.sessionId = nil
        XCTAssertEqual(Recovery.plan(RecoveryRegistry(roles: [saved]), runtime: RecoveryRuntime(terminals: [running]), valid: { _ in nil }).first?.action, .blocked)
    }

    func testARenamedRoleReplacesItsOldEntry() {
        let before = RecoveryRegistry(roles: [role("old-name")], savedAt: "t0")
        let (saved, _) = Recovery.merge(before, runtime: RecoveryRuntime(terminals: [agentTerm("t1", role: "new-name")]), seen: ["old-name"], now: "t2")
        XCTAssertEqual(saved.roles.map(\.key), ["new-name"])
    }

    func testAFlagNamedOnlyInThePromptIsNotABypass() {
        XCTAssertFalse(Recovery.bypass(["codex", "resume", "x", "Review the --dangerously-bypass-approvals-and-sandbox flag; do not enable it"]))
        XCTAssertFalse(Recovery.bypass(["/bin/zsh", "-lic", "exec codex 'mention --dangerously-skip-permissions here'"]))
        XCTAssertTrue(Recovery.bypass(["/bin/zsh", "-lic", "exec codex --dangerously-bypass-approvals-and-sandbox resume x 'hi'"]))
        // our own resume, wrapped twice
        XCTAssertTrue(Recovery.bypass(["/bin/zsh", "-lic", "exec /bin/zsh -lic 'cd -- /Users/me && exec codex --no-daemon --dangerously-bypass-approvals-and-sandbox resume x '\"'\"'msg'\"'\"''"]))
        XCTAssertTrue(Recovery.bypass(["node", "/usr/local/bin/claude", "--dangerously-skip-permissions", "--resume", "x"]))
    }
}
