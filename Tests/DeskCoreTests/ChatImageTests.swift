import Foundation
import XCTest
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import Darwin
@testable import DeskCore

final class ChatImageTests: XCTestCase {
    private func makeRoot() throws -> URL {
        // Tests run from the lead's isolated candidate/source checkout.
        // Keep this synthetic home inside that workspace, away from temporary aliases.
        let physical = URL(fileURLWithPath:FileManager.default.currentDirectoryPath,isDirectory:true)
            .appendingPathComponent("qa-image-test-" + UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:physical,withIntermediateDirectories:true)
        var directory = stat()
        XCTAssertEqual(lstat(physical.path,&directory),0)
        XCTAssertTrue(directory.st_mode & S_IFMT == S_IFDIR)
        XCTAssertFalse(directory.st_mode & S_IFMT == S_IFLNK)
        return physical
    }
    private func emitDiagnostic(_ values: [String:Any]) {
        guard ProcessInfo.processInfo.environment["HERDRDESK_IMAGE_DIAGNOSTIC"] == "1",
              let data=try? JSONSerialization.data(withJSONObject:values,options:.sortedKeys),
              let line=String(data:data,encoding:.utf8) else { return }
        print("IMAGE_PREVIEW_DIAG " + line)
    }
    private func diagnosePreview(_ url: URL, home: URL? = nil) {
        guard ProcessInfo.processInfo.environment["HERDRDESK_IMAGE_DIAGNOSTIC"] == "1" else { return }
        errno=0
        let bytes=ChatImagePolicy.readRegularFile(url.path,maxBytes:ChatImagePolicy.maxBytes)
        let readErrno=errno
        let bounded=bytes.flatMap { ChatImagePolicy.boundedThumbnail($0) }
        var flags:[String:Any] = ["fileRead":bytes != nil,"readErrno":Int(readErrno),"boundedThumbnail":bounded != nil]
        if let home { flags["pathThumbnail"]=ChatImagePolicy.thumbnail(url.path,home:home.path) != nil }
        emitDiagnostic(flags)
    }
    private func makePNG(width: Int = 16, height: Int = 8) throws -> Data {
        let context = try XCTUnwrap(CGContext(data:nil,width:width,height:height,bitsPerComponent:8,
            bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red:0.25,green:0.5,blue:0.75,alpha:1))
        context.fill(CGRect(x:0,y:0,width:width,height:height))
        let image = try XCTUnwrap(context.makeImage())
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes,UTType.png.identifier as CFString,1,nil))
        CGImageDestinationAddImage(destination,image,nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
    func testGeneratedPNGFixtureDecodesActualPixels() throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(try makePNG() as CFData,nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        XCTAssertEqual(image.width,16)
        XCTAssertEqual(image.height,8)
        XCTAssertNotNil(image.dataProvider?.data)
    }
    func testExplicitReferencesExcludeCodeRemoteAndOrdinaryPaths() {
        XCTAssertEqual(ChatImagePolicy.references("![한 장](</Users/demo/Pictures/a b.png>)\n[결과](/Users/demo/Documents/out.jpg)\n/Users/demo/Pictures/plain.png\n```\n![code](/Users/demo/Pictures/code.png)\n```\n`![inline](/Users/demo/Pictures/inline.png)`\n![remote](https://example.com/a.png)\nsecret /Users/demo/Pictures/ordinary.png"), ["/Users/demo/Pictures/a b.png","/Users/demo/Documents/out.jpg","/Users/demo/Pictures/plain.png"])
    }
    func testUnsupportedExplicitImageRetainsFallbackReferenceWithoutReadPermission() {
        XCTAssertEqual(ChatImagePolicy.references("![vector](/Users/demo/Pictures/a.svg)"), ["/Users/demo/Pictures/a.svg"])
        XCTAssertNil(ChatImagePolicy.thumbnail("/Users/demo/Pictures/a.svg",home:"/Users/demo"))
    }
    func testFenceLengthClosingTextAndIndentedCodeNeverBecomeReferences() {
        XCTAssertEqual(ChatImagePolicy.references("````markdown\n```\n![inside](/Users/demo/Pictures/inside.png)\n```` extra\n![still](/Users/demo/Pictures/still.png)\n````\n    ```\n    ![indented](/Users/demo/Pictures/indented.png)\n    ```\n/Users/demo/Pictures/out.png"), ["/Users/demo/Pictures/out.png"])
    }
    func testBoundRecordRejectsSessionBodyRoleAndStaleSubstitution() {
        let row = ChatImageRecord(id:"r20261120120000abcdef",role:"lead",session:"1:2",body:"![x](/Users/demo/Pictures/a.png)")
        XCTAssertTrue(row.matches(id:row.id,role:"lead",session:"1:2",body:row.body))
        XCTAssertFalse(row.matches(id:row.id,role:"other",session:"1:2",body:row.body))
        XCTAssertFalse(row.matches(id:row.id,role:"lead",session:"1:3",body:row.body))
        XCTAssertFalse(row.matches(id:row.id,role:"lead",session:"1:2",body:row.body+"stale"))
    }
    func testSentThumbnailSurvivesClearAndRestartWithExactLedgerBinding() throws {
        let png = try makePNG()
        let root=try makeRoot()
        defer { try? FileManager.default.removeItem(at:root) }
        let draft=AttachmentStore(root:root.appendingPathComponent("attachments"))
        let (attachment,_)=try draft.add(role:"lead",name:"test.png",data:png)
        diagnosePreview(URL(fileURLWithPath:attachment.file))
        let preview=[["name":attachment.name,"thumbnail":try XCTUnwrap(draft.thumbnail(for:attachment)).base64EncodedString()]]
        let record=ChatImageRecord(id:"mtest001",role:"lead",session:"1:2",body:"photo")
        let url=root.appendingPathComponent("previews")
        try SentChatImages(root:url).save(record,previews:preview)
        draft.clear(role:"lead",ids:[attachment.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath:attachment.file))
        let restarted=SentChatImages(root:url)
        XCTAssertEqual(restarted.load(record),preview)
        XCTAssertNil(restarted.load(ChatImageRecord(id:record.id,role:"other",session:record.session,body:record.body)))
        XCTAssertNil(restarted.load(ChatImageRecord(id:record.id,role:record.role,session:"new",body:record.body)))
        XCTAssertNil(restarted.load(ChatImageRecord(id:record.id,role:record.role,session:record.session,body:"different")))
    }
    func testDecodeAndPathBoundaries() throws {
        let png = try makePNG()
        let home=try makeRoot()
        defer { try? FileManager.default.removeItem(at:home) }
        try FileManager.default.createDirectory(at:home.appendingPathComponent("Pictures"),withIntermediateDirectories:true)
        let image=home.appendingPathComponent("Pictures/ok.png");try png.write(to:image)
        diagnosePreview(image,home:home)
        XCTAssertNotNil(ChatImagePolicy.thumbnail(image.path,home:home.path))
        let alias=home.appendingPathComponent("Pictures/link.png");try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:image)
        XCTAssertNil(ChatImagePolicy.thumbnail(alias.path,home:home.path))
        for name in ["token.png","secret.png","credentials.png",".hidden.png","script.png","broken.png","large.png"] {
            let url=home.appendingPathComponent("Pictures/"+name)
            let data = name == "script.png" ? Data("#!/bin/sh\n".utf8) : name == "broken.png" ? Data("broken".utf8) : name == "large.png" ? Data(repeating:0,count:ChatImagePolicy.maxBytes+1) : png
            try data.write(to:url);XCTAssertNil(ChatImagePolicy.thumbnail(url.path,home:home.path),name)
        }
        try png.write(to:home.appendingPathComponent("outside.png"))
        XCTAssertNil(ChatImagePolicy.thumbnail(home.appendingPathComponent("outside.png").path,home:home.path))
        XCTAssertNil(ChatImagePolicy.thumbnail(image.path,home:home.appendingPathComponent("other").path))
        XCTAssertNil(ChatImagePolicy.thumbnail("https://example.com/a.png",home:home.path))
        XCTAssertNil(ChatImagePolicy.boundedThumbnail(Data(repeating:0,count:ChatImagePolicy.maxBytes+1)))
        // A valid ImageIO-encoded PNG beyond the axis limit must be refused.
        XCTAssertNil(ChatImagePolicy.boundedThumbnail(try makePNG(width:16385,height:1)))
    }
}
