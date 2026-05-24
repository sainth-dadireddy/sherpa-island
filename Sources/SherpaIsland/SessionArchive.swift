import Foundation

/// Persistent rolling buffer of the N most-recent sessions that were
/// alive but disappeared from monitor.sessions (claude process exited
/// or jsonl went stale beyond the visibility window). Kept in
/// UserDefaults as JSON because the volume is tiny and the data is UI-
/// only.
struct ArchivedSession: Identifiable, Codable, Equatable {
    let id: String
    let projectName: String
    let cwd: String
    let model: String
    let closedAt: Date
    let finalContextTokens: Int
    let estimatedCostUSD: Double
}

enum SessionArchive {
    private static let defaultsKey = "sherpa.recentSessions"
    private static let cap = 10

    static func load() -> [ArchivedSession] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder.iso8601.decode([ArchivedSession].self, from: data)
        else { return [] }
        return decoded
    }

    static func save(_ entries: [ArchivedSession]) {
        guard let data = try? JSONEncoder.iso8601.encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    /// Add a single entry, dedupe by id, cap at `cap` newest-first.
    static func append(_ entry: ArchivedSession) {
        var current = load()
        current.removeAll { $0.id == entry.id }
        current.insert(entry, at: 0)
        if current.count > cap { current.removeLast(current.count - cap) }
        save(current)
    }
}

private extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

private extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
