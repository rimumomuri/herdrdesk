import Foundation
import XCTest
@testable import DeskCore

final class LegacyAttachmentsTests: XCTestCase {
    func testExistingIndexUsesOnlyFilesInTheOriginalRoleDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let draft = tmp.appendingPathComponent("drafts/reviewer")
        try FileManager.default.createDirectory(at: draft, withIntermediateDirectories: true)
        let image = draft.appendingPathComponent("herdr-img-1-demo.png")
        let outside = tmp.appendingPathComponent("outside.png")
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aFKsAAAAASUVORK5CYII="))
        try png.write(to: image)
        try png.write(to: outside)
        let existing = Attachment(id: "atest001", name: "Existing.png", file: image.path, bytes: png.count, width: 1, height: 1)
        let invalid = Attachment(id: "invalid", name: "Outside.png", file: outside.path, bytes: png.count, width: 1, height: 1)
        try JSONEncoder().encode([existing, invalid]).write(to: draft.appendingPathComponent("index.json"))
        let store = AttachmentStore(root: tmp)
        XCTAssertEqual(store.rolesWithDrafts(), ["reviewer"])
        XCTAssertEqual(store.list(role: "reviewer"), [existing])
        XCTAssertEqual(store.resolve(role: "reviewer", ids: [existing.id]), [existing])
        XCTAssertNil(store.resolve(role: "not-reviewer", ids: [existing.id]))
        XCTAssertNil(store.resolve(role: "reviewer", ids: [invalid.id]))
    }
}
