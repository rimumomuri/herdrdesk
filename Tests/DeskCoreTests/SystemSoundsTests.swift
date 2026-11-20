import Foundation
import XCTest
@testable import DeskCore

final class SystemSoundsTests: XCTestCase {
    func testListsOnlySoundFilesSortedWithoutExtension() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["Ping.aiff", "Glass.aiff", "notes.txt", ".hidden.aiff"] {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
        }
        XCTAssertEqual(SystemSounds.names(in: dir), ["Glass", "Ping"])
    }

    func testOnlyListedNamesArePlayable() {
        let names = ["Glass", "Ping"]
        XCTAssertTrue(SystemSounds.allowed("Ping", in: names))
        XCTAssertFalse(SystemSounds.allowed("../../etc/x", in: names))
        XCTAssertFalse(SystemSounds.allowed("", in: names))
    }
}
