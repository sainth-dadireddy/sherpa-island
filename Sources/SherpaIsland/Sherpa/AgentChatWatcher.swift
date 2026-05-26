// AgentChatWatcher — always-on background watcher for inter-agent chat.
//
// Independent of the AgentChatPopup. Polls agent_chat.db every 4s. On new
// inbound msg addressed to the current user (sai by default):
//   • plays Tink sound
//   • speaks "<sender> sent a message" via NSSpeechSynthesizer
//   • posts a macOS user notification (banner)
//   • increments @Published unread count for the notch/menubar badge
//
// Mirrors the popup's lastSeenMaxId logic but runs always.

import Foundation
import AppKit
import SwiftUI
import SQLite3
import UserNotifications

@MainActor
final class AgentChatWatcher: ObservableObject {
    static let shared = AgentChatWatcher()

    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var lastSender: String = ""
    @Published private(set) var lastSnippet: String = ""

    private let dbPath = NSHomeDirectory() + "/.claude/memory/agent_chat.db"
    private var pollTimer: Timer?
    private var lastSeenMaxId: Int = 0
    private let synth = NSSpeechSynthesizer()
    private var firstRun = true

    private var me: String {
        UserDefaults.standard.string(forKey: "AgentChat.me") ?? "sai"
    }
    private var voiceEnabled: Bool {
        UserDefaults.standard.object(forKey: "AgentChat.voiceEnabled") as? Bool ?? true
    }
    private var notificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: "AgentChat.notificationsEnabled") as? Bool ?? true
    }
    private var soundEnabled: Bool {
        UserDefaults.standard.object(forKey: "AgentChat.soundEnabled") as? Bool ?? true
    }

    private init() {}

    func start() {
        // Request notification authorization (one-time prompt; user can deny)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    func stop() {
        pollTimer?.invalidate(); pollTimer = nil
    }

    private func poll() {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        // On first poll EVER (this process launch), set baseline = current global MAX id.
        // Skip announcing ANY backlog. Only announce truly new msgs that arrive AFTER this.
        if firstRun {
            var maxStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT IFNULL(MAX(id), 0) FROM messages", -1, &maxStmt, nil) == SQLITE_OK,
               sqlite3_step(maxStmt) == SQLITE_ROW {
                lastSeenMaxId = Int(sqlite3_column_int(maxStmt, 0))
            }
            sqlite3_finalize(maxStmt)
            firstRun = false
            return
        }

        // Find new msgs since last seen, targeting current user
        let sql = """
            SELECT m.id, m.from_agent, m.content
            FROM messages m
            WHERE m.id > ?
              AND m.from_agent != ?
              AND (m.to_agent = ? OR m.to_agent = '@all'
                   OR m.mentions LIKE ?
                   OR m.room_id IN (SELECT id FROM rooms WHERE members LIKE ?))
            ORDER BY m.id ASC LIMIT 20
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(lastSeenMaxId))
        sqlite3_bind_text(stmt, 2, me, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, me, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, "%\"\(me)\"%", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, "%\"\(me)\"%", -1, SQLITE_TRANSIENT)

        var newMsgs: [(id: Int, from: String, content: String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = Int(sqlite3_column_int(stmt, 0))
            let from = String(cString: sqlite3_column_text(stmt, 1))
            let content = String(cString: sqlite3_column_text(stmt, 2))
            newMsgs.append((id, from, content))
        }
        guard !newMsgs.isEmpty else { return }

        let maxId = newMsgs.map { $0.id }.max() ?? lastSeenMaxId
        lastSeenMaxId = maxId

        // Update published state for UI
        unreadCount += newMsgs.count
        if let last = newMsgs.last {
            lastSender = last.from
            lastSnippet = String(last.content.prefix(80))
        }

        // Trigger notifications — but cap to last 1 if many arrived at once
        // (avoid voice spam if you've been away).
        let toAnnounce = newMsgs.count > 3 ? [newMsgs.last!] : newMsgs
        for msg in toAnnounce {
            announce(from: msg.from, content: msg.content)
        }
        // If batched, announce count once
        if newMsgs.count > 3, voiceEnabled {
            synth.stopSpeaking()
            synth.startSpeaking("\(newMsgs.count) new agent messages")
        }
    }

    private func announce(from: String, content: String) {
        // Sound (every new msg)
        if soundEnabled {
            NSSound(named: "Tink")?.play()
        }

        // Voice (lightweight: just the sender's name)
        if voiceEnabled {
            // Cancel any in-flight speech so we don't queue up backlogs
            synth.stopSpeaking()
            synth.startSpeaking("\(from) sent a message")
        }

        // macOS banner notification
        if notificationsEnabled {
            let content_ = UNMutableNotificationContent()
            content_.title = "Agent Chat: \(from)"
            content_.body = String(content.prefix(180))
            content_.sound = .default
            let request = UNNotificationRequest(
                identifier: "agent_chat_\(UUID().uuidString)",
                content: content_,
                trigger: nil   // deliver immediately
            )
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }

    /// Called when user opens the chat popup — clears unread badge.
    func clearUnread() {
        unreadCount = 0
    }
}
