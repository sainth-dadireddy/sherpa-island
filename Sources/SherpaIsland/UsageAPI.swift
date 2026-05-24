import Foundation

/// Live usage percentages pulled from Anthropic's oauth/usage endpoint
/// — the same data Claude's account settings page shows you.
///
/// Each window carries a 0-100 utilization percentage and an optional
/// reset timestamp. Nil windows mean "not applicable for this plan"
/// (e.g. `sevenDayOpus` is null for plans without Opus access).
struct ClaudeUsage: Equatable {
    struct Window: Equatable {
        let utilization: Double    // 0…100
        let resetsAt: Date?
    }

    struct ExtraUsage: Equatable {
        let isEnabled: Bool
        let monthlyLimit: Int
        let usedCredits: Double
        let utilization: Double
    }

    let fiveHour: Window?
    let sevenDay: Window?
    let sevenDaySonnet: Window?
    let sevenDayOpus: Window?
    let extraUsage: ExtraUsage?
    let fetchedAt: Date
}

/// Outcome of a single usage-endpoint hit. The aggregator uses
/// `.rateLimited(retryAfter:)` to back off so we don't keep
/// hammering the endpoint while Anthropic is throttling us.
enum UsageFetchOutcome {
    case success(ClaudeUsage)
    case rateLimited(retryAfter: TimeInterval)
    case failed
}

/// Wraps the Anthropic API calls + Keychain credential read. All of
/// this is best-effort — on any failure we return nil and callers
/// fall back to local jsonl-derived data.
enum UsageAPI {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Read the Claude Code OAuth access token from the macOS Keychain
    /// by shelling out to `/usr/bin/security find-generic-password`.
    ///
    /// Why not `SecItemCopyMatching`? The "Claude Code-credentials"
    /// Keychain item has an ACL that's whitelisted to trusted binaries.
    /// When Claude Code originally writes the token it uses the
    /// `security` CLI, so `/usr/bin/security` ends up on the ACL
    /// automatically. Any later read via that same binary succeeds
    /// silently. A Swift `SecItemCopyMatching` call from our own app
    /// hits a different identity and prompts the user for their login
    /// keychain password — which is terrible UX and the reason Vibe
    /// Island also uses this exact exec path.
    /// Read the access token from the keychain. Never refreshes —
    /// Claude Code handles its own token refresh and writes fresh
    /// tokens to the keychain. We just read whatever's there.
    /// If the token is expired and Claude Code hasn't refreshed it,
    /// we return nil and the UI falls back to jsonl-derived data.
    private static let debugEnabled = ProcessInfo.processInfo.environment["SHERPA_ISLAND_DEBUG"] != nil

    private static func dlog(_ msg: String) {
        guard debugEnabled else { return }
        let line = "[\(Date())] [UsageAPI] \(msg)\n"
        if let data = line.data(using: .utf8),
           let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/sherpa-usage.log")) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? line.data(using: .utf8)?.write(to: URL(fileURLWithPath: "/tmp/sherpa-usage.log"))
        }
    }

    static func accessToken() async -> String? {
        let start = Date()
        dlog("accessToken() entry")
        guard let creds = readCredentials() else {
            dlog("keychain read failed in \(Date().timeIntervalSince(start))s")
            return nil
        }

        let expiresAt = creds.expiresAt / 1000
        let now = Date().timeIntervalSince1970
        let secondsUntilExpiry = expiresAt - now
        let readTime = Date().timeIntervalSince(start)
        if now < expiresAt {
            dlog("creds read ok in \(readTime)s · token expires in \(secondsUntilExpiry)s")
            return creds.accessToken
        }
        dlog("token expired by \(-secondsUntilExpiry)s · returning nil")
        // Expired — return nil, UI will show fallback
        return nil
    }

    private struct Credentials {
        let accessToken: String
        let expiresAt: Double // milliseconds since epoch
    }

    private static func readCredentials() -> Credentials? {
        // The on-disk file (~/.claude/.cred*.json) is fast and avoids the
        // keychain ACL prompt that wedges LSUIElement apps. It's NOT always
        // in sync with the keychain — Claude Code refreshes the keychain
        // token but doesn't always rewrite the file — so only trust it if
        // the embedded expiresAt is still in the future.
        let fileCreds = readCredentialsFile()
        if let f = fileCreds, f.expiresAt / 1000 > Date().timeIntervalSince1970 {
            return f
        }
        dlog("file creds missing or expired — trying keychain")

        // Keychain via `/usr/bin/security`. Account-specific entry first
        // (freshest after a refresh), then the null-account entry. Both
        // are guarded by a 4s timeout in readKeychainEntry so a hung
        // permission prompt can't wedge the polling task.
        if let creds = readKeychainEntry(account: NSUserName()) {
            return creds
        }
        if let creds = readKeychainEntry(account: nil) {
            return creds
        }
        // Last resort: return the (expired) file creds anyway so callers
        // can surface a clearer "token expired" state. accessToken() will
        // reject it.
        return fileCreds
    }

    private static func readCredentialsFile() -> Credentials? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent(".claude/.credentials.json")
        guard let data = try? Data(contentsOf: url) else {
            dlog("credentials file unreadable at \(url.path)")
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              let expires = oauth["expiresAt"] as? Double
        else {
            dlog("credentials file JSON malformed")
            return nil
        }
        dlog("credentials file ok")
        return Credentials(accessToken: token, expiresAt: expires)
    }

    private static func readKeychainEntry(account: String?) -> Credentials? {
        let task = Process()
        task.launchPath = "/usr/bin/security"
        var args = ["find-generic-password", "-s", "Claude Code-credentials"]
        if let acct = account {
            args += ["-a", acct]
        }
        args.append("-w")
        task.arguments = args
        let out = Pipe()
        let err = Pipe()
        task.standardOutput = out
        task.standardError = err
        do {
            try task.run()
        } catch {
            dlog("security exec error: \(error)")
            return nil
        }

        // Bound the wait — a hung keychain prompt (no UI to show on a
        // LSUIElement background app) would otherwise wedge this thread
        // forever. 4s is plenty for a normal find-generic-password call.
        let deadline = Date().addingTimeInterval(4)
        while task.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if task.isRunning {
            task.terminate()
            dlog("security timed out account=\(account ?? "<nil>") — terminated")
            return nil
        }
        guard task.terminationStatus == 0 else {
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? "<no stderr>"
            dlog("security exit \(task.terminationStatus) account=\(account ?? "<nil>") stderr=\(errText)")
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let jsonData = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              let expires = oauth["expiresAt"] as? Double
        else { return nil }

        return Credentials(
            accessToken: token,
            expiresAt: expires
        )
    }

    /// Default backoff when Anthropic returns 429 without a
    /// `Retry-After` header — generous enough that we don't end up in
    /// a 429 loop on a fresh launch.
    private static let defaultRateLimitBackoff: TimeInterval = 60

    /// Hit the usage endpoint with the OAuth token. Returns a
    /// structured outcome so the caller can distinguish a transient
    /// failure (worth retrying soon) from a rate-limit response
    /// (must wait at least `retryAfter` seconds).
    static func fetchUsage() async -> UsageFetchOutcome {
        guard let token = await accessToken() else { return .failed }

        var req = URLRequest(url: endpoint)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 8

        let start = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let elapsed = Date().timeIntervalSince(start)
            guard let http = response as? HTTPURLResponse else {
                dlog("non-HTTP response in \(elapsed)s")
                return .failed
            }
            if http.statusCode == 429 {
                let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(TimeInterval.init)) ?? defaultRateLimitBackoff
                dlog("HTTP 429 in \(elapsed)s · backing off \(retryAfter)s")
                return .rateLimited(retryAfter: retryAfter)
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                dlog("HTTP \(http.statusCode) in \(elapsed)s · body=\(body)")
                return .failed
            }
            guard let parsed = parse(data) else {
                dlog("HTTP 200 in \(elapsed)s · parse failed")
                return .failed
            }
            dlog("HTTP 200 in \(elapsed)s · parsed ok")
            return .success(parsed)
        } catch {
            let elapsed = Date().timeIntervalSince(start)
            dlog("request error in \(elapsed)s: \(error)")
            return .failed
        }
    }

    private static func parse(_ data: Data) -> ClaudeUsage? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        func window(_ key: String) -> ClaudeUsage.Window? {
            guard let dict = obj[key] as? [String: Any],
                  let util = dict["utilization"] as? Double
            else { return nil }
            let reset = (dict["resets_at"] as? String).flatMap(parseTimestamp)
            return ClaudeUsage.Window(utilization: util, resetsAt: reset)
        }

        var extra: ClaudeUsage.ExtraUsage? = nil
        if let ex = obj["extra_usage"] as? [String: Any],
           let enabled = ex["is_enabled"] as? Bool {
            extra = ClaudeUsage.ExtraUsage(
                isEnabled: enabled,
                monthlyLimit: (ex["monthly_limit"] as? Int) ?? 0,
                usedCredits: (ex["used_credits"] as? Double) ?? 0,
                utilization: (ex["utilization"] as? Double) ?? 0
            )
        }

        return ClaudeUsage(
            fiveHour: window("five_hour"),
            sevenDay: window("seven_day"),
            sevenDaySonnet: window("seven_day_sonnet"),
            sevenDayOpus: window("seven_day_opus"),
            extraUsage: extra,
            fetchedAt: Date()
        )
    }

    /// ISO8601 with fractional seconds + timezone offset, matching
    /// the `resets_at` shape Anthropic returns
    /// (e.g. `2026-04-16T01:00:00.038614+00:00`).
    private static func parseTimestamp(_ s: String) -> Date? {
        if let d = formatterFractional.date(from: s) { return d }
        return formatterPlain.date(from: s)
    }

    nonisolated(unsafe) private static let formatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let formatterPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
