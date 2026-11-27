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

        private var drag = CompanionDrag()
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        override func mouseEntered(with event: NSEvent) { if drag.acceptsHover { onHover?(true) } }
        override func mouseExited(with event: NSEvent) { if drag.acceptsHover { onHover?(false) } }
        override func mouseDown(with event: NSEvent) { drag.press(at: NSEvent.mouseLocation, origin: window?.frame.origin ?? .zero) }
        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let now = NSEvent.mouseLocation
            let step = drag.move(to: now)
            if step.began { onDragStart?() }   // the stat panel closes while the sheep is carried
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

    /// Over the stat panel: notes when the pointer is on it, and lets every event through to the page (so it scrolls).
    private final class HoverView: NSView {
        var onHover: ((Bool) -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }
        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }
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
    /// The stat panel lives in its own window beside the sheep, so the sheep's window never changes size: resizing a
    /// window holding a web page shows a frame or two of the old drawing, which flashed on every hover.
    private let bubble: Panel
    private let bubbleWeb: WKWebView
    private let bubbleHover = HoverView()
    private var bubbleReady = false
    private var overSheep = false, overBubble = false, carrying = false
    private var bubbleOpen = false
    private var closeTimer: Timer?
    private var bubbleToken = 0
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
        let bubbleSize = NSRect(x: 0, y: 0, width: CompanionLayout.wide - side, height: side)
        bubble = Panel(contentRect: bubbleSize, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        let bubbleConfiguration = WKWebViewConfiguration()
        bubbleConfiguration.websiteDataStore = .nonPersistent()
        bubbleWeb = WKWebView(frame: bubbleSize, configuration: bubbleConfiguration)
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
        surface.onHover = { [weak self] in self?.overSheep = $0; self?.carrying = false; self?.layoutBubble() }
        surface.onMoved = { [weak self] in self?.savePlace() }
        surface.onDragStart = { [weak self] in self?.carrying = true; self?.layoutBubble() }
        surface.onMenu = { [weak self] in self?.showMenu($0) }
        for window in [bubble] {
            window.isFloatingPanel = true
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
        }
        bubbleWeb.setValue(false, forKey: "drawsBackground")
        bubbleWeb.navigationDelegate = self
        let bubbleContent = NSView(frame: bubbleSize)
        bubbleWeb.autoresizingMask = [.width, .height]
        bubbleHover.frame = bubbleContent.bounds
        bubbleHover.autoresizingMask = [.width, .height]
        bubbleContent.addSubview(bubbleWeb)
        bubbleContent.addSubview(bubbleHover)
        bubble.contentView = bubbleContent
        bubbleHover.onHover = { [weak self] in self?.overBubble = $0; self?.layoutBubble() }
        // the plain page; once loaded it is switched to panel-only (a URL fragment here made WebKit throw, which cut
        // the app's launch short before it connected to Herdr)
        bubbleWeb.loadFileURL(page, allowingReadAccessTo: webFolder)
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
        if bubbleOpen { layoutBubble() }   // the rows may have changed: fit the panel window to them
    }

    /// The main window was closed or opened again: the companion shows while it is closed.
    func deskVisibilityChanged() { refresh() }

    private func refresh() {
        recheck?.invalidate()
        recheck = nil
        let now = Date()
        if let until = snoozedUntil, until <= now { snoozedUntil = nil }
        let mood = state?["mood"] as? String ?? "idle"
        let windowOpen = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        let front = CompanionLayout.deskInFront(appActive: NSApp.isActive, windowVisible: windowOpen)
        let show = pageReady && CompanionLayout.visible(mood: mood, enabled: enabled, attentionOnly: attentionOnly, appActive: front,
                                                        snoozed: snoozedUntil != nil, idleFor: idleSince.map { now.timeIntervalSince($0) })
        if show {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible {
            overSheep = false; overBubble = false
            layoutBubble()
            panel.orderOut(nil)
        }
        // wake again when the idle grace or the snooze runs out
        let wake = [snoozedUntil, idleSince.map { $0.addingTimeInterval(CompanionLayout.idleGrace + 0.1) }].compactMap { $0 }.filter { $0 > now }.min()
        if let wake {
            recheck = Timer.scheduledTimer(withTimeInterval: wake.timeIntervalSince(now), repeats: false) { [weak self] _ in self?.refresh() }
        }
    }

    private func draw() {
        guard let state else { return }
        if pageReady { web.callAsyncJavaScript("window.companion.show(state)", arguments: ["state": state], in: nil, in: .page, completionHandler: nil) }
        if bubbleReady { bubbleWeb.callAsyncJavaScript("window.companion.show(state)", arguments: ["state": state], in: nil, in: .page, completionHandler: nil) }
    }

    /// Opens the panel while the pointer is on the sheep or on the panel (and nothing is being carried); closes it a
    /// moment after the pointer leaves both, so moving from the sheep onto the panel keeps it open.
    private func layoutBubble() {
        let stats = state?["stats"] as? [[String: Any]] ?? []
        let lines = (state?["lines"] as? [String]) ?? []
        let want = (overSheep || overBubble) && !carrying && panel.isVisible && (!stats.isEmpty || !lines.isEmpty)
        if !want {
            guard bubbleOpen else { bubbleToken += 1; return }   // an open still waiting on the page is dropped
            if carrying || !panel.isVisible { closeBubble(); return }
            closeTimer?.invalidate()
            closeTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in self?.closeBubble() }
            return
        }
        closeTimer?.invalidate(); closeTimer = nil
        let rows = stats.map { (($0["rows"] as? [Any])?.count ?? 0) + ((($0["more"] as? String) ?? "").isEmpty ? 0 : 1) }
        let mood = state?["mood"] as? String ?? ""
        let notices = ["offline", "limit"].contains(mood) ? lines.count : 0
        let place = CompanionLayout.bubbleFrame(sheep: panel.frame, screens: Self.screens(),
                                                height: stats.isEmpty ? nil : CompanionLayout.panelHeight(sections: rows, lines: notices))
        bubbleToken += 1
        let token = bubbleToken
        let show = { [weak self] in
            guard let self, self.bubbleToken == token, (self.overSheep || self.overBubble), !self.carrying, self.panel.isVisible else { return }
            if self.bubble.frame != place.frame { self.bubble.setFrame(place.frame, display: true) }
            if !self.bubble.isVisible { self.bubble.orderFrontRegardless() }
            self.bubbleOpen = true
        }
        guard bubbleReady, let state else { show(); return }
        // the panel window is placed and drawn before it shows (only then is it brought on screen)
        if !bubble.isVisible, bubble.frame != place.frame { bubble.setFrame(place.frame, display: false) }
        bubbleWeb.callAsyncJavaScript("window.companion.show(state); window.companion.direction(right, down)",
                                      arguments: ["state": state, "right": place.right, "down": place.down], in: nil, in: .page) { _ in show() }
    }

    private func closeBubble() {
        closeTimer?.invalidate(); closeTimer = nil
        bubbleToken += 1
        bubbleOpen = false
        bubble.orderOut(nil)
    }

    /// The sheep's place: its window never changes size, so it is the window's origin.
    private func sheepOrigin() -> NSPoint { panel.frame.origin }

    private func savePlace() {
        keepOnScreen()
        defaults.set(NSStringFromPoint(sheepOrigin()), forKey: "companionOrigin")
    }

    private func keepOnScreen() {
        panel.setFrameOrigin(CompanionLayout.origin(saved: sheepOrigin(), screens: Self.screens()))
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
        if view === bubbleWeb {
            view.callAsyncJavaScript("window.companion.panelOnly()", arguments: [:], in: nil, in: .page) { [weak self] _ in
                self?.bubbleReady = true
                self?.draw()
            }
            return
        }
        pageReady = true
        draw()
        refresh()
    }

    func webViewWebContentProcessDidTerminate(_ view: WKWebView) {
        if view === bubbleWeb {
            bubbleReady = false
            closeBubble()
            view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
            return
        }
        pageReady = false
        refresh()
        view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }
}
