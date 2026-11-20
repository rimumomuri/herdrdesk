import Foundation
import XCTest
@testable import DeskCore

final class ChatShortcutTests: XCTestCase {
    func testLocalFilesAreRevealedAndFoldersAreOpened() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("my script.sh")
        try Data("#!/bin/sh\n".utf8).write(to: file)
        func shortcut(_ path: String) -> URL {
            URL(string: "herdrdesk-path:" + path.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)!
        }
        guard case .folder(let folder) = ChatShortcut.destination(shortcut(directory.path)) else {
            return XCTFail("Expected to open a folder")
        }
        XCTAssertEqual(folder.path, directory.path)
        XCTAssertEqual(ChatShortcut.destination(shortcut("~/my script.sh:21:2"), home: directory.path), .reveal(file.standardizedFileURL))
        XCTAssertNil(ChatShortcut.destination(shortcut(directory.appendingPathComponent("missing").path)))
        XCTAssertNil(ChatShortcut.destination(shortcut("//some-other-computer/path")))
    }

    func testOnlyHTTPAndHTTPSCanOpenInTheBrowser() {
        let site = URL(string: "https://github.com/example")!
        XCTAssertEqual(ChatShortcut.destination(site), .website(site))
        for value in ["javascript:alert(1)", "file:///Applications/Some.app", "https://user:password@example.com"] {
            XCTAssertNil(ChatShortcut.destination(URL(string: value)!))
        }
    }
}
