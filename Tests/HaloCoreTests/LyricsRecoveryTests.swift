import Foundation
import XCTest
@testable import HaloCore

final class LyricsRecoveryTests: XCTestCase {
    func testRemasterVariantMatchesButLiveAndDifferentRecordingDoNot() {
        let track = Track(title: "Signal - 2011 Remaster", artist: "Example", duration: 180)
        XCTAssertNotNil(LyricsMatcher.score(title: "Signal", artist: "Example", duration: 181, track: track))
        XCTAssertNil(LyricsMatcher.score(title: "Signal (Live)", artist: "Example", duration: 181, track: track))
        XCTAssertNil(LyricsMatcher.score(title: "Signal", artist: "Cover Artist", duration: 181, track: track))
        XCTAssertNil(LyricsMatcher.score(title: "Signal", artist: "Example", duration: 230, track: track))
    }

    func testPlainLyricsNeverSelectLastLineAsIfSynced() {
        let timeline = LyricsTimeline(lines: [.init(startTime: 0, text: "First"), .init(startTime: 0, text: "Last")], kind: .plain, source: "test")
        XCTAssertNil(timeline.activeLineIndex(at: 45))
    }

    func testExact404FallsBackToMatchingSyncedSearchResult() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricsStubProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let cache = LyricsCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let provider = LRCLIBProvider(session: session, cache: cache)
        let track = Track(title: "Signal", artist: "Example", album: "Alternate release", duration: 180)
        let result = try await provider.lyrics(for: track)
        XCTAssertEqual(result?.kind, .lineSynced)
        XCTAssertEqual(result?.lines.first?.text, "Correct recording")
    }

    func testCacheSeparatesDifferentReleases() async {
        let cache = LyricsCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let first = Track(title: "Signal", artist: "Example", album: "First", duration: 180)
        let second = Track(title: "Signal", artist: "Example", album: "Live", duration: 180)
        await cache.store(.init(lines: [.init(startTime: 1, text: "First release")], kind: .lineSynced, source: "test"), for: first)
        let cached = await cache.value(for: second)
        XCTAssertNil(cached)
    }
}

private final class LyricsStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let search = request.url!.path.hasSuffix("search")
        let json = search ? #"[{"trackName":"Signal","artistName":"Other Artist","duration":180,"syncedLyrics":"[00:01.00]Wrong artist"},{"trackName":"Signal","artistName":"Example","duration":180,"syncedLyrics":"[00:01.00]Correct recording\n[00:04.00]Next line"}]"# : "{}"
        let response = HTTPURLResponse(url: request.url!, statusCode: search ? 200 : 404, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
