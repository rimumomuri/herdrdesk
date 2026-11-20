import XCTest
@testable import DeskCore

final class TerminalObserveTests: XCTestCase {
    func testFrameDecodesAcrossReadsAndKeepsRawBytes() throws {
        let bytes = Data([0x1B, 0x5B, 0x48, 0xED, 0x95, 0x9C])
        let first = ObserveFrame(channel: 2, kind: 0, payload: bytes)
        let next = ObserveFrame(channel: 2, kind: 3, payload: Data([90, 0, 30, 0]))
        var buffer = Data(first.encoded.prefix(8))
        XCTAssertNil(try ObserveFrame.take(from: &buffer))
        buffer.append(first.encoded.dropFirst(8))
        buffer.append(next.encoded)
        XCTAssertEqual(try ObserveFrame.take(from: &buffer), first)
        XCTAssertEqual(try ObserveFrame.take(from: &buffer), next)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testOversizedFrameIsRejectedAndCreditIsLittleEndian() throws {
        var bad = Data([1, 0, 0, 0, 0, 1, 0, 0, 1])
        XCTAssertThrowsError(try ObserveFrame.take(from: &bad))
        XCTAssertEqual(ObserveFrame.credit(channel: 1, count: 513).encoded,
                       Data([1, 0, 0, 0, 1, 4, 0, 0, 0, 1, 2, 0, 0]))
    }
}
