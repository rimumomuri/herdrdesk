import XCTest
@testable import DeskCore

final class AttachmentKeyTests: XCTestCase {
    func term(_ address: String, role: String?, pid: Int) -> Term {
        var json: [String: Any] = ["address": address, "state": "live", "created_ms": 1, "pid": pid, "status": ["app": "codex", "state": "idle"]]
        if let role { json["labels"] = ["recovery.role": role] }
        return Term(json: json)!
    }

    func testAUniqueRoleKeepsItsRoleKey() {
        let a = term("t1", role: "shop-builder", pid: 1)
        XCTAssertEqual(AttachmentKey.make(for: a, among: [a]), "shop-builder")
    }

    func testTwoTerminalsWithTheSameRoleGetSeparateKeys() {
        let a = term("t1", role: "shop-builder", pid: 1), b = term("t2", role: "shop-builder", pid: 2)
        let ka = AttachmentKey.make(for: a, among: [a, b]), kb = AttachmentKey.make(for: b, among: [a, b])
        XCTAssertNotNil(ka); XCTAssertNotNil(kb)
        XCTAssertNotEqual(ka, kb)
        XCTAssertNotEqual(ka, "shop-builder")
        XCTAssertTrue(ka!.hasPrefix("session-"))
    }

    func testAnUnsafeRoleIsRefused() {
        let a = term("t1", role: "..", pid: 1)
        XCTAssertNil(AttachmentKey.make(for: a, among: [a]))
    }
}
