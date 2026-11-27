import AppKit
import DeskCore
import WebKit

/// The floating companion sheep: a small always-on-top panel that never takes focus and shows over full-screen apps.
/// The main page decides what it says; this window only draws that, and only while HerdrDesk is in the background.
/// Its page has no message handler, so it can neither read data nor act. Clicking only brings HerdrDesk forward.
final class CompanionPanel: NSObject, WKNavigationDelegate {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    /// Takes every mouse event over the page: drag to move, click to open, right-click for the menu, hover for the bubble.
    private final class Surface: NSView {
        var onClick: (() -> Void)?, onMenu: ((NSEvent) -> Void)?, onHover: ((Bool) -> Void)?, onMoved: (() -> Void)?, onDragStart: (() -> Void)?
        /// The page underneath: scrolling goes to it, so a stat panel cut to the screen can be scrolled.
        weak var scrollTarget: NSView?
        override func scrollWheel(with event: NSEvent) { scrollTarget?.scrollWheel(with: event) }
        private var drag = CompanionDrag()
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        override func mouseEntered(with event: NSEvent) { if drag.acceptsHover { onHover?(true) } }
        override func mouseExited(with event: NSEvent) {
            // a resize re-creates the tracking area; the pointer still over the window is not leaving it
            if let window, window.frame.contains(NSEvent.mouseLocation) { return }
            if drag.acceptsHover { onHover?(false) }
        }
        override func mouseDown(with event: NSEvent) { drag.press(at: NSEvent.mouseLocation, origin: window?.frame.origin ?? .zero) }
        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let now = NSEvent.mouseLocation
            var step = drag.move(to: now)
            if step.began {
                // close the bubble once; the window has not moved yet, so its new origin is where it stood at the press
                // (at its new size) and the pointer's whole movement since then still applies
                onDragStart?()
                drag.rebase(origin: window.frame.origin)
                step = drag.move(to: now)
            }
            if let origin = step.origin { window.setFrameOrigin(origin) }
        }
        override func mouseUp(with event: NSEvent) {
            switch drag.release() {
            case .moved:
                onMoved?()
                // the pointer may rest on the sheep again: show its bubble then, not during the drag
                if let window { onHover?(window.frame.contains(NSEvent.mouseLocation)) }
            case .click: onClick?()
            case .none: break
            }
        }
        override func rightMouseDown(with event: NSEvent) { onMenu?(event) }
    }

    var onOpen: (() -> Void)?
    var onTurnOff: (() -> Void)?
    private let panel: Panel
    private let web: WKWebView
    private let surface = Surface()
    private let page: URL
    private let defaults = UserDefaults.standard
    private var pageReady = false
    private var state: [String: Any]?
    private var menuLabels = (snooze: "Hide for 1 hour", off: "Turn off")
    private var enabled = true, attentionOnly = false
    private var idleSince: Date?
    private var snoozedUntil: Date?
    private var hovering = false
    private var bubbleRight = false
    private var bubbleDown = false
    /// The corner the current window frame actually keeps the sheep at (changes only together with the frame), so the
    /// sheep's place is read right even while a direction change waits on the page.
    private var frameRight = false, frameDown = false
    /// Bumped on every hover layout or drag; a step that comes back from the page after that is dropped.
    private var layoutToken = 0
    private var recheck: Timer?
    private var observers: [NSObjectProtocol] = []

    init(webFolder: URL) {
        page = webFolder.appendingPathComponent("companion.html")
        let side = CompanionLayout.side
        panel = Panel(contentRect: NSRect(x: 0, y: 0, width: side, height: side), styleMask: [.borderless, .nonactivatingPanel],
                      backing: .buffered, defer: true)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: side, height: side), configuration: configuration)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = self
        let content = NSView(frame: web.frame)
        web.autoresizingMask = [.width, .height]
        surface.frame = content.bounds
        surface.autoresizingMask = [.width, .height]
        content.addSubview(web)
        content.addSubview(surface)
        panel.contentView = content
        surface.onClick = { [weak self] in self?.onOpen?() }
        surface.onHover = { [weak self] in self?.setHover($0) }
        surface.onMoved = { [weak self] in self?.savePlace() }
        surface.onDragStart = { [weak self] in self?.collapseNow() }
        surface.scrollTarget = web
        surface.onMenu = { [weak self] in self?.showMenu($0) }
        let saved = defaults.string(forKey: "companionOrigin").map(NSPointFromString)
        panel.setFrameOrigin(CompanionLayout.origin(saved: saved, screens: Self.screens()))
        web.loadFileURL(page, allowingReadAccessTo: webFolder)
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification, NSApplication.didChangeScreenParametersNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                if note.name == NSApplication.didChangeScreenParametersNotification { self?.keepOnScreen() }
                self?.refresh()
            })
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    /// A state from the main page: {mood, count, working, flash, lines, enabled, attentionOnly, menu}.
    func update(_ body: [String: Any]) {
        guard let next = CompanionLayout.pageState(body) else { return }
        let mood = next["mood"] as? String, before = state?["mood"] as? String
        let freshFlash = (next["flashAt"] as? Double).map { $0 != state?["flashAt"] as? Double } ?? false
        // an idle sheep shows for the grace period after work ends, or after a fresh finish or assignment
        if mood == "idle" { if (before != nil && before != "idle") || freshFlash { idleSince = Date() } } else { idleSince = nil }
        enabled = body["enabled"] as? Bool ?? true
        attentionOnly = body["attentionOnly"] as? Bool ?? false
        if let menu = body["menu"] as? [String: Any] {
            menuLabels = ((menu["snooze"] as? String).map { String($0.prefix(60)) } ?? menuLabels.snooze,
                          (menu["off"] as? String).map { String($0.prefix(60)) } ?? menuLabels.off)
        }
        state = next
        draw()
        refresh()
        if hovering { layoutHover() }   // the panel's rows may have changed: fit the window to them (no-op when unchanged)
    }

    private func refresh() {
        recheck?.invalidate()
        recheck = nil
        let now = Date()
        if let until = snoozedUntil, until <= now { snoozedUntil = nil }
        let mood = state?["mood"] as? String ?? "idle"
        let show = pageReady && CompanionLayout.visible(mood: mood, enabled: enabled, attentionOnly: attentionOnly, appActive: NSApp.isActive,
                                                        snoozed: snoozedUntil != nil, idleFor: idleSince.map { now.timeIntervalSince($0) })
        if show {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible {
            setHover(false)
            panel.orderOut(nil)
        }
        // wake again when the idle grace or the snooze runs out
        let wake = [snoozedUntil, idleSince.map { $0.addingTimeInterval(CompanionLayout.idleGrace + 0.1) }].compactMap { $0 }.filter { $0 > now }.min()
        if let wake {
            recheck = Timer.scheduledTimer(withTimeInterval: wake.timeIntervalSince(now), repeats: false) { [weak self] _ in self?.refresh() }
        }
    }

    private func draw() {
        guard pageReady, let state else { return }
        web.callAsyncJavaScript("window.companion.show(state)", arguments: ["state": state], in: nil, in: .page, completionHandler: nil)
    }

    private func setHover(_ on: Bool) {
        guard on != hovering else { return }
        hovering = on
        layoutHover()
    }

    /// A drag reads the window's origin right away: shrink to the sheep now and let the page catch up.
    private func collapseNow() {
        guard hovering else { return }
        let sheep = NSRect(origin: sheepOrigin(), size: NSSize(width: CompanionLayout.side, height: CompanionLayout.side))
        hovering = false
        layoutToken += 1
        panel.setFrame(sheep, display: true)
        frameRight = false; frameDown = false
        bubbleRight = false; bubbleDown = false
        reveal(false) { [weak self] in self?.direction() }
    }

    /// Opens or closes the panel without moving the sheep: to open, the page first pins the sheep to the corner it keeps,
    /// then the window grows, then the panel shows; to close, the panel hides, the window shrinks, then the pin resets.
    /// The sheep is pinned to a window corner in the page, so no step of this ever moves it on screen.
    private func layoutHover() {
        let sheep = NSRect(origin: sheepOrigin(), size: NSSize(width: CompanionLayout.side, height: CompanionLayout.side))
        let stats = state?["stats"] as? [[String: Any]] ?? []
        let lines = (state?["lines"] as? [String]) ?? []
        layoutToken += 1
        let token = layoutToken
        guard hovering, !stats.isEmpty || !lines.isEmpty else {
            reveal(false) { [weak self] in
                guard let self, self.layoutToken == token else { return }
                if self.panel.frame != sheep { self.panel.setFrame(sheep, display: true) }
                self.frameRight = false; self.frameDown = false
                self.bubbleRight = false; self.bubbleDown = false
                self.direction()
            }
            return
        }
        let rows = stats.map { (($0["rows"] as? [Any])?.count ?? 0) + ((($0["more"] as? String) ?? "").isEmpty ? 0 : 1) }
        let mood = state?["mood"] as? String ?? ""
        let notices = ["offline", "limit"].contains(mood) ? lines.count : 0
        let open = CompanionLayout.expanded(sheep: sheep, screens: Self.screens(),
                                            height: stats.isEmpty ? nil : CompanionLayout.panelHeight(sections: rows, lines: notices))
        let turned = open.bubbleRight != bubbleRight || open.down != bubbleDown
        bubbleRight = open.bubbleRight; bubbleDown = open.down
        let grow = { [weak self] in
            guard let self, self.layoutToken == token, self.hovering else { return }
            if self.panel.frame != open.frame { self.panel.setFrame(open.frame, display: true) }
            self.frameRight = open.bubbleRight; self.frameDown = open.down
            self.reveal(true)
        }
        if turned { direction(then: grow) } else { grow() }
    }

    private func direction(then next: (() -> Void)? = nil) {
        guard pageReady else { next?(); return }
        web.callAsyncJavaScript("window.companion.direction(right, down)", arguments: ["right": bubbleRight, "down": bubbleDown],
                                in: nil, in: .page) { _ in next?() }
    }

    private func reveal(_ on: Bool, then next: (() -> Void)? = nil) {
        guard pageReady else { next?(); return }
        web.callAsyncJavaScript("window.companion.reveal(on)", arguments: ["on": on], in: nil, in: .page) { _ in next?() }
    }

    /// The sheep's own place: the right end of the window (left while the panel opens right), at its bottom (top while
    /// the panel opens down).
    private func sheepOrigin() -> NSPoint {
        NSPoint(x: frameRight ? panel.frame.minX : panel.frame.maxX - CompanionLayout.side,
                y: frameDown ? panel.frame.maxY - CompanionLayout.side : panel.frame.minY)
    }

    private func savePlace() {
        keepOnScreen()
        defaults.set(NSStringFromPoint(sheepOrigin()), forKey: "companionOrigin")
    }

    private func keepOnScreen() {
        let origin = CompanionLayout.origin(saved: sheepOrigin(), screens: Self.screens())
        panel.setFrameOrigin(NSPoint(x: frameRight ? origin.x : origin.x + CompanionLayout.side - panel.frame.width,
                                     y: frameDown ? origin.y + CompanionLayout.side - panel.frame.height : origin.y))
    }

    private func showMenu(_ event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: menuLabels.snooze, action: #selector(snooze), keyEquivalent: "").target = self
        menu.addItem(withTitle: menuLabels.off, action: #selector(turnOff), keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(menu, with: event, for: surface)
    }

    @objc private func snooze() {
        snoozedUntil = Date().addingTimeInterval(3600)
        refresh()
    }

    @objc private func turnOff() {
        enabled = false
        refresh()
        onTurnOff?()
    }

    private static func screens() -> [CGRect] {
        let main = NSScreen.main
        return ([main].compactMap { $0 } + NSScreen.screens.filter { $0 != main }).map(\.visibleFrame)
    }

    func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = action.request.url.map { $0.isFileURL && $0.standardizedFileURL.path == page.standardizedFileURL.path } ?? false
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        draw()
        refresh()
    }

    func webViewWebContentProcessDidTerminate(_ view: WKWebView) {
        pageReady = false
        refresh()
        view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }
}
