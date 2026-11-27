import AppKit
import CryptoKit
import UniformTypeIdentifiers
import DeskCore
import WebKit

final class Desk: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    private var web: WKWebView!
    private var window: NSWindow!
    private var index: URL!
    private var pump: EventPump?
    private var executable: String?
    private var connection = "connecting"
    private var candidates: [Term] = []
    private var terms: [[String: Any]] = []
    private var machines: [[String: Any]] = []
    private var spaces: [[String: Any]] = []
    private var replySignature: [String]?
    private var replies: [[String: Any]] = []
    private var teamMessages: [[String: Any]] = []
    private var liveTurns: [String: [String: String]] = [:]
    private let liveReplyArchive = LiveReplyArchive(url: DeskPaths.data.appendingPathComponent("live-replies.json"))
    private let userDispatchReceipts = UserDispatchReceipts(root:UserDispatchReceipts.defaultRoot())
    private let lineageStore = LineageStore(root:LineageStore.defaultRoot())
    private var liveMessages: [[String: String]] = []
    private let handoffStore = HandoffStore(url: HandoffStore.defaultURL())
    private lazy var handoffs = handoffStore.load()
    private var handoffSignature = ""
    private var handoffTimer: Timer?
    private var pushedHandoffSignature: String?
    private var pushDiff = PushDiff()
    private var resultsStamp: String?
    private var lineageCache: (stamp: Date, edges: [HandoffLineage])?
    private let handoffWrites = DispatchQueue(label: "herdrdesk.handoffs", qos: .utility)
    /// Team card board from `herdr-task board --json`, re-read only when the ledger folder changes.
    private lazy var taskSource: TaskBoardSource = {
        let env = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: env["HERDRDESK_TASK_ROOT"] ?? NSHomeDirectory() + "/workspace/operations/herdr-tasks")
            .appendingPathComponent("state")
        let exe = ProcessHc.resolveExecutable("herdr-task", overrides: [env["HERDRDESK_TASK"]])
        return TaskBoardSource(stamp: { TaskBoardSource.boardStamp(root) },
                               run: { exe.map { ProcessHc(path: $0).run(["board", "--json"], timeout: 5) }
                                   ?? HcResult(code: 127, out: "", err: "herdr-task not found", timedOut: false) })
    }()
    private var taskBoard: [String: Any] = [:]
    private lazy var taskExecutable: String? = ProcessHc.resolveExecutable("herdr-task", overrides: [ProcessInfo.processInfo.environment["HERDRDESK_TASK"]])
    /// Settings edits stay quick on their own queue; clones (minutes) run apart so they never hold a setting back.
    private let machineQueue = DispatchQueue(label: "herdrdesk.machines", qos: .userInitiated)
    private let cloneQueue = DispatchQueue(label: "herdrdesk.machines.clone", qos: .userInitiated, attributes: .concurrent)
    private let taskQueue = DispatchQueue(label: "herdrdesk.tasks", qos: .utility)
    private var taskPolling = false
    private var taskVersion = 0
    private var pushedTaskVersion = -1
    private lazy var liveChat = LiveChatFeed(receipts:userDispatchReceipts) { [weak self] batch in
        DispatchQueue.main.async {
            guard let self, self.automaticChat else { return }
            for entry in batch {
                if entry["kind"] == "turn", let address = entry["fromAddress"], let session = entry["session"] {
                    let key = address + ":" + session
                    let previous = self.liveTurns[key]
                    // the shown runtime state needs the turn's start; reply pairing keeps its earlier rule
                    if LiveTurnRule.accepts(previous: previous, entry: entry) { self.liveTurns[key] = entry }
                    if entry["state"] == "done", previous == nil || previous?["turn"] == entry["turn"], let turn = entry["turn"], let at = entry["at"] {
                        do { try self.liveReplyArchive.complete(turn: turn, session: session, address: address, at: at) }
                        catch { self.call("window.desk.notice(message)", ["message": "답장 턴 정보 저장에 실패했습니다. 현재 기록은 유지됩니다."]) }
                    }
                } else if entry["kind"] == "agent-send" {
                    self.recordHandoff(entry, source: "sender")
                } else if entry["kind"] == "reply" {
                    if let address = entry["fromAddress"], let session = entry["session"] {
                        self.handoffs.deskReply(from: HandoffParty(address: address, session: session, role: entry["role"] ?? ""),
                                                at: Desk.ms(entry["at"]), body: entry["body"] ?? "")
                    }
                    do { try self.liveReplyArchive.append(entry) }
                    catch {
                        self.liveMessages.append(entry)
                        self.call("window.desk.notice(message)", ["message": "답장을 저장하지 못했습니다. 현재 화면에만 보존됩니다."])
                    }
                } else {
                    if entry["kind"] == "agent-handoff" { self.recordHandoff(entry, source: "receiver") }
                    self.liveMessages.append(entry)
                }
            }
            self.observeHandoffs()
            while self.liveMessages.filter({ $0["kind"] != "reply" }).count > 300,
                  let index = self.liveMessages.firstIndex(where: { $0["kind"] != "reply" }) {
                self.liveMessages.remove(at:index)
            }
            self.push()
        }
    }
    private var automaticChat: Bool { preferences.object(forKey: "automaticChat") as? Bool ?? true }

    private var inventoryBusy = false
    private var lastInventory = Date.distantPast
    private var inventoryRefresh: DispatchWorkItem?
    private var appExecutable: String? { ProcessHc.resolveExecutable("herdr-app", overrides: [ProcessInfo.processInfo.environment["HERDRDESK_APP"]]) }
    private var observer: TerminalObserver?
    private var watch: (id: String, term: Term, interactive: Bool)?
    private var watchGeneration = 0
    private var currentGrid: (cols: Int, rows: Int)?
    private var ready = false
    private var companion: CompanionPanel?
    private var currentSound: NSSound?
    private let systemSounds = SystemSounds.names()
    private let attachmentStore = AttachmentStore(root: AttachmentStore.defaultRoot())
    private let sentChatImages = SentChatImages(root: DeskPaths.data.appendingPathComponent("sent-image-previews"))
    private let attachmentQueue = DispatchQueue(label: "herdrdesk.attachments", qos: .utility)
    private var archiveRoles: [String] = []
    private lazy var configuredTeams: [[String: Any]] = {
        guard DeskPaths.retainsLegacyProfile, let path = Bundle.main.url(forResource: "legacy-teams", withExtension: "json"),
              let data = try? Data(contentsOf: path), data.count < 256 * 1024,
              let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return list
    }()
    private var currentLanguage = "en"
    private var generation = 0
    private let commands = DispatchQueue(label: "herdrdesk.commands", qos: .userInitiated)
    private let inventoryQueue = DispatchQueue(label: "herdrdesk.inventory", qos: .utility)
    private let preferences = UserDefaults.standard
    private let environment = ProcessInfo.processInfo.environment
    private var isolated: Bool { environment["HERDRDESK_HC"] != nil }

    // MARK: agent recovery state
    private let recoveryStore = RecoveryStore()
    private let recoveryQueue = DispatchQueue(label: "herdrdesk.recovery", qos: .utility)
    /// Saved roles seen running during this live connection (a role that disappears after that was closed on purpose).
    private var recoverySeen = Set<String>()
    private var recoverySignature = ""
    private var recoveryTurns = ""
    private var recoveryChecked = -1       // the connection generation whose first check ran
    /// Bumped whenever Core goes away; a save started before that writes nothing.
    private let recoveryEpochBox = RecoveryEpoch()
    private var recoveryEpoch: Int { recoveryEpochBox.value }
    private var recoveryLastSave = Date.distantPast
    private var recoverySave: DispatchWorkItem?
    private var recoveryBusy = ""          // "", "checking", "restoring"
    private var recoveryReport: RecoveryReport?
    private var recoveryError = ""
    private lazy var recoverySaved = recoveryStore.load()
    private var recoveryEnabled: Bool { !isolated }

    func applicationDidFinishLaunching(_ note: Notification) {
        updateMenu(preferences.string(forKey: "displayLocale") ?? Locale.preferredLanguages.first ?? "en")
        let configuration = WKWebViewConfiguration()
        if isolated { configuration.websiteDataStore = .nonPersistent() }
        configuration.userContentController.add(self, name: "desk")
        web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        web.uiDelegate = self
        let screen = NSRect(x: 0, y: 0, width: 1280, height: 850)
        window = NSWindow(contentRect: screen, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "HerdrDesk"
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 380, height: 540)
        window.contentView = web
        if !isolated { window.setFrameAutosaveName("HerdrDeskPublic") }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let bundleWeb = Bundle.main.resourceURL!.appendingPathComponent("web")
        index = bundleWeb.appendingPathComponent("index.html")
        web.loadFileURL(index, allowingReadAccessTo: bundleWeb)
        if !isolated {
            let companion = CompanionPanel(webFolder: bundleWeb)
            companion.onOpen = { [weak self] in
                guard let self else { return }
                NSApp.activate(ignoringOtherApps: true)
                if self.window.isMiniaturized { self.window.deminiaturize(nil) }
                self.window.makeKeyAndOrderFront(nil)
                self.call("window.desk.openCompanionTarget()", [:])
            }
            companion.onTurnOff = { [weak self] in self?.call("window.desk.companionOff()", [:]) }
            self.companion = companion
        }
        connect()
        loadArchivedAttachmentRoles()
        captureIfRequested()
        reportCompatibilityIfRequested()
    }

    private func connect() {
        generation += 1
        let current = generation
        pump?.stop()
        pump = nil
        stopWatch()
        terms = []
        liveChat.track([])
        liveTurns.removeAll()
        recoverySeen = []
        recoverySignature = ""
        recoveryTurns = ""
        candidates = []
        spaces = []
        machines = []
        inventoryBusy = false
        lastInventory = .distantPast
        inventoryRefresh?.cancel()
        inventoryRefresh = nil
        executable = ProcessHc.resolveExecutable("hc", overrides: [environment["HERDRDESK_HC"], preferences.string(forKey: "corePath")])
        guard let executable else { connection = "missing"; push(); return }
        connection = "connecting"
        push()
        let pump = EventPump(hcPath: executable)
        self.pump = pump
        pump.onChange = { [weak self] records, state, _, native in
            guard let self, self.generation == current else { return }
            self.terms = records
            self.connection = state
            self.candidates = native
            let liveKeys = Set(native.map { $0.address + ":" + $0.session })
            self.liveTurns = self.liveTurns.filter { liveKeys.contains($0.key) }
            if let watch = self.watch {
                if self.target(address: watch.term.address, session: watch.term.session) == nil {
                    self.stopWatch()
                    self.terminalEvent(watch.id, "ended", "streamClosed")
                } else if let grid = self.currentGrid,
                          let current = self.target(address: watch.term.address, session: watch.term.session),
                          let cols = current.cols, let rows = current.rows, cols != grid.cols || rows != grid.rows {
                    self.stopWatch()
                    self.terminalEvent(watch.id, "ended", "gridChanged")
                }
            }
            if state == "live" { self.scheduleInventory(); self.scheduleRecoverySave(native) }
            else {
                // Core went away (it may come back rebooted): what was seen before no longer proves a deliberate close.
                self.recoverySeen = []
                self.recoveryEpochBox.bump()
                self.recoveryChecked = -1
                self.recoverySignature = ""
            }
            if !self.isolated && self.automaticChat { self.liveChat.track(state == "live" ? native : []) }
            self.observeHandoffs()
            self.push()
        }
        pump.start()
    }

    private func scheduleInventory() {
        guard inventoryRefresh == nil, !inventoryBusy, Date().timeIntervalSince(lastInventory) >= 8 else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.inventoryRefresh = nil
            self?.refreshInventory()
        }
        inventoryRefresh = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: item)
    }

    private func refreshInventory() {
        guard let executable, !inventoryBusy else { return }
        let current = generation
        let appPath = appExecutable
        inventoryBusy = true
        inventoryQueue.async {
            func inspect(_ path: String, _ args: [String]) -> [String: Any]? {
                let result = ProcessHc(path: path).run(args, timeout: 4)
                guard result.code == 0, let data = result.out.data(using: .utf8) else { return nil }
                return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            let rawMachines = inspect(executable, ["machine", "ls", "--json"])?["machines"] as? [[String: Any]] ?? []
            let machines = rawMachines.compactMap { machine -> [String: String]? in
                guard let name = machine["name"] as? String else { return nil }
                return ["name": name, "state": machine["state"] as? String ?? "unknown"]
            }
            let rawSpaces = appPath.flatMap { inspect($0, ["ls"])?["spaces"] as? [[String: Any]] } ?? []
            let spaces = rawSpaces.map { space -> [String: Any] in
                let tabs = (space["tabs"] as? [[String: Any]] ?? []).map { tab -> [String: Any] in
                    let terminals = (tab["terminals"] as? [[String: Any]] ?? []).compactMap { $0["terminal"] as? String }
                    return ["name": tab["name"] as? String ?? "", "terminals": terminals]
                }
                return ["name": space["name"] as? String ?? "", "machine": space["machine"] as? String ?? "", "tabs": tabs]
            }
            DispatchQueue.main.async {
                guard self.generation == current else { return }
                self.inventoryBusy = false
                self.lastInventory = Date()
                let reconnected = Desk.machineStates(self.machines) != Desk.machineStates(machines)
                self.machines = machines
                self.spaces = spaces
                if reconnected { self.scheduleRecoverySave(self.candidates) }   // a computer came back: check what it holds
                self.push()
            }
        }
    }

    private func push() {
        guard ready else { return }
        refreshPublishedMessages()
        call("window.desk.update(payload)", ["payload": pushDiff.trim(["terms": terms, "machines": machines, "spaces": spaces, "systemSounds": systemSounds,
                                                         "connection": connection, "isolated": isolated, "ledger": questionLedger(),
                                                         "preferredLocale": Locale.preferredLanguages.first ?? "en",
                                                         "replies": replies, "teamMessages": teamMessages, "liveMessages": liveMessages + liveReplyArchive.entries, "liveTurns": liveTurns, "automaticChat": automaticChat, "archiveRoles": archiveRoles,
                                                         "legacyProfile": DeskPaths.retainsLegacyProfile, "configuredTeams": configuredTeams, "lineage":lineageStore.publicJSON(), "recovery": recoveryPayload()].merging(handoffPayload()) { $1 }.merging(taskPayload()) { $1 })])
    }

    // MARK: handoffs

    /// The card board only when it changed since the last push; the page keeps the previous one otherwise.
    private func taskPayload() -> [String: Any] {
        guard taskVersion != pushedTaskVersion else { return [:] }
        pushedTaskVersion = taskVersion
        return ["tasks": taskBoard]
    }

    /// The handoff snapshot only when it changed since the last push; the page keeps the previous one otherwise.
    private func handoffPayload() -> [String: Any] {
        let now = Date().timeIntervalSince1970 * 1000
        let signature = handoffs.signature(now: now)
        guard signature != pushedHandoffSignature else { return [:] }
        pushedHandoffSignature = signature
        return ["handoffs": handoffs.webSnapshot(now: now)]
    }

    static func ms(_ iso: String?) -> Double { parsedMs(iso) ?? Date().timeIntervalSince1970 * 1000 }
    static func parsedMs(_ iso: String?) -> Double? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let iso, let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return nil }
        return d.timeIntervalSince1970 * 1000
    }

    /// Lineage edges as handoff signals, re-read only when the lineage file changes.
    private func lineageSignals() -> [HandoffLineage] {
        let file = LineageStore.defaultRoot().appendingPathComponent("state.json")
        let stamp = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date) ?? .distantPast
        if let cache = lineageCache, cache.stamp == stamp { return cache.edges }
        let edges = ((try? lineageStore.snapshot())?.edges ?? []).map { e in
            HandoffLineage(from: HandoffParty(address: e.from.address, session: e.from.session, role: e.from.role),
                           to: HandoffParty(address: e.to.address, session: e.to.session, role: e.to.role),
                           id: e.id, completed: e.completedAt != nil, at: [e.acceptedAt, e.completedAt].compactMap { $0 }.max())
        }
        lineageCache = (stamp, edges)
        return edges
    }

    private func recordHandoff(_ entry: [String: String], source: String) {
        guard let fromAddress = entry["fromAddress"], let toAddress = entry["toAddress"], let body = entry["body"] else { return }
        let from = HandoffParty(address: fromAddress, session: entry["fromSession"] ?? "", role: entry["fromRole"] ?? entry["role"] ?? "")
        let to = HandoffParty(address: toAddress, session: entry["toSession"] ?? "", role: entry["toRole"] ?? entry["recipient"] ?? "")
        handoffs.record(HandoffMessage(from: from, to: to, at: Self.ms(entry["at"]), body: body, source: source))
    }

    /// 2 s while a reply window, a return flash or a fresh arrow is in play; 30 s while anything is merely open.
    private func scheduleHandoffTick(now: Double) {
        let interval: TimeInterval? = handoffs.needsFastTicks(now: now) ? 2 : handoffs.hasOpenEdges ? 30 : nil
        if let timer = handoffTimer, timer.timeInterval == interval ?? -1 { return }
        handoffTimer?.invalidate(); handoffTimer = nil
        guard let interval else { return }
        handoffTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let before = self.handoffSignature
            let tasksBefore = self.taskVersion
            self.observeHandoffs()
            if self.handoffSignature != before || self.taskVersion != tasksBefore { self.push() }
        }
    }

    /// Reads the card board off the main thread (a Python run); a changed board re-observes and repaints.
    private func requestTaskPoll() {
        guard !taskPolling else { return }
        taskPolling = true
        let source = taskSource
        taskQueue.async {
            let board = source.poll()
            DispatchQueue.main.async {
                self.taskPolling = false
                guard let board else { return }
                self.taskBoard = board
                self.taskVersion += 1
                self.observeHandoffs()
                self.push()
            }
        }
    }

    /// Feeds terminal status, herdr-flow labels and lineage edges to the book; saves and repaints only on change.
    private func observeHandoffs() {
        let now = Date().timeIntervalSince1970 * 1000
        var status: [String: String] = [:], sessions: [String: String] = [:], statusSince: [String: Double] = [:]
        for term in candidates where term.state == "live" {
            status[term.address] = term.status ?? ""
            sessions[term.address] = term.session
            if let since = term.statusMs { statusSince[term.address] = Double(since) }
        }
        let byRole = Dictionary(grouping: candidates.filter { $0.state == "live" && $0.role != nil }, by: { $0.role! })
        func party(_ t: Term) -> HandoffParty { HandoffParty(address: t.address, session: t.session, role: t.role ?? "") }
        var flows: [HandoffFlow] = []
        for worker in candidates where worker.state == "live" {
            guard let id = worker.labels["flow.id"], let from = worker.labels["flow.from"], let phase = worker.labels["flow.phase"],
                  worker.labels["flow.session"] == worker.session, let leads = byRole[from], leads.count == 1, let lead = leads.first else { continue }
            let acked = lead.labels["flowack." + id]?.split(separator: "|").dropFirst().first.map(String.init) == worker.role
            flows.append(HandoffFlow(worker: party(worker), lead: party(lead), id: id, phase: acked ? "acked" : phase,
                                     updatedAt: Desk.parsedMs(worker.labels["flow.updated"])))
        }
        requestTaskPoll()
        // Card signals go last: the book takes the last matching flow, so a card outranks a herdr-flow label.
        flows += TaskBoard.flows(board: taskBoard, terms: candidates)
        let lineage = lineageSignals()
        // herdr-reply posts answer the HerdrDesk user just like a transcript reply does.
        // Oldest first, so the first answer after the user's message is the one that closes it.
        for reply in replies.reversed() where reply["kind"] as? String == "reply" && (reply["recipient"] as? String ?? "").isEmpty {
            guard let role = reply["role"] as? String, let session = reply["session"] as? String,
                  let at = Desk.parsedMs(reply["at"] as? String) else { continue }
            handoffs.publishedReply(role: role, session: session, at: at)
        }
        handoffs.observe(HandoffSignals(status: status, session: sessions, flows: flows, lineage: lineage, statusSince: statusSince), now: now)
        handoffs.prune(now: now)
        let signature = handoffs.signature(now: now)
        scheduleHandoffTick(now: now)
        guard signature != handoffSignature else { return }
        handoffSignature = signature
        let copy = HandoffBook(edges: handoffs.edges, cards: handoffs.cards), store = handoffStore
        handoffWrites.async {
            do { try store.save(copy) }
            catch { DispatchQueue.main.async { self.call("window.desk.notice(key)", ["key": "handoffSaveFailed"]) } }
        }
    }

    private func call(_ script: String, _ args: [String: Any]) {
        web.callAsyncJavaScript(script, arguments: args, in: nil, in: .page, completionHandler: nil)
    }

    private func target(address: String, session: String) -> Term? {
        guard connection == "live" else { return nil }
        return candidates.first { $0.address == address && $0.session == session && $0.pid > 0 && $0.state == "live" }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        func field(_ key: String, _ max: Int = 96) -> String? {
            guard let value = body[key] as? String, value.count <= max else { return nil }
            return value
        }
        switch type {
        case "ready":
            ready = true
            pushedHandoffSignature = nil   // a fresh page has no handoff snapshot yet
            pushedTaskVersion = -1
            pushDiff.reset()               // ... nor any of the large parts
            stopWatch()
            push()
        case "copyChatID":
            guard window.isKeyWindow, NSApp.isActive, let value = field("value", 200),
                  value.hasPrefix("room:") || value.hasPrefix("direct:") else { return }
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setString(value, forType: .string) {
                call("window.desk.notice(key)", ["key": "copiedChatID"])
            }
        case "language":
            if let value = field("value", 2), ["en", "ko", "ja"].contains(value) {
                if !isolated { preferences.set(value, forKey: "displayLocale") }
                updateMenu(value)
            }
        case "automaticChat":
            guard !isolated, let enabled = body["enabled"] as? Bool else { return }
            preferences.set(enabled, forKey: "automaticChat")
            liveChat.track(enabled && connection == "live" ? candidates : [])
            if !enabled { liveMessages.removeAll(); liveTurns.removeAll() }
            push()
        case "sound":
            guard !isolated, environment["HERDRDESK_NO_SEND"] != "1" else { return }
            // `system`: a macOS alert sound the user picked for done / handoff / attention. `cue`: the app's own clicks.
            let sound: NSSound?
            if let name = field("system", 64) {
                guard SystemSounds.allowed(name, in: systemSounds) else { return }
                sound = NSSound(contentsOf: SystemSounds.folder.appendingPathComponent(name + ".aiff"), byReference: true) ?? NSSound(named: name)
            } else if let cue = field("cue", 8), ["sent", "done"].contains(cue) {
                sound = Bundle.main.url(forResource: cue, withExtension: "wav", subdirectory: "sounds").flatMap { NSSound(contentsOf: $0, byReference: true) }
            } else { return }
            guard let sound else { return }
            currentSound?.stop()
            currentSound = sound
            currentSound?.play()
        case "companion":
            if let state = body["state"] as? [String: Any] { companion?.update(state) }
        case "refresh":
            refreshInventory()
        case "chooseCore":
            let dialog = NSOpenPanel()
            dialog.canChooseDirectories = false
            dialog.allowsMultipleSelection = false
            dialog.showsHiddenFiles = true
            dialog.beginSheetModal(for: window) { result in
                guard result == .OK, let url = dialog.url, url.lastPathComponent == "hc",
                      FileManager.default.isExecutableFile(atPath: url.path) else {
                    if result == .OK { self.call("window.desk.notice(key)", ["key": "invalidCore"]) }
                    return
                }
                self.preferences.set(url.path, forKey: "corePath")
                self.connect()
            }
        case "waitingTarget":
            guard let kind = field("kind"), let actorAddress = field("actorAddress"), let actorSession = field("actorSession"),
                  let actorRole = field("actorRole"), let address = field("address"), let session = field("session"), let role = field("role"),
                  target(address:actorAddress,session:actorSession) != nil, target(address:address,session:session) != nil,
                  let client = sender() else { call("window.desk.notice(key)",["key":"waitingStale"]); return }
            let request = WaitingTargetRequest(kind:kind,actorAddress:actorAddress,actorSession:actorSession,actorRole:actorRole,
                targetAddress:address,targetSession:session,targetRole:role,requestID:field("requestID"))
            if let pendingId = field("pendingId") {
                guard let taskId = field("taskId"), let origin = field("originRequestId"), let conversation = field("conversationId",256), let requestId = field("requestID"),
                      lineageStore.validatesPending(id:pendingId,taskId:taskId,origin:origin,conversation:conversation,requestId:requestId,
                        requester:LineageIdentity(address:actorAddress,session:actorSession,role:actorRole),target:LineageIdentity(address:address,session:session,role:role)) else {
                    call("window.desk.notice(key)",["key":"waitingStale"]); return
                }
            }
            commands.async {
                let current = resolveWaitingTarget(request,client:client)
                DispatchQueue.main.async {
                    guard let current, self.target(address:actorAddress,session:actorSession) != nil,
                          self.target(address:address,session:session) != nil else { self.call("window.desk.notice(key)",["key":"waitingStale"]); return }
                    self.open(current)
                }
            }
        case "answer", "approval":
            guard let id = field("id"), let sender = sender() else { return }
            guard connection == "live",
                  case .success(let asker) = askerOf(questionId: id, in: candidates),
                  let role = asker.role else {
                questionResult(id, "refused")
                return
            }
            if type == "approval" {
                commands.async {
                    let destination = sender.fetchApproval(questionId: id, askerRole: role)
                    DispatchQueue.main.async {
                        if case .success(let term) = destination,
                           self.target(address: term.address, session: term.session) != nil {
                            self.call("window.desk.approvalTarget(request)", ["request": [
                                "id": id, "address": term.address, "session": term.session
                            ]])
                        }
                        else { self.call("window.desk.notice(key)", ["key": "openFailed"]) }
                    }
                }
            } else if let answer = field("text", 2000) {
                let ids = body["attachments"] as? [String] ?? []
                guard ids.count <= AttachmentStore.maxCount, Set(ids).count == ids.count, ids.allSatisfy({ $0.count <= 64 }),
                      ids.isEmpty || attachmentKey(asker) != nil, !(answer.isEmpty && ids.isEmpty) else { questionResult(id, "refused"); return }
                sendAnswer(id: id, asker: asker, role: role, text: answer, attachmentIDs: ids, client: sender)
            } else {
                questionResult(id, "refused")
            }
        case "chatImages":
            guard let token=field("token",64), let id=field("id",160), let role=field("role",64),
                  let session=field("session",128), let text=field("body",8192) else { return }
            let requested=ChatImageRecord(id:id,role:role,session:session,body:text)
            if let sent=sentImageLedger(requested) {
                attachmentQueue.async {
                    let previews=self.sentChatImages.load(requested) ?? [["name":"첨부 이미지","thumbnail":""]]
                    DispatchQueue.main.async {
                        self.call("window.desk.chatImages(payload)",["payload":["token":token,"previews":self.sentImageLedger(requested) == sent ? previews : []]])
                    }
                }
                return
            }
            guard let record=chatImageRecord(id:id,role:role,session:session,body:text) else {
                call("window.desk.chatImages(payload)",["payload":["token":token,"previews":[]]]); return
            }
            attachmentQueue.async {
                let previews=record.previews()
                DispatchQueue.main.async {
                    let current=self.chatImageRecord(id:id,role:role,session:session,body:text)
                    self.call("window.desk.chatImages(payload)",["payload":["token":token,"previews":current == record ? previews : []]])
                }
            }
        case "chatImageLarge":
            // The viewer asks for one image of an already shown agent message at viewer size. Same record binding and
            // file rules as the thumbnails; sent images (kept only as thumbnails) get nothing and the page keeps its thumbnail.
            guard let token=field("token",64), let id=field("id",160), let role=field("role",64),
                  let session=field("session",128), let text=field("body",8192),
                  let index=body["index"] as? Int, (0..<4).contains(index) else { return }
            let reply: (String) -> Void = { image in
                self.call("window.desk.chatImageLarge(payload)",["payload":["token":token,"index":index,"image":image]])
            }
            guard let record=chatImageRecord(id:id,role:role,session:session,body:text) else { reply(""); return }
            attachmentQueue.async {
                let paths=ChatImagePolicy.references(record.body)
                let image=index < paths.count ? ChatImagePolicy.largePreview(paths[index])?.base64EncodedString() ?? "" : ""
                DispatchQueue.main.async {
                    reply(self.chatImageRecord(id:id,role:role,session:session,body:text) == record ? image : "")
                }
            }
        case "attachments", "attach", "detach":
            guard let address = field("address", 160), let session = field("session") else { return }
            let term = target(address: address, session: session)
            let archivedRole = (type == "attachments" && address.hasPrefix("archive:") && session == "archive")
                ? String(address.dropFirst("archive:".count)) : nil
            let key = term.flatMap { attachmentKey($0) } ?? archivedRole.flatMap { archiveRoles.contains($0) ? $0 : nil }
            guard let key else {
                attachmentResult(address: address, session: session, items: [], completed: type == "attach",
                                 error: type == "attachments" ? nil : "attachmentFailed")
                return
            }
            if type == "attach" {
                let maxEncoded = AttachmentStore.maxInput * 4 / 3 + 16
                guard let term, term.isAgent, let name = field("name", 200), let encoded = body["data"] as? String,
                      encoded.utf8.count <= maxEncoded else {
                    attachmentResult(address: address, session: session, items: nil, completed: true, error: "attachmentFailed")
                    return
                }
                modifyAttachments(key: key, address: address, session: session, completed: true, change: {
                    guard let media = Data(base64Encoded: encoded) else { throw AttachError.notImage }
                    _ = try self.attachmentStore.add(role: key, name: name, data: media)
                })
            } else if type == "detach" {
                guard term?.isAgent == true, let id = field("id", 64) else { return }
                modifyAttachments(key: key, address: address, session: session, change: {
                    self.attachmentStore.remove(role: key, id: id)
                })
            } else {
                modifyAttachments(key: key, address: address, session: session)
            }
        case "machine":
            guard let token = field("token", 64) else { return }
            func reply(_ payload: [String: Any]) { call("window.desk.machineResult(payload)", ["payload": payload.merging(["token": token]) { a, _ in a }]) }
            guard environment["HERDRDESK_NO_SEND"] != "1", window.isKeyWindow, NSApp.isActive,
                  let argv = MachineSettings.argv(body, terms: candidates) else { reply(["ok": false, "error": "refused"]); return }
            guard let exe = taskExecutable else { reply(["ok": false, "error": "herdr-task not found"]); return }
            (MachineSettings.isLong(argv) ? cloneQueue : machineQueue).async {
                let result = ProcessHc(path: exe).run(argv, timeout: MachineSettings.timeout(argv))
                let parsed = result.out.split(separator: "\n").last.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) }
                DispatchQueue.main.async {
                    if result.code == 0, !result.timedOut {
                        reply(["ok": true, "result": parsed ?? [:]])
                        if argv[1] != "suggest" { self.requestTaskPoll() }
                    } else {
                        let reason = result.timedOut ? "timed out" : result.err.replacingOccurrences(of: "refused: ", with: "")
                        reply(["ok": false, "error": String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))])
                    }
                }
            }
        case "recovery":
            guard recoveryEnabled, recoveryBusy.isEmpty else { return }
            switch field("action", 16) {
            case "check": runRecovery(restore: false)
            case "restore":
                guard environment["HERDRDESK_NO_SEND"] != "1", window.isKeyWindow, NSApp.isActive else { return }
                runRecovery(restore: true)
            default: return
            }
        case "terminalUnwatch":
            if field("id") == watch?.id { stopWatch() }
        case "terminalInput":
            guard environment["HERDRDESK_NO_SEND"] != "1", window.isKeyWindow, NSApp.isActive,
                  let watch, watch.interactive, watch.id == field("id"),
                  watch.term.address == field("address", 160), watch.term.session == field("session"),
                  target(address: watch.term.address, session: watch.term.session) != nil,
                  let value = field("data", 32 * 1024) else { return }
            observer?.type(Data(value.utf8))
        case "terminalWatch", "open", "send":
            guard let id = field("id"), let address = field("address"), let session = field("session") else { return }
            guard let term = target(address: address, session: session) else {
                if type == "send" { sendResult(id, "refused") }
                if type == "terminalWatch" { terminalEvent(id, "ended", "sessionChanged") }
                if type == "open" { call("window.desk.notice(key)", ["key": "openFailed"]) }
                return
            }
            if type == "terminalWatch" {
                startWatch(id: id, term: term, interactive: environment["HERDRDESK_NO_SEND"] != "1")
                return
            }
            if type == "open" { open(term); return }
            guard term.isAgent, let text = field("text", 2000), let executable else {
                sendResult(id, "refused"); return
            }
            let ids = body["attachments"] as? [String] ?? []
            let uniqueRole = !DeskPaths.retainsLegacyProfile || term.role == nil ||
                candidates.filter { $0.role == term.role && $0.isAgent && $0.state == "live" }.count == 1
            guard uniqueRole, ids.count <= AttachmentStore.maxCount, Set(ids).count == ids.count,
                  ids.allSatisfy({ $0.count <= 64 }), let key = attachmentKey(term) else { sendResult(id, "refused"); return }
            send(id: id, text: text, term: term, executable: executable, attachmentIDs: ids, key: key, conversationId:field("conversationId",256))
        default: break
        }
    }

    // MARK: agent recovery

    static func machineStates(_ list: [[String: Any]]) -> String {
        list.map { (($0["name"] as? String) ?? "") + "=" + (($0["state"] as? String) ?? "") }.sorted().joined(separator: ",")
    }

    private func recoveryRunner() -> RecoveryRunner? {
        guard let executable else { return nil }
        let locale = preferences.string(forKey: "displayLocale").map { String($0.prefix(2)) } ?? "en"
        return RecoveryRunner(hc: ProcessHc(path: executable), app: appExecutable.map { ProcessHc(path: $0) }, locale: locale)
    }

    /// Saves again in the background: after the first look of a connection, when agents start, end or move, and (at most
    /// once a minute) when their turns advance, which is where a new conversation inside the same agent shows up.
    private func scheduleRecoverySave(_ native: [Term]) {
        guard recoveryEnabled else { return }
        let agents = native.filter { $0.isAgent && $0.state == "live" }
        // Agents, plus terminals carrying a role (a shell a reboot left behind), plus which computers are connected.
        let watched = native.filter { $0.state == "live" && ($0.isAgent || !($0.role ?? "").isEmpty) }
        let rows: [String] = watched.map { term in
            let app: String = term.app ?? ""
            return term.address + ":" + term.session + ":" + app + ":" + Recovery.labelSignature(term.labels)
        }
        let signature: String = rows.sorted().joined(separator: "|") + "#" + Desk.machineStates(machines)
        let turns = agents.map { $0.address + ":" + String($0.turn) }.sorted().joined(separator: "|")
        guard let delay = Recovery.saveDelay(checked: recoveryChecked == generation, structural: signature != recoverySignature,
                                             turns: turns != recoveryTurns, sinceLast: Date().timeIntervalSince(recoveryLastSave)) else { return }
        let structural = signature != recoverySignature || recoveryChecked != generation
        recoverySignature = signature
        recoveryTurns = turns
        if !structural, recoverySave != nil { return }      // a save is already on its way
        recoveryChecked = generation
        recoverySave?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveRecovery() }
        recoverySave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Tries the save again later (it was skipped during a check or could not collect).
    private func retryRecoverySave(after delay: TimeInterval) {
        guard recoverySave == nil else { return }
        let item = DispatchWorkItem { [weak self] in self?.saveRecovery() }
        recoverySave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func saveRecovery() {
        recoverySave = nil
        guard connection == "live", let runner = recoveryRunner() else { return }
        guard recoveryBusy.isEmpty else { retryRecoverySave(after: 15); return }
        let current = generation, epoch = recoveryEpoch, seen = recoverySeen, store = recoveryStore
        recoveryLastSave = Date()
        recoveryQueue.async {
            guard let runtime = try? runner.collector.collect() else {
                DispatchQueue.main.async { if self.generation == current { self.retryRecoverySave(after: 30) } }
                return
            }
            let (registry, seenNow) = Recovery.merge(store.load(), runtime: runtime, seen: seen, now: RecoveryRunner.timestamp())
            var saved = registry, failure = ""
            guard self.recoveryEpochBox.value == epoch else { return }   // Core went away meanwhile
            if registry != store.load() {
                do { try store.save(registry) } catch { saved = store.load(); failure = "the recovery list could not be saved: \(error)" }
            }
            // The sidebar follows what runs now (a resume that finished starting, a shell left by a reboot).
            let report = runner.check(saved, runtime: runtime)
            DispatchQueue.main.async {
                guard self.generation == current, self.recoveryEpoch == epoch else { return }
                self.recoverySeen = seenNow
                self.recoverySaved = saved
                if !failure.isEmpty { self.recoveryError = String(failure.prefix(300)) }
                else if self.recoveryError.hasPrefix("the recovery list could not be saved") { self.recoveryError = "" }
                if self.recoveryBusy.isEmpty {
                    var report = report
                    // After a recovery the sidebar keeps its result (until dismissed) while later checks refresh the roles.
                    if let last = self.recoveryReport, last.applied { report.applied = true; report.at = last.at }
                    self.recoveryReport = report
                }
                self.push()
            }
        }
    }

    private func runRecovery(restore: Bool) {
        guard let runner = recoveryRunner() else { return }
        recoveryBusy = restore ? "restoring" : "checking"
        recoveryError = ""
        push()
        let store = recoveryStore
        recoveryQueue.async {
            var report: RecoveryReport?, failure = ""
            do { report = restore ? try runner.restore(store.load()) : try runner.check(store.load()) }
            catch { failure = String("\(error)".prefix(300)) }
            DispatchQueue.main.async {
                self.recoveryBusy = ""
                self.recoveryError = failure
                if let report { self.recoveryReport = report }
                self.push()
                self.recoverySignature = ""      // save (and refresh the sidebar) again from what runs now
                self.scheduleRecoverySave(self.candidates)
            }
        }
    }

    private func recoveryPayload() -> [String: Any] {
        guard recoveryEnabled else { return ["enabled": false] }
        var payload: [String: Any] = ["enabled": true, "saved": recoverySaved.roles.count, "savedAt": recoverySaved.savedAt ?? "",
                                      "busy": recoveryBusy, "error": recoveryError]
        if let report = recoveryReport {
            payload["report"] = ["at": report.at, "applied": report.applied, "ready": report.ready, "resumable": report.resumable,
                                 "attention": report.needsAttention,
                                 "roles": report.roles.map { ["title": $0.title, "action": $0.action.rawValue, "reason": $0.reason] }]
        }
        return payload
    }

    private func sender() -> AnswerSender? {
        guard let executable else { return nil }
        return AnswerSender(hc: ProcessHc(path: executable), ledger: Ledger(dir: Ledger.defaultDir()),
                            lockPath: AnswerSender.defaultLockPath(), originReceipts:userDispatchReceipts, lineage:lineageStore)
    }

    private func refreshPublishedMessages() {
        let signature = candidates.compactMap { term in
            term.labels["result.latest"].map { term.address + ":" + $0 + ":" + (term.labels["result.revision"] ?? "") }
        }.sorted()
        replySignature = signature
        // Re-read the records only when a role folder changed (files are written by rename) or a label points at a new one.
        let stamp = resultsFolderStamp() + "|" + signature.joined(separator: ",")
        if stamp == resultsStamp { return }
        resultsStamp = stamp
        let records = ResultStore(root: ResultStore.defaultRoot()).load().filter { !$0.withdrawn }
        let personal = records.filter { ["reply", "message", "progress"].contains($0.kind) || ($0.kind == "agent-handoff" && !$0.recipient.isEmpty) }
        let readable = DeskPaths.retainsLegacyProfile ? personal : Array(personal.prefix(160))
        func asDictionary(_ item: ResultRecord) -> [String: Any] {
            ["id": item.id, "role": item.role, "session": item.session, "at": item.at, "kind": item.kind, "team": item.team, "recipient": item.recipient,
             "body": DeskPaths.retainsLegacyProfile ? (item.body.isEmpty ? item.summary : item.body) : String(item.body.prefix(8192))]
        }
        replies = readable.map(asDictionary)
        teamMessages = records.filter { ["team-message", "progress"].contains($0.kind) && !$0.team.isEmpty }.prefix(300).map(asDictionary)
    }

    private func resultsFolderStamp() -> String {
        let root = ResultStore.defaultRoot(), fm = FileManager.default
        guard let roles = try? fm.contentsOfDirectory(atPath: root.path) else { return "none" }
        return roles.sorted().map { role -> String in
            let date = (try? fm.attributesOfItem(atPath: root.appendingPathComponent(role).path)[.modificationDate] as? Date) ?? .distantPast
            return role + "@" + String(date.timeIntervalSince1970)
        }.joined(separator: ";")
    }

    private func questionLedger() -> [String: String] {
        let ledger = Ledger(dir: Ledger.defaultDir())
        let ids = Set(candidates.compactMap { $0.labels["ask.id"] })
        return ids.reduce(into: [:]) { result, id in
            if let entry = ledger.read(id) { result[id] = entry.state }
        }
    }

    private func questionResult(_ id: String, _ state: String) {
        call("window.desk.questionResult(id,state)", ["id": id, "state": state])
        push()
    }

    /// Sends the answer the person typed and submitted in the focused HerdrDesk window; no second confirmation.
    /// Images come from the asker's own attachment tray (the same one its conversation's composer uses) and are
    /// cleared once the answer is sent.
    private func sendAnswer(id: String, asker: Term, role: String, text: String, attachmentIDs: [String], client: AnswerSender) {
        guard window.isKeyWindow, NSApp.isActive, attachmentIDs.isEmpty ? checkText(text) == nil : text.count <= maxAnswerLength,
              validate(term: asker, questionId: id) == nil,
              environment["HERDRDESK_NO_SEND"] != "1" else { questionResult(id, "refused"); return }
        let key = attachmentKey(asker)
        commands.async {
            var files: [Attachment] = []
            if !attachmentIDs.isEmpty {
                guard let key, let resolved = self.attachmentQueue.sync(execute: { self.attachmentStore.resolve(role: key, ids: attachmentIDs) }) else {
                    DispatchQueue.main.async { self.questionResult(id, "refused") }; return
                }
                files = resolved
            }
            let state: String
            switch client.send(role: role, questionId: id, text: text, attachments: files) {
            case .sent:
                state = "sent"
                if let key, !files.isEmpty {
                    self.modifyAttachments(key: key, address: asker.address, session: asker.session) {
                        self.attachmentStore.clear(role: key, ids: attachmentIDs)
                    }
                }
            case .notSent: state = "notSent"
            case .needsCheck: state = "needsCheck"
            case .refused: state = "refused"
            }
            DispatchQueue.main.async { self.questionResult(id, state) }
        }
    }

    private func sentImageLedger(_ record: ChatImageRecord) -> LedgerEntry? {
        guard let entry=Ledger(dir:DirectSender.defaultDir()).read(record.id), entry.state == "sent",
              entry.role == record.role, entry.session == record.session else { return nil }
        return entry
    }

    /// Accepted in-memory records only. No page-supplied paths, transcript reads or result-folder scans.
    private func chatImageRecord(id: String, role: String, session: String, body: String) -> ChatImageRecord? {
        var rows = replies + teamMessages
        rows += liveMessages.map { $0.mapValues { $0 as Any } }
        rows += liveReplyArchive.entries.map { $0.mapValues { $0 as Any } }
        let accepted=rows.filter {
            ["reply","team-message"].contains($0["kind"] as? String ?? "") &&
            $0["id"] as? String == id && $0["role"] as? String == role &&
            $0["session"] as? String == session && $0["body"] as? String == body
        }
        guard !accepted.isEmpty else { return nil }
        let current=candidates.filter { $0.role == role && $0.session == session && $0.state == "live" && !$0.address.contains("/") }
        guard current.count == 1, accepted.allSatisfy({ row in
            (row["fromAddress"] as? String).map { $0 == current[0].address } ?? true
        }) else { return nil }
        return ChatImageRecord(id:id,role:role,session:session,body:body)
    }

    private func attachmentKey(_ term: Term) -> String? { AttachmentKey.make(for: term, among: candidates) }

    private func loadArchivedAttachmentRoles() {
        attachmentQueue.async {
            let roles = self.attachmentStore.rolesWithDrafts()
            DispatchQueue.main.async { self.archiveRoles = roles; self.push() }
        }
    }

    private func attachmentPayload(_ key: String) -> [[String: Any]] {
        attachmentStore.list(role: key).map { item in
            ["id": item.id, "name": item.name, "thumbnail": attachmentStore.thumbnail(for: item)?.base64EncodedString() ?? ""]
        }
    }

    private func attachmentResult(address: String, session: String, items: [[String: Any]]?, completed: Bool, error: String?) {
        call("window.desk.attachmentResult(payload)", ["payload": [
            "address": address, "session": session, "items": items.map { $0 as Any } ?? NSNull(),
            "completed": completed, "error": error.map { $0 as Any } ?? NSNull()
        ]])
    }

    private func modifyAttachments(key: String, address: String, session: String, completed: Bool = false,
                                   after: (() -> Void)? = nil, change: @escaping () throws -> Void = {}) {
        attachmentQueue.async {
            let failure: String?
            do { try change(); failure = nil }
            catch AttachError.tooMany { failure = "attachmentLimit" }
            catch { failure = "attachmentFailed" }
            let items = self.attachmentPayload(key)
            let roles = self.attachmentStore.rolesWithDrafts()
            DispatchQueue.main.async {
                self.archiveRoles = roles
                self.attachmentResult(address: address, session: session, items: items, completed: completed, error: failure)
                after?()
            }
        }
    }

    private func send(id: String, text: String, term: Term, executable: String, attachmentIDs: [String], key: String, conversationId: String?) {
        commands.async {
            let files = self.attachmentQueue.sync { self.attachmentStore.resolve(role: key, ids: attachmentIDs) }
            guard let files else { DispatchQueue.main.async { self.sendResult(id, "refused") }; return }
            // Capture only native-resolved draft images before send/clear. Failed sends never retain these.
            let previews: [[String: String]] = self.attachmentQueue.sync {
                files.map { ["name":$0.name,"thumbnail":self.attachmentStore.thumbnail(for:$0)?.base64EncodedString() ?? ""] }
            }
            let base = AnswerSender(hc: ProcessHc(path: executable), ledger: Ledger(dir: Ledger.defaultDir()), lockPath: AnswerSender.defaultLockPath(), originReceipts:self.userDispatchReceipts, lineage:self.lineageStore)
            let direct = DirectSender(base: base, ledger: Ledger(dir: DirectSender.defaultDir()))
            let outcome = self.environment["HERDRDESK_NO_SEND"] == "1" ? SendOutcome.notSent("") :
                direct.send(to: term, messageId: id, text: text, attachments: files,conversationId:conversationId)
            let state: String
            switch outcome {
            case .sent:
                state = "sent"
                if !previews.isEmpty {
                    let record=ChatImageRecord(id:id,role:term.role ?? term.address,session:term.session,body:text)
                    do { try self.sentChatImages.save(record,previews:previews) }
                    catch { DispatchQueue.main.async { self.call("window.desk.notice(message)",["message":"이미지 미리보기 보존에 실패했습니다."]) } }
                }
                DispatchQueue.main.async {
                    self.handoffs.record(HandoffMessage(from: .desk, to: HandoffParty(address: term.address, session: term.session, role: term.role ?? ""),
                                                        at: Date().timeIntervalSince1970 * 1000, body: text, source: "desk"))
                    self.observeHandoffs()
                    self.push()
                }
                if !files.isEmpty {
                    self.modifyAttachments(key: key, address: term.address, session: term.session,
                                           after: { self.sendResult(id, "sent", previews: previews) }) {
                        self.attachmentStore.clear(role: key, ids: attachmentIDs)
                    }
                    return
                }
            case .notSent: state = "notSent"
            case .needsCheck: state = "needsCheck"
            case .refused: state = "refused"
            }
            DispatchQueue.main.async { self.sendResult(id, state, previews: state == "sent" ? previews : []) }
        }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        guard frame.isMainFrame else { completionHandler(nil); return }
        let dialog = NSOpenPanel()
        dialog.canChooseDirectories = false
        dialog.allowsMultipleSelection = parameters.allowsMultipleSelection
        dialog.allowedContentTypes = [.image]
        dialog.beginSheetModal(for: window) { result in completionHandler(result == .OK ? dialog.urls : nil) }
    }

    private func sendResult(_ id: String, _ state: String, previews: [[String: String]] = []) {
        call("window.desk.sendResult(id, state, previews)", ["id": id, "state": state, "previews": previews])
    }

    private func open(_ term: Term) {
        guard !isolated, let path = appExecutable else { call("window.desk.notice(key)", ["key": "openFailed"]); return }
        func focus(_ attempts: Int) {
            guard target(address: term.address, session: term.session) != nil else {
                call("window.desk.notice(key)", ["key": "openFailed"]); return
            }
            commands.async {
                let command = term.isAgent ? "agent.focus" : "terminal.peek"
                let result = ProcessHc(path: path).run(["do", command, "--terminal", term.address], timeout: 3)
                DispatchQueue.main.async {
                    if result.code == 0 { NSRunningApplication.runningApplications(withBundleIdentifier: "dev.herdr.app").first?.activate() }
                    else if attempts > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focus(attempts - 1) } }
                    else { self.call("window.desk.notice(key)", ["key": "openFailed"]) }
                }
            }
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: "dev.herdr.app").isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.herdr.app") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                DispatchQueue.main.async {
                    if error == nil { focus(4) }
                    else { self.call("window.desk.notice(key)", ["key": "openFailed"]) }
                }
            }
        } else { focus(0) }
    }

    private func startWatch(id: String, term: Term, interactive: Bool = false) {
        stopWatch()
        guard let executable else { return }
        watch = (id, term, interactive)
        let generation = watchGeneration
        let stream = TerminalObserver(path: executable, target: term, interactive: interactive) { [weak self] event in
            DispatchQueue.main.async {
                guard let self, self.watchGeneration == generation, let current = self.observer else { return }
                switch event {
                case .ready(let cols, let rows, let followsSize):
                    if !followsSize { self.currentGrid = (cols, rows) }
                    self.terminalEvent(id, "grid", "", cols, rows, canType: interactive)
                case .size(let cols, let rows):
                    self.terminalEvent(id, "grid", "", cols, rows, canType: interactive)
                case .output(let bytes):
                    self.web.callAsyncJavaScript("return await window.desk.terminalOutput(id, data)",
                                                 arguments: ["id": id, "data": bytes.base64EncodedString()], in: nil, in: .page) { result in
                        guard self.watchGeneration == generation else { return }
                        if case .success(let ok) = result, ok as? Bool == true { current.consumed(bytes.count) }
                        else { self.stopWatch(); self.terminalEvent(id, "ended", "streamClosed") }
                    }
                case .ended:
                    self.stopWatch()
                    self.terminalEvent(id, "ended", "streamClosed")
                }
            }
        }
        observer = stream
        stream.start()
    }

    private func terminalEvent(_ id: String, _ state: String, _ key: String, _ cols: Int = 0, _ rows: Int = 0, canType: Bool = false) {
        call("window.desk.terminalEvent({id,state,message,cols,rows,canType})",
             ["id": id, "state": state, "message": key, "cols": cols, "rows": rows, "canType": canType])
    }

    private func stopWatch() {
        watchGeneration += 1
        watch = nil
        observer?.stop()
        observer = nil
        currentGrid = nil
    }

    func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.isFileURL && url.standardizedFileURL.path == index.standardizedFileURL.path {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        guard action.navigationType == .linkActivated, action.sourceFrame.isMainFrame,
              action.targetFrame?.isMainFrame == true, window.isKeyWindow, NSApp.isActive else { return }
        switch ChatShortcut.destination(url) {
        case .website(let link), .folder(let link):
            if !NSWorkspace.shared.open(link) { call("window.desk.notice(key)", ["key": "shortcutOpenFailed"]) }
        case .reveal(let file):
            NSWorkspace.shared.activateFileViewerSelecting([file])
        case .browser(let file):
            // A saved page has no reliable default app of its own; use the app that opens web links.
            guard let browser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else {
                NSWorkspace.shared.activateFileViewerSelecting([file]); return
            }
            NSWorkspace.shared.open([file], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if error != nil { DispatchQueue.main.async { NSWorkspace.shared.activateFileViewerSelecting([file]) } }
            }
        case .markdown(let file):
            guard let text = ChatShortcut.markdownText(file) else { NSWorkspace.shared.activateFileViewerSelecting([file]); return }
            call("window.desk.showDocument(doc)", ["doc": ["name": file.lastPathComponent, "path": file.path, "text": text]])
        case nil:
            call("window.desk.notice(key)", ["key": "shortcutOpenFailed"])
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { ready = false; stopWatch() }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ note: Notification) { stopWatch(); pump?.stop(); liveChat.track([]) }

    private func updateMenu(_ locale: String) {
        let code = locale.split(separator: "-").first.map(String.init) ?? "en"
        currentLanguage = code
        let edit: [String], quit: String
        switch code {
        case "ko": edit = ["편집", "잘라내기", "복사", "붙여넣기", "모두 선택"]; quit = "HerdrDesk 종료"
        case "ja": edit = ["編集", "カット", "コピー", "ペースト", "すべてを選択"]; quit = "HerdrDesk を終了"
        default: edit = ["Edit", "Cut", "Copy", "Paste", "Select All"]; quit = "Quit HerdrDesk"
        }
        let main = NSMenu(), appItem = NSMenuItem(), editItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let menu = NSMenu(title: edit[0])
        menu.addItem(withTitle: edit[1], action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: edit[2], action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: edit[3], action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: edit[4], action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = menu
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func reportCompatibilityIfRequested() {
        guard let path = environment["HERDRDESK_QA_REPORT"] else { return }
        let probeKeys = ["HERDRDESK_QA_REPLY_ID", "HERDRDESK_QA_REPLY_ROLE", "HERDRDESK_QA_REPLY_SESSION", "HERDRDESK_QA_REPLY_NONCE"]
        let values = probeKeys.compactMap { environment[$0] }
        var script = "window.desk?.compatibilitySummary()"
        var targetNonce: String?
        if !values.isEmpty {
            guard values.count == 4, values.allSatisfy({ !$0.isEmpty && $0.count <= 128 }),
                  ReplyProbeID.matches(values[0],session:values[2]) else { return }
            targetNonce = values[3]
            var probe: [String: Any] = ["id":values[0], "role":values[1], "session":values[2], "nonce":values[3],
                                        "select":environment["HERDRDESK_QA_SELECT_REPLY"] == "1"]
            if let address = ReplyProbeID.address(values[0]) { probe["address"] = address }
            guard let data = try? JSONSerialization.data(withJSONObject: probe), let json = String(data:data,encoding:.utf8) else { return }
            script = "window.desk?.compatibilitySummary(\(json))"
        }
        let reportScript = script
        func attempt(_ remaining: Int) {
            self.web.evaluateJavaScript(reportScript) { payload, _ in
                var report: Any = payload ?? [:]
                if let nonce = targetNonce {
                    var safe: [String: Any] = ["nonce":nonce, "snapshotCount":0, "mergedCount":0, "domCount":0, "visible":false, "inViewport":false]
                    if let row = payload as? [String: Any], row["nonce"] as? String == nonce {
                        for key in ["snapshotCount", "mergedCount", "domCount"] {
                            if let count = row[key] as? Int, count >= 0 { safe[key] = count }
                        }
                        for key in ["visible", "inViewport"] { if let flag = row[key] as? Bool { safe[key] = flag } }
                    }
                    if remaining > 0 && ((safe["mergedCount"] as? Int ?? 0) != 1 || (safe["domCount"] as? Int ?? 0) == 0 || safe["visible"] as? Bool != true || safe["inViewport"] as? Bool != true) {
                        DispatchQueue.main.asyncAfter(deadline:.now() + 0.5) { attempt(remaining - 1) }
                        return
                    }
                    report = safe
                }
                guard JSONSerialization.isValidJSONObject(report),
                      let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) else { return }
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { attempt(targetNonce == nil ? 0 : 19) }
    }

    private func captureIfRequested() {
        guard isolated, let path = environment["HERDRDESK_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if let js = self.environment["HERDRDESK_SNAPSHOT_JS"] {
                self.web.evaluateJavaScript(js) { _, error in
                    if let error { NSLog("Fixture JavaScript error: %@", error.localizedDescription) }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.web.takeSnapshot(with: nil) { image, _ in
                    if let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                       let png = bitmap.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: path))
                    }
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

/// A counter read from the recovery queue and bumped on the main thread.
final class RecoveryEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return current }
    func bump() { lock.lock(); current += 1; lock.unlock() }
}

if CommandLine.arguments.dropFirst().first == "--recovery" {
    // `HerdrDesk --recovery check|save|restore`: the same recovery as the app's button, from a terminal.
    let action = CommandLine.arguments.dropFirst(2).first ?? "check"
    guard ["check", "save", "restore"].contains(action), let hc = ProcessHc.resolvePath() else {
        FileHandle.standardError.write(Data("usage: HerdrDesk --recovery check|save|restore\n".utf8)); exit(64)
    }
    let app = ProcessHc.resolveExecutable("herdr-app", overrides: [ProcessInfo.processInfo.environment["HERDRDESK_APP"]]).map { ProcessHc(path: $0) }
    let locale = UserDefaults.standard.string(forKey: "displayLocale").map { String($0.prefix(2)) } ?? "en"
    let runner = RecoveryRunner(hc: ProcessHc(path: hc), app: app, locale: locale)
    let store = RecoveryStore()
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
        switch action {
        case "save":
            let (registry, _) = Recovery.merge(store.load(), runtime: try runner.collector.collect(), seen: [], now: RecoveryRunner.timestamp())
            try store.save(registry)
            FileHandle.standardOutput.write(Data("saved \(registry.roles.count) agents to \(store.url.path)\n".utf8))
        default:
            let report = action == "restore" ? try runner.restore(store.load()) : try runner.check(store.load())
            FileHandle.standardOutput.write(try encoder.encode(report)); FileHandle.standardOutput.write(Data([10]))
            exit(report.ready ? 0 : 2)
        }
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1)
    }
    exit(0)
}
if CommandLine.arguments.dropFirst().first == "--lineage" {
    var output: [String:Any] = ["recorded":false,"error":"invalid"]
    do {
        guard CommandLine.arguments.count == 3, let caller = ProcessInfo.processInfo.environment["HC_TERMINAL_ID"],
              let hc = ProcessHc.resolvePath() else { throw LineageError.ownership }
        let bytes = FileHandle.standardInput.readData(ofLength:65537)
        guard bytes.count <= 65536, let input = try JSONSerialization.jsonObject(with:bytes) as? [String:Any] else { throw LineageError.invalid }
        output = try LineageCommand.apply(operation:CommandLine.arguments[2],input:input,caller:caller,hc:ProcessHc(path:hc),store:LineageStore(root:LineageStore.defaultRoot()))
    } catch { output = ["recorded":false,"error":(error as? LineageError)?.rawValue ?? "storage"] }
    if let bytes = try? JSONSerialization.data(withJSONObject:output,options:.sortedKeys) { FileHandle.standardOutput.write(bytes); FileHandle.standardOutput.write(Data([10])) }
    exit(output["recorded"] as? Bool == true ? 0 : 1)
}
let app = NSApplication.shared
let delegate = Desk()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
