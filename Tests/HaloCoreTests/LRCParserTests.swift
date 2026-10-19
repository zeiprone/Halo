import XCTest
@testable import HaloCore

final class LRCParserTests: XCTestCase {
    func testParsesValidTimestampsAndSortsMultipleTags() {
        let timeline = LRCParser().parse("[00:10.00][00:02.00] Hello\n[00:12.50] World")
        XCTAssertEqual(timeline.lines.map(\.startTime), [2, 10, 12.5])
        XCTAssertEqual(timeline.lines[0].text, "Hello")
        XCTAssertEqual(timeline.kind, .lineSynced)
    }

    func testIgnoresMalformedAndEmptyLyrics() {
        XCTAssertTrue(LRCParser().parse("").lines.isEmpty)
        XCTAssertTrue(LRCParser().parse("[bad] Nope").lines.isEmpty)
    }

    func testPreservesUnicode() {
        let timeline = LRCParser().parse("[00:01.00] Merhaba dünya 你好")
        XCTAssertEqual(timeline.lines.first?.text, "Merhaba dünya 你好")
    }

    func testParsesEnhancedWordTimestamps() {
        let timeline = LRCParser().parse("[00:01.00]<00:01.10>Hello <00:01.80>world")
        XCTAssertEqual(timeline.kind, .wordSynced)
        XCTAssertEqual(timeline.lines.first?.words.count, 2)
        XCTAssertEqual(timeline.lines.first?.words.first?.startTime, 1.1)
        XCTAssertEqual(timeline.lines.first?.words.first?.endTime, 1.8)
    }

    func testInstrumentalGapsHaveLineEndTimes() {
        let timeline = LRCParser().parse("[00:01.00] A\n[00:06.00] B")
        XCTAssertEqual(timeline.lines.first?.endTime, 6)
    }
}
