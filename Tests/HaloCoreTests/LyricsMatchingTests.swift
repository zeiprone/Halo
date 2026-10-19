import XCTest
@testable import HaloCore

final class LyricsMatchingTests: XCTestCase {
    func testCacheHit() async {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let cache = LyricsCache(directory: directory)
        let track = Track(title: "Song", artist: "Artist", duration: 180)
        let timeline = LyricsTimeline(lines: [LyricLine(startTime: 1, text: "Hi")], kind: .lineSynced, source: "test")
        await cache.store(timeline, for: track)
        let cached = await cache.value(for: track)
        XCTAssertEqual(cached, timeline)
    }

    func testActiveLineSelection() {
        let timeline = LyricsTimeline(
            lines: [
                LyricLine(startTime: 1, endTime: 4, text: "A"),
                LyricLine(startTime: 4, endTime: 8, text: "B")
            ],
            kind: .lineSynced,
            source: "test"
        )
        XCTAssertEqual(timeline.activeLineIndex(at: 4.1), 1)
        XCTAssertNil(timeline.activeLineIndex(at: 0.2))
    }
}
