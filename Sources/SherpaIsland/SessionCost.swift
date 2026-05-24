import Foundation

/// Cheap per-session token sum for today's jsonl entries. Walks the
/// jsonl tail, totals `input_tokens + output_tokens + cache_read +
/// cache_creation` from any `usage` blocks dated today, and applies
/// Opus retail rates to produce an equivalent-cost figure.
///
/// Mtime-cached so consecutive ticks on an unchanged file reuse the
/// last result.
enum SessionCost {
    private struct Sample: Equatable {
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheCreate: Int

        var totalTokens: Int { input + output + cacheRead + cacheCreate }
    }

    private static var cache: [String: (mtime: Date, sample: Sample)] = [:]

    /// Returns the estimated retail cost (USD) for today's activity in
    /// a given session's jsonl. Returns nil if the file is missing,
    /// hasn't been touched today, or has no usage blocks.
    static func costToday(jsonlPath: String) -> Double? {
        guard let sample = sampleToday(jsonlPath: jsonlPath), sample.totalTokens > 0 else {
            return nil
        }
        // Opus 4.x retail: $5/M in, $25/M out, $0.50/M cache read,
        // $6.25/M cache write.
        return
            Double(sample.input)       / 1_000_000.0 * 5.00 +
            Double(sample.output)      / 1_000_000.0 * 25.00 +
            Double(sample.cacheRead)   / 1_000_000.0 * 0.50 +
            Double(sample.cacheCreate) / 1_000_000.0 * 6.25
    }

    /// Total today-tokens for a jsonl (sum of input/output/cache rw),
    /// or nil if nothing to report.
    static func tokensToday(jsonlPath: String) -> Int? {
        sampleToday(jsonlPath: jsonlPath).flatMap {
            $0.totalTokens > 0 ? $0.totalTokens : nil
        }
    }

    private static func sampleToday(jsonlPath: String) -> Sample? {
        guard !jsonlPath.isEmpty else { return nil }
        let url = URL(fileURLWithPath: jsonlPath)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: jsonlPath),
              let mtime = attrs[.modificationDate] as? Date
        else {
            return nil
        }
        if let cached = cache[jsonlPath], cached.mtime == mtime {
            return cached.sample
        }
        let tail = readTail(url, bytes: 1024 * 1024)
        guard !tail.isEmpty else {
            cache[jsonlPath] = (mtime, Sample(input: 0, output: 0, cacheRead: 0, cacheCreate: 0))
            return cache[jsonlPath]?.sample
        }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        var input = 0, output = 0, cacheRead = 0, cacheCreate = 0
        for line in tail.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ts = (obj["timestamp"] as? String).flatMap(isoToDate),
                  ts >= startOfDay,
                  let msg = obj["message"] as? [String: Any],
                  let usage = msg["usage"] as? [String: Any]
            else { continue }
            input       += (usage["input_tokens"] as? Int) ?? 0
            output      += (usage["output_tokens"] as? Int) ?? 0
            cacheRead   += (usage["cache_read_input_tokens"] as? Int) ?? 0
            cacheCreate += (usage["cache_creation_input_tokens"] as? Int) ?? 0
        }
        let sample = Sample(
            input: input,
            output: output,
            cacheRead: cacheRead,
            cacheCreate: cacheCreate
        )
        cache[jsonlPath] = (mtime, sample)
        return sample
    }

    static func purgeStale(keep: Set<String>) {
        cache = cache.filter { keep.contains($0.key) }
    }

    private static func readTail(_ url: URL, bytes: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let readBytes = UInt64(min(Int(size), bytes))
        try? handle.seek(toOffset: size - readBytes)
        let data = handle.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func isoToDate(_ s: String) -> Date? {
        isoFormatter.date(from: s) ?? isoFallback.date(from: s)
    }
}
