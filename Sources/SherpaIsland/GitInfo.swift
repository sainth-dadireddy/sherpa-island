import Foundation

/// Cheap branch lookup for a working directory. Reads `<cwd>/.git/HEAD`
/// directly — no subprocess, no fork, no fs walk. Detached HEAD returns
/// a short SHA. Non-repo or unreadable HEAD returns nil.
///
/// Intentionally does NOT compute dirty state — that requires walking
/// the index, which is too expensive to run on every monitor tick.
enum GitInfo {
    private static var cache: [String: (mtime: Date, branch: String?)] = [:]

    static func branch(for cwd: String) -> String? {
        guard !cwd.isEmpty else { return nil }
        let head = "\(cwd)/.git/HEAD"
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: head),
              let mtime = attrs[.modificationDate] as? Date
        else {
            cache[cwd] = (Date(), nil)
            return nil
        }
        if let cached = cache[cwd], cached.mtime == mtime {
            return cached.branch
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: head)),
              let raw = String(data: data, encoding: .utf8)
        else {
            cache[cwd] = (mtime, nil)
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved: String?
        if trimmed.hasPrefix("ref: refs/heads/") {
            resolved = String(trimmed.dropFirst("ref: refs/heads/".count))
        } else if trimmed.count >= 7 {
            // Detached HEAD — show short sha.
            resolved = String(trimmed.prefix(7))
        } else {
            resolved = nil
        }
        cache[cwd] = (mtime, resolved)
        return resolved
    }

    static func purgeStale(keep: Set<String>) {
        cache = cache.filter { keep.contains($0.key) }
    }
}
