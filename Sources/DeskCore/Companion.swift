import Foundation

/// Rules for the floating companion sheep: when it shows, where it sits, and what reaches its page.
public enum CompanionLayout {
    public static let side: CGFloat = 84          // the collapsed window: one sheep
    public static let wide: CGFloat = 300         // while hovered: sheep plus its bubble, growing to the left
    public static let inset: CGFloat = 24
    public static let idleGrace: TimeInterval = 10
    public static let moods: Set<String> = ["attention", "offline", "limit", "working", "idle"]

    /// Shown only while HerdrDesk is in the background; an idle sheep stays briefly after work ends, then leaves.
    public static func visible(mood: String, enabled: Bool, attentionOnly: Bool, appActive: Bool, snoozed: Bool, idleFor: TimeInterval?) -> Bool {
        guard enabled, !appActive, !snoozed, moods.contains(mood) else { return false }
        if attentionOnly { return mood == "attention" }
        if mood == "idle" { return (idleFor ?? .infinity) < idleGrace }
        return true
    }

    /// The saved place when the whole sheep fits on one screen, else the main screen's top-right corner.
    /// `screens` are visible frames, the main screen first.
    public static func origin(saved: CGPoint?, screens: [CGRect]) -> CGPoint {
        if let saved, screens.contains(where: { $0.contains(CGRect(origin: saved, size: CGSize(width: side, height: side))) }) { return saved }
        let main = screens.first ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        return CGPoint(x: main.maxX - inset - side, y: main.maxY - inset - side)
    }

    /// The hovered window: sheep plus bubble, growing left, or right when the left would leave the sheep's screen.
    public static func expanded(sheep: CGRect, screens: [CGRect]) -> (frame: CGRect, bubbleRight: Bool) {
        let screen = screens.first { $0.intersects(sheep) } ?? screens.first ?? sheep
        let left = CGRect(x: sheep.maxX - wide, y: sheep.minY, width: wide, height: sheep.height)
        if left.minX >= screen.minX { return (left, false) }
        return (CGRect(x: sheep.minX, y: sheep.minY, width: wide, height: sheep.height), true)
    }

    /// What the page may draw: a known mood, small numbers, a known flash and up to four short lines. Nil for anything else.
    public static func pageState(_ body: [String: Any]) -> [String: Any]? {
        guard let mood = body["mood"] as? String, moods.contains(mood) else { return nil }
        let number = { (key: String) in min(max(body[key] as? Int ?? 0, 0), 999) }
        let flash = (body["flash"] as? String).flatMap { ["done", "handoff"].contains($0) ? $0 : nil }
        let lines = (body["lines"] as? [Any] ?? []).compactMap { $0 as? String }.prefix(4).map { String($0.prefix(120)) }
        let flashAt = flash == nil ? nil : body["flashAt"] as? Double
        return ["mood": mood, "count": number("count"), "working": number("working"), "limited": number("limited"), "flash": flash ?? NSNull(),
                "flashAt": flashAt ?? NSNull(), "lines": Array(lines), "face": face(body["face"]) ?? NSNull()]
    }

    /// The agent's look: a known provider and short lowercase style names (the page maps unknown names to defaults).
    static func face(_ value: Any?) -> [String: Any]? {
        guard let body = value as? [String: Any], let provider = body["provider"] as? String, ["codex", "claude", "neutral"].contains(provider) else { return nil }
        var face: [String: Any] = ["provider": provider, "sleeping": body["sleeping"] as? Bool ?? false, "working": body["working"] as? Bool ?? false,
                                   "kind": (body["kind"] as? String) == "agent" ? "agent" : "lead"]
        // Engines of the agents a lead is holding (what it handed work to): known names only, a few at most.
        face["mouth"] = (body["mouth"] as? [Any] ?? []).prefix(9).compactMap { $0 as? String }.filter { ["codex", "claude"].contains($0) }
        for key in ["style", "coat", "accessory"] {
            let name = body[key] as? String ?? ""
            guard name.count <= 24, name.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }) else { return nil }
            face[key] = name
        }
        return face
    }
}

/// Mouse handling of the floating sheep: a press that moves more than a few points is a drag, otherwise a click.
/// While the button is down, hover changes are ignored: the window trails the pointer, so the pointer slips in and out
/// of it, and opening and closing the bubble on each slip made the window flicker.
public struct CompanionDrag {
    public enum Outcome: Equatable { case click, moved, none }
    private var start: CGPoint?, startOrigin: CGPoint?, dragging = false
    public init() {}

    public var acceptsHover: Bool { start == nil }

    public mutating func press(at point: CGPoint, origin: CGPoint) {
        start = point; startOrigin = origin; dragging = false
    }

    /// `began` is true once, when the press turns into a drag; `origin` is where the window goes (nil: stay).
    public mutating func move(to point: CGPoint) -> (began: Bool, origin: CGPoint?) {
        guard let start, let startOrigin else { return (false, nil) }
        let dx = point.x - start.x, dy = point.y - start.y
        var began = false
        if !dragging, hypot(dx, dy) > 3 { dragging = true; began = true }
        return (began, dragging ? CGPoint(x: startOrigin.x + dx, y: startOrigin.y + dy) : nil)
    }

    /// The window changed size when the drag began (the window's origin at the press, seen at its new size):
    /// the pointer's whole movement since the press still applies.
    public mutating func rebase(origin: CGPoint) {
        guard start != nil else { return }
        startOrigin = origin
    }

    public mutating func release() -> Outcome {
        defer { start = nil; startOrigin = nil; dragging = false }
        guard start != nil else { return .none }
        return dragging ? .moved : .click
    }
}
