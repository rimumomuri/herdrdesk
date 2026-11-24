import Foundation

/// Rules for the floating companion sheep: when it shows, where it sits, and what reaches its page.
public enum CompanionLayout {
    public static let side: CGFloat = 84          // the collapsed window: one sheep
    public static let wide: CGFloat = 300         // while hovered: sheep plus its bubble, growing to the left
    public static let inset: CGFloat = 24
    public static let idleGrace: TimeInterval = 10
    public static let moods: Set<String> = ["attention", "offline", "working", "idle"]

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
        return ["mood": mood, "count": number("count"), "working": number("working"), "flash": flash ?? NSNull(), "lines": Array(lines)]
    }
}
