import Foundation

/// Per-session activity sparkline source. Reads the tail of a jsonl,
/// finds ISO timestamps, and buckets them into 12 × 5-minute bins
/// covering the last 60 minutes. Bin 0 = oldest, bin 11 = newest.
///
/// Tail-only + mtime-cached, so subsequent calls on an unchanged file
/// reuse the result.
enum ActivityBuckets {
    static let binCount = 12
    static let binSeconds: TimeInterval = 5 * 60    // 5 minutes

    private static var cache: [String: (mtime: Date, buckets: [Int])] = [:]

    static func compute(jsonlPath: String) -> [Int] {
        guard !jsonlPath.isEmpty else { return Array(repeating: 0, count: binCount) }
        let url = URL(fileURLWithPath: jsonlPath)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: jsonlPath),
              let mtime = attrs[.modificationDate] as? Date
        else {
            return Array(repeating: 0, count: binCount)
        }
        if let cached = cache[jsonlPath], cached.mtime == mtime {
            return cached.buckets
        }
        var buckets = Array(repeating: 0, count: binCount)
        let tail = readTail(url, bytes: 256 * 1024)
        guard !tail.isEmpty else {
            cache[jsonlPath] = (mtime, buckets)
            return buckets
        }
        let now = Date()
        // Scan for `"timestamp":"…"` substrings without full JSON parse —
        // we just need the timestamp string, not the surrounding object.
        var i = tail.startIndex
        let key = "\"timestamp\":\""
        while let r = tail.range(of: key, range: i..<tail.endIndex) {
            let valStart = r.upperBound
            if let endQuote = tail[valStart...].firstIndex(of: "\"") {
                let iso = String(tail[valStart..<endQuote])
                if let ts = isoToDate(iso) {
                    let age = now.timeIntervalSince(ts)
                    if age >= 0 && age < binSeconds * Double(binCount) {
                        let bin = binCount - 1 - Int(age / binSeconds)
                        if bin >= 0 && bin < binCount {
                            buckets[bin] += 1
                        }
                    }
                }
                i = endQuote
            } else {
                break
            }
        }
        cache[jsonlPath] = (mtime, buckets)
        return buckets
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
