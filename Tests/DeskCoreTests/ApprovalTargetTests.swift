import Foundation
import XCTest
@testable import DeskCore

final class ApprovalTargetTests: XCTestCase {
    func testLinkedTerminalAllowsFocusOnlyForCurrentSession() throws {
        let labels = [
            "recovery.role": "requester", "ask.id": "qFixture", "ask.text": "Confirm the test",
            "ask.session": "400:50", "ask.approval_role": "operator", "ask.approval_session": "500:60"
        ]
        let asker = try XCTUnwrap(Term(json: ["address": "t1", "state": "live", "created_ms": 400, "pid": 50,
                                             "labels": labels, "status": ["app": "codex", "state": "blocked"]]))
        func target(pid: Int) throws -> Term {
            try XCTUnwrap(Term(json: ["address": "peer/t1", "state": "live", "created_ms": 500, "pid": pid,
                                     "labels": ["recovery.role": "operator"],
                                     "status": ["app": "codex", "state": "blocked"]]))
        }
        XCTAssertEqual(checkApproval(questionId: "qFixture", asker: asker, target: .success(try target(pid: 60))),
                       .success(try target(pid: 60)))
        XCTAssertEqual(checkApproval(questionId: "qFixture", asker: asker, target: .success(try target(pid: 61))),
                       .failure(.targetSessionChanged))
        XCTAssertEqual(checkApproval(questionId: "qFixture", asker: asker, target: .failure(.ambiguous)),
                       .failure(.target(.ambiguous)))
    }
}
