import Foundation
import CryptoKit

public enum LyricsKind: String, Codable, Sendable, Equatable {
    case plain
    case lineSynced
    case wordSynced
}

public struct LyricWord: Codable, Sendable, Equatable {
    public let text: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval?

    public init(text: String, startTime: TimeInterval, endTime: TimeInterval?) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
    }
}

public struct LyricLine: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(startTime)-\(text)" }

    public let startTime: TimeInterval
    public var endTime: TimeInterval?
    public let text: String
    public let words: [LyricWord]

    public init(startTime: TimeInterval, endTime: TimeInterval? = nil, text: String, words: [LyricWord] = []) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.words = words
    }
}

public struct LyricsTimeline: Codable, Sendable, Equatable {
    public let lines: [LyricLine]
    public let kind: LyricsKind
    public let source: String

    public init(lines: [LyricLine], kind: LyricsKind, source: String) {
        self.lines = lines
        self.kind = kind
        self.source = source
    }

    public static let empty = LyricsTimeline(lines: [], kind: .plain, source: "none")

    public func activeLineIndex(at position: TimeInterval, offset: TimeInterval = 0) -> Int? {
        guard kind != .plain else { return nil }
        let t = position + offset
        return lines.lastIndex { line in
            guard line.startTime <= t else { return false }
            if let end = line.endTime { return t < end }
            return true
        }
    }
}

public protocol LyricsProvider: Sendable {
    func lyrics(for track: Track) async throws -> LyricsTimeline?
}

public struct LRCParser: Sendable {
    public init() {}

    public func parse(_ content: String) -> LyricsTimeline {
        let rawLines = content.components(separatedBy: .newlines)
        var parsed: [LyricLine] = []

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let stamps = leadingLineTimestamps(in: trimmed)
            guard !stamps.times.isEmpty else { continue }

            let lyricStart = stamps.consumedUntil
            let body = String(trimmed[lyricStart...])
            let (text, words) = parseWords(in: body)
            let finalText = text.trimmingCharacters(in: .whitespaces)

            for timestamp in stamps.times {
                parsed.append(LyricLine(startTime: timestamp, text: finalText, words: words))
            }
        }

        parsed.sort { $0.startTime < $1.startTime }
        for index in parsed.indices.dropLast() {
            parsed[index].endTime = parsed[index + 1].startTime
        }

        let kind: LyricsKind = parsed.contains { !$0.words.isEmpty } ? .wordSynced : .lineSynced
        return LyricsTimeline(lines: parsed, kind: parsed.isEmpty ? .plain : kind, source: "LRC")
    }

    private func leadingLineTimestamps(in line: String) -> (times: [TimeInterval], consumedUntil: String.Index) {
        var cursor = line.startIndex
        var times: [TimeInterval] = []

        while cursor < line.endIndex, line[cursor] == "[" {
            guard let close = line[cursor...].firstIndex(of: "]") else { break }
            let token = String(line[line.index(after: cursor)..<close])
            guard let time = parseTimestamp(token) else { break }
            times.append(time)
            cursor = line.index(after: close)
        }

        return (times, cursor)
    }

    private func parseWords(in body: String) -> (String, [LyricWord]) {
        var cursor = body.startIndex
        var plain = ""
        var words: [LyricWord] = []
        var pendingStart: TimeInterval?
        var pendingText = ""

        func flush(until end: TimeInterval?) {
            guard let start = pendingStart else { return }
            let text = pendingText
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                words.append(LyricWord(text: text, startTime: start, endTime: end))
            }
            pendingStart = nil
            pendingText = ""
        }

        while cursor < body.endIndex {
            if body[cursor] == "<", let close = body[cursor...].firstIndex(of: ">") {
                let token = String(body[body.index(after: cursor)..<close])
                if let timestamp = parseTimestamp(token) {
                    flush(until: timestamp)
                    pendingStart = timestamp
                    cursor = body.index(after: close)
                    continue
                }
            }

            let char = body[cursor]
            plain.append(char)
            if pendingStart != nil {
                pendingText.append(char)
            }
            cursor = body.index(after: cursor)
        }
        flush(until: nil)

        return (plain, words)
    }

    private func parseTimestamp(_ token: String) -> TimeInterval? {
        let pieces = token.split(separator: ":", maxSplits: 1)
        guard pieces.count == 2,
              let minutes = Double(pieces[0]),
              let seconds = Double(pieces[1].replacingOccurrences(of: ",", with: ".")) else {
            return nil
        }
        return minutes * 60 + seconds
    }
}

public actor LyricsCache {
    private var memory: [String: LyricsTimeline] = [:]
    private let directory: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = base.appendingPathComponent("HaloLyricsCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    public func value(for track: Track) -> LyricsTimeline? {
        let key = cacheKey(for: track)
        if let cached = memory[key] { return cached }
        let url = directory.appendingPathComponent(key).appendingPathExtension("json")
        guard let data = try? Data(contentsOf: url),
              let timeline = try? JSONDecoder().decode(LyricsTimeline.self, from: data) else {
            return nil
        }
        memory[key] = timeline
        return timeline
    }

    public func store(_ timeline: LyricsTimeline, for track: Track) {
        let key = cacheKey(for: track)
        memory[key] = timeline
        let url = directory.appendingPathComponent(key).appendingPathExtension("json")
        if let data = try? JSONEncoder().encode(timeline) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func cacheKey(for track: Track) -> String {
        let raw = "v2|\(track.identity)|\(track.artist)|\(track.title)|\(track.album)|\(track.duration)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct LRCLIBProvider: LyricsProvider {
    private struct Response: Decodable {
        let plainLyrics: String?
        let syncedLyrics: String?
        let instrumental: Bool?
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
    }

    private let session: URLSession
    private let cache: LyricsCache
    private let parser = LRCParser()

    public init(session: URLSession = .shared, cache: LyricsCache = LyricsCache()) {
        self.session = session
        self.cache = cache
    }

    public func lyrics(for track: Track) async throws -> LyricsTimeline? {
        let cached = await cache.value(for: track)
        if let cached, cached.kind != .plain { return cached }
        let query = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album.isEmpty ? nil : track.album),
            URLQueryItem(name: "duration", value: track.duration > 0 ? String(Int(track.duration.rounded())) : nil)
        ].filter { $0.value != nil }

        var fallback = cached
        if let data = try await request(path: "get", query: query) {
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            if let result = timeline(from: decoded) {
                if result.kind != .plain {
                    await cache.store(result, for: track)
                    return result
                }
                fallback = result
            }
        }
        // Album spelling and remaster suffixes frequently differ between services.
        let titles = Array(NSOrderedSet(array: [track.title, LyricsMatcher.normalizedTitle(track.title)])) as? [String] ?? [track.title]
        for title in titles {
            try Task.checkCancellation()
            let query = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: track.artist)]
            guard let data = try await request(path: "search", query: query) else { continue }
            let candidates = try JSONDecoder().decode([Response].self, from: data)
            let matched = candidates.compactMap { candidate -> (Response, Double)? in
                guard let name = candidate.trackName, let artist = candidate.artistName,
                      let duration = candidate.duration,
                      let score = LyricsMatcher.score(title: name, artist: artist, duration: duration, track: track) else { return nil }
                return (candidate, score + (candidate.syncedLyrics?.isEmpty == false ? 4 : 0))
            }.sorted { $0.1 > $1.1 }
            for (candidate, _) in matched {
                guard let result = timeline(from: candidate) else { continue }
                if result.kind != .plain {
                    await cache.store(result, for: track)
                    return result
                }
                if fallback == nil { fallback = result }
            }
        }
        if let fallback { await cache.store(fallback, for: track) }
        return fallback
    }

    private func request(path: String, query: [URLQueryItem]) async throws -> Data? {
        var components = URLComponents(string: "https://lrclib.net/api/" + path)!
        components.queryItems = query
        var request = URLRequest(url: components.url!, timeoutInterval: 12)
        request.setValue("Halo/0.3 (local macOS lyrics client)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { return nil }
        if http.statusCode == 429 {
            throw LyricsRateLimitError(retryAfter: max(30, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60))
        }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return data
    }

    private func timeline(from decoded: Response) -> LyricsTimeline? {
        let timeline: LyricsTimeline?
        if let synced = decoded.syncedLyrics, !synced.isEmpty {
            timeline = parser.parse(synced)
        } else if let plain = decoded.plainLyrics, !plain.isEmpty {
            let lines = plain.components(separatedBy: .newlines).map { LyricLine(startTime: 0, text: $0) }
            timeline = LyricsTimeline(lines: lines, kind: .plain, source: "LRCLIB")
        } else if decoded.instrumental == true {
            timeline = LyricsTimeline(lines: [], kind: .lineSynced, source: "LRCLIB instrumental")
        } else {
            timeline = nil
        }

        return timeline
    }
}

public struct LyricsRateLimitError: LocalizedError, Sendable {
    public let retryAfter: TimeInterval
    public var errorDescription: String? { "Lyrics service is busy. Retrying shortly." }
}

public enum LyricsMatcher {
    public static func normalizedTitle(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: #"(?i)\s*(?:[-–]\s*|\()(?:\d{4}\s+)?(?:remaster(?:ed)?|radio edit|album version)[^)]*\)?\s*$"#, with: "", options: .regularExpression)
        return normalized(stripped)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func score(title: String, artist: String, duration: Double, track: Track) -> Double? {
        guard normalizedTitle(title) == normalizedTitle(track.title),
              normalized(artist) == normalized(track.artist),
              track.duration > 0, abs(duration - track.duration) <= 4 else { return nil }
        return 10 - abs(duration - track.duration)
    }
}

@MainActor
public final class LyricsManager: ObservableObject {
    @Published public private(set) var timeline: LyricsTimeline = .empty
    @Published public private(set) var status: String = "No lyrics loaded."

    private let provider: LyricsProvider
    private var loadTask: Task<Void, Never>?
    private var loadedTrackID: String?
    private var nextRetry = Date.distantFuture
    private var retryCount = 0

    public init(provider: LyricsProvider) {
        self.provider = provider
    }

    public func loadLyrics(for track: Track?, force: Bool = false) {
        if track == nil {
            guard loadedTrackID != nil || status != "Waiting for a music track." else { return }
            loadTask?.cancel()
            loadedTrackID = nil
            timeline = .empty
            status = "Waiting for a music track."
            return
        }
        let changed = loadedTrackID != track?.identity
        guard changed || force || (Date() >= nextRetry && retryCount < 3) else { return }
        if changed || force { retryCount = 0 }
        nextRetry = .distantFuture
        loadedTrackID = track?.identity
        loadTask?.cancel()
        timeline = .empty

        guard let track else {
            timeline = .empty
            status = "No track."
            return
        }

        status = "Loading lyrics..."
        loadTask = Task { [provider] in
            do {
                let fetched = try await provider.lyrics(for: track)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.timeline = fetched ?? .empty
                    self.status = fetched == nil ? "No matching lyrics found." : fetched?.kind == .plain ? "Unsynced lyrics are shown in the overlay and Studio." : "Synced lyrics ready."
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.timeline = .empty
                    self.status = error.localizedDescription
                    self.retryCount += 1
                    self.nextRetry = Date().addingTimeInterval((error as? LyricsRateLimitError)?.retryAfter ?? Double(self.retryCount * 10))
                }
            }
        }
    }
}
