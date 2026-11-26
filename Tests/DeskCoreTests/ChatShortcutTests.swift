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

    func testWebPagesOpenInTheBrowserAndMarkdownOpensInTheApp() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func make(_ name: String) throws -> URL {
            let file = directory.appendingPathComponent(name)
            try Data("x".utf8).write(to: file)
            return file.standardizedFileURL
        }
        func shortcut(_ url: URL) -> URL {
            URL(string: "herdrdesk-path:" + url.path.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)!
        }
        for name in ["map.html", "Page.HTM"] {
            let file = try make(name)
            XCTAssertEqual(ChatShortcut.destination(shortcut(file)), .browser(file))
        }
        for name in ["plan.md", "NOTES.markdown"] {
            let file = try make(name)
            XCTAssertEqual(ChatShortcut.destination(shortcut(file)), .markdown(file))
        }
        let other = try make("data.csv")
        XCTAssertEqual(ChatShortcut.destination(shortcut(other)), .reveal(other))
        let link = directory.appendingPathComponent("link.html")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: try make("real.html"))
        XCTAssertEqual(ChatShortcut.destination(shortcut(link)), .reveal(link.standardizedFileURL))
    }

    func testMarkdownTextIsReadOnlyWhenSmallAndUTF8() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("plan.md")
        try Data("# 계획\n".utf8).write(to: file)
        XCTAssertEqual(ChatShortcut.markdownText(file), "# 계획\n")
        try Data(repeating: 0x61, count: ChatShortcut.markdownLimit + 1).write(to: file)
        XCTAssertNil(ChatShortcut.markdownText(file))
        try Data([0xFF, 0xFE, 0x00]).write(to: file)
        XCTAssertNil(ChatShortcut.markdownText(file))
    }

    func testOnlyHTTPAndHTTPSCanOpenInTheBrowser() {
        let site = URL(string: "https://github.com/example")!
        XCTAssertEqual(ChatShortcut.destination(site), .website(site))
        for value in ["javascript:alert(1)", "file:///Applications/Some.app", "https://user:password@example.com"] {
            XCTAssertNil(ChatShortcut.destination(URL(string: value)!))
        }
    }
}
