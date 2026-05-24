import Foundation
import UserNotifications
import AppKit

/// Posts a macOS notification when a pinned session has been idle for
/// more than `idleThreshold` seconds. Throttled per cwd so the same
/// session doesn't spam every minute.
@MainActor
final class IdleNotifier {
    static let shared = IdleNotifier()

    private let idleThreshold: TimeInterval = 15 * 60
    private let notifyCooldown: TimeInterval = 30 * 60

    private var lastNotified: [String: Date] = [:]
    private var authorized = false

    private init() {
        requestAuthIfNeeded()
    }

    private func requestAuthIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    Task { @MainActor in self.authorized = granted }
                }
            case .authorized, .provisional, .ephemeral:
                Task { @MainActor in self.authorized = true }
            default:
                Task { @MainActor in self.authorized = false }
            }
        }
    }

    /// Evaluate the current session list against the pinned cwd set
    /// and fire notifications for any pinned session that has been idle
    /// past the threshold (and hasn't been notified recently).
    func evaluate(sessions: [ClaudeSession], pinnedCwds: Set<String>) {
        guard authorized, !pinnedCwds.isEmpty else { return }
        let now = Date()
        for s in sessions where pinnedCwds.contains(s.cwd) {
            let idle = now.timeIntervalSince(s.lastActivity)
            guard idle >= idleThreshold else { continue }
            if let last = lastNotified[s.cwd], now.timeIntervalSince(last) < notifyCooldown {
                continue
            }
            post(for: s, idleSeconds: idle)
            lastNotified[s.cwd] = now
        }
        // Drop entries for cwds that are no longer pinned.
        lastNotified = lastNotified.filter { pinnedCwds.contains($0.key) }
    }

    private func post(for s: ClaudeSession, idleSeconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Sherpa Island"
        let minutes = Int(idleSeconds / 60)
        content.body = "\(s.projectName) idle \(minutes)m — waiting on you."
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "sherpa.idle.\(s.cwd)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
