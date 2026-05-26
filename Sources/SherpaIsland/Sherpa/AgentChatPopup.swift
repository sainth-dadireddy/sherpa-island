import SwiftUI
import Foundation
import AppKit
import SQLite3

// MARK: - Brand palette (chat = purple/violet)

fileprivate let chatPrimary    = Color(red: 0.51, green: 0.31, blue: 0.85)   // #8250D8 violet
fileprivate let chatAccent     = Color(red: 0.69, green: 0.51, blue: 1.00)   // light violet
fileprivate let chatBg         = Color(red: 0.165, green: 0.192, blue: 0.255)
fileprivate let chatPanel      = Color(red: 0.204, green: 0.235, blue: 0.302)
fileprivate let chatSidebar    = Color(red: 0.145, green: 0.170, blue: 0.230)
fileprivate let chatTextHi     = Color(red: 0.95,  green: 0.96,  blue: 0.98)
fileprivate let chatTextMid    = Color(red: 0.72,  green: 0.75,  blue: 0.80)
fileprivate let chatTextLow    = Color(red: 0.55,  green: 0.58,  blue: 0.64)

fileprivate let knownAgents = ["sai", "claude", "codex", "agy", "ollama", "jules"]

// MARK: - Per-agent color

fileprivate func agentColor(_ name: String) -> Color {
    switch name.lowercased() {
    case "sai":     return Color(red: 0.95, green: 0.45, blue: 0.55)   // human pink
    case "claude":  return Color(red: 0.85, green: 0.50, blue: 0.30)   // claude orange
    case "codex":   return Color(red: 0.30, green: 0.75, blue: 0.55)   // openai green
    case "agy":     return Color(red: 0.45, green: 0.65, blue: 0.95)   // google blue
    case "ollama":  return Color(red: 0.55, green: 0.40, blue: 0.85)   // local purple
    case "jules":   return Color(red: 0.95, green: 0.75, blue: 0.30)   // google yellow
    default:        return chatAccent
    }
}

fileprivate func agentInitial(_ name: String) -> String {
    String(name.prefix(1).uppercased())
}

// MARK: - Per-agent backing model (rendered as small tag under name/avatar)

fileprivate let agentModel: [String: String] = [
    "sai":    "human",
    "claude": "opus-4.7",
    "codex":  "gpt-5.x",
    "agy":    "gemini-3-pro",
    "ollama": "qwen2.5-coder:14b",
    "jules":  "gemini-async",
    "system": "—"
]

fileprivate func modelTag(for agent: String) -> String {
    agentModel[agent.lowercased()] ?? ""
}

// MARK: - Mascot loader (one-shot disk read, cached by NSImage)

fileprivate func loadMascotImage() -> NSImage? {
    if let p = Bundle.main.path(forResource: "erpa-mascot", ofType: "png"),
       let img = NSImage(contentsOfFile: p) {
        return img
    }
    return nil
}

fileprivate func statusColor(_ s: String) -> Color {
    switch s.lowercased() {
    case "new":         return Color(red: 0.55, green: 0.70, blue: 0.95)
    case "in_progress": return Color(red: 0.95, green: 0.70, blue: 0.30)
    case "blocked":     return Color(red: 0.90, green: 0.35, blue: 0.40)
    case "review":      return Color(red: 0.70, green: 0.55, blue: 0.95)
    case "done":        return Color(red: 0.40, green: 0.80, blue: 0.55)
    default:            return chatTextLow
    }
}

fileprivate func priorityColor(_ p: String) -> Color {
    switch p.lowercased() {
    case "p0", "urgent":  return Color(red: 0.95, green: 0.30, blue: 0.35)
    case "p1", "high":    return Color(red: 0.95, green: 0.55, blue: 0.30)
    case "p2", "medium":  return Color(red: 0.85, green: 0.75, blue: 0.30)
    case "p3", "low":     return Color(red: 0.55, green: 0.65, blue: 0.70)
    default:              return chatTextLow
    }
}

// MARK: - Models

struct ChatMessage: Identifiable, Hashable {
    let id: Int
    let from: String
    let to: String
    let content: String
    let createdAt: String
    let readAt: String?
    let replyTo: Int?
    let roomId: String?
    let mentions: String?
    let ticketId: String?
}

struct ChatTicket: Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let category: String
    let ownerAgent: String?
    let status: String
    let priority: String
    let createdBy: String
    let createdAt: String
    let updatedAt: String
    let dueAt: String?
    let parentTicket: String?
    let costUsd: Double?
    let costCeilingUsd: Double?
    let artifact: String?
    let closedAt: String?
    let repo: String?
    let branch: String?
    let prUrl: String?
    let prState: String?
}

struct ChatRoom: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let ticketId: String?
    let members: [String]
    let createdBy: String
    let createdAt: String
    let description: String
}

struct DMPair: Identifiable, Hashable {
    let a: String
    let b: String
    var id: String { "\(a)|\(b)" }
    func other(than me: String) -> String { a == me ? b : a }
}

struct AgentRow: Identifiable, Hashable {
    let name: String
    let displayName: String
    let roleLane: String?
    let modelId: String?
    let provider: String?
    var id: String { name }
}


enum ConvSelection: Hashable {
    case none
    case dm(String, String)   // canonical sorted pair
    case room(String)
    case ticket(String)
    case agent(String)        // AI worker detail
    case kanban               // board view of all tickets grouped by status
}

enum FilterMode: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case mentions = "@Mentions"
    case unread = "Unread"
    var id: String { rawValue }
}

// MARK: - Polling store

@MainActor
final class ChatStore: ObservableObject {
    @Published var messages: [ChatMessage] = []     // messages for current selection
    @Published var dmPairs: [DMPair] = []
    @Published var rooms: [ChatRoom] = []
    @Published var tickets: [ChatTicket] = []
    @Published var workers: [AgentRow] = []
    @Published var onlineAgents: Set<String> = []
    @Published var pollError: String?

    @Published var selection: ConvSelection = .none
    @Published var me: String = UserDefaults.standard.string(forKey: "AgentChat.me") ?? "sai" {
        didSet { UserDefaults.standard.set(me, forKey: "AgentChat.me") }
    }
    @Published var filter: FilterMode = .all

    // Per-conversation unread counts for the current user.
    // Keys: "dm:other" for DMs, "room:<roomId>" for rooms, "ticket:<id>" for tickets.
    @Published var unreadCounts: [String: Int] = [:]
    // Per-message read receipts: msgId -> set of agents that have read it.
    @Published var readBy: [Int: Set<String>] = [:]
    // Track last seen highest msg id so we can play a sound only on truly new arrivals.
    private var lastSeenMaxId: Int = 0
    private var soundEnabled: Bool { UserDefaults.standard.object(forKey: "AgentChat.soundEnabled") as? Bool ?? true }

    private let dbPath = NSHomeDirectory() + "/.claude/memory/agent_chat.db"
    private var pollTimer: Timer?

    func startPolling() {
        load()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate(); pollTimer = nil
    }

    // MARK: - Sends

    func sendMessage(content: String, mentions: [String]) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }

        var roomId: String? = nil
        var ticketId: String? = nil
        var to: String = ""

        switch selection {
        case .dm(let a, let b):
            to = (a == me) ? b : a
        case .room(let rid):
            roomId = rid
            to = "@all"   // broadcast to all room members
        case .ticket(let tid):
            ticketId = tid
            to = "@all"   // ticket msgs broadcast within ticket's room
            // Use ticket's linked room if one exists, else AUTO-CREATE one
            // (isolated to ticket — does NOT leak to team:all anymore).
            if let existing = lookupRoomForTicket(tid) {
                roomId = existing
            } else {
                // Auto-create a per-ticket room with all known agents
                let newId = createRoom(
                    name: "ticket:\(tid)",
                    members: knownAgents,
                    description: "Linked room for \(tid)",
                    ticketId: tid
                )
                roomId = newId
            }
        case .agent:
                HStack { Text("Agent").foregroundColor(chatTextLow); Spacer() }
                    .padding(.horizontal, 16).padding(.vertical, 12).background(chatPanel.opacity(0.5))
            case .kanban:
            // Composer in kanban view broadcasts to team:all (board-wide announcement)
            to = "@all"
            roomId = lookupRoomByName("team:all")
        case .none:
            return false
        }

        let mentionsJSON: String? = mentions.isEmpty ? nil : (try? String(data: JSONSerialization.data(withJSONObject: mentions), encoding: .utf8))

        let sql = "INSERT INTO messages (from_agent, to_agent, content, room_id, ticket_id, mentions) VALUES (?, ?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, me, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, to, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, content, -1, SQLITE_TRANSIENT)
        if let r = roomId { sqlite3_bind_text(stmt, 4, r, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 4) }
        if let t = ticketId { sqlite3_bind_text(stmt, 5, t, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 5) }
        if let m = mentionsJSON { sqlite3_bind_text(stmt, 6, m, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 6) }
        let ok = sqlite3_step(stmt) == SQLITE_DONE
        if ok { load() }
        return ok
    }

    func createDM(with other: String) {
        let pair = canonicalPair(me, other)
        selection = .dm(pair.0, pair.1)
        load()
    }

    /// Look up the room linked to a ticket via rooms.ticket_id.
    private func lookupRoomForTicket(_ ticketId: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT id FROM rooms WHERE ticket_id = ? LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return nil }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, ticketId, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return String(cString: sqlite3_column_text(stmt, 0))
    }

    /// Look up a room id by canonical name (e.g. "team:all").
    private func lookupRoomByName(_ name: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT id FROM rooms WHERE name = ? LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return nil }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return String(cString: sqlite3_column_text(stmt, 0))
    }

    func createRoom(name: String, members: [String], description: String, ticketId: String?) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        let id = nextRoomId(db: db)
        let membersJSON = (try? String(data: JSONSerialization.data(withJSONObject: members), encoding: .utf8)) ?? "[]"
        let sql = "INSERT INTO rooms (id, name, category, ticket_id, members, created_by, description) VALUES (?, ?, ?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, "general", -1, SQLITE_TRANSIENT)
        if let t = ticketId { sqlite3_bind_text(stmt, 4, t, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 4) }
        sqlite3_bind_text(stmt, 5, membersJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, me, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, description, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
        return id
    }

    // MARK: - Member management

    func updateRoomMembers(_ roomId: String, members: [String]) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }
        let membersJSON = (try? String(data: JSONSerialization.data(withJSONObject: members), encoding: .utf8)) ?? "[]"
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE rooms SET members = ? WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, membersJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, roomId, -1, SQLITE_TRANSIENT)
        let ok = sqlite3_step(stmt) == SQLITE_DONE
        if ok { load() }
        return ok
    }

    func addMemberToRoom(_ roomId: String, agent: String) -> Bool {
        guard let room = rooms.first(where: { $0.id == roomId }) else { return false }
        if room.members.contains(agent) { return true }   // already a member
        return updateRoomMembers(roomId, members: room.members + [agent])
    }

    func removeMemberFromRoom(_ roomId: String, agent: String) -> Bool {
        guard let room = rooms.first(where: { $0.id == roomId }) else { return false }
        return updateRoomMembers(roomId, members: room.members.filter { $0 != agent })
    }

    func createTicket(title: String, description: String, owner: String?, priority: String, category: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        let id = nextTicketId(db: db)
        let sql = "INSERT INTO tickets (id, title, description, category, owner_agent, status, priority, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, title, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, description, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, category, -1, SQLITE_TRANSIENT)
        if let o = owner { sqlite3_bind_text(stmt, 5, o, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 5) }
        sqlite3_bind_text(stmt, 6, "new", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, priority, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, me, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
        return id
    }

    func updateTicketStatus(_ id: String, status: String) {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        let sql = "UPDATE tickets SET status=?, updated_at=datetime('now') WHERE id=?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, status, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)
        _ = sqlite3_step(stmt)
        load()
    }

    /// Assign (or unassign) a ticket's owner. Passing nil clears owner.
    func assignTicket(_ id: String, owner: String?) {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = owner == nil
            ? "UPDATE tickets SET owner_agent = NULL, updated_at = datetime('now') WHERE id = ?"
            : "UPDATE tickets SET owner_agent = ?, updated_at = datetime('now') WHERE id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        if let o = owner {
            sqlite3_bind_text(stmt, 1, o, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        }
        _ = sqlite3_step(stmt)
        load()
    }

    func claimTicket(_ id: String) {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        let sql = "UPDATE tickets SET owner_agent=?, status='in_progress', updated_at=datetime('now') WHERE id=?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, me, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)
        _ = sqlite3_step(stmt)
        load()
    }

    // MARK: - Deletes

    func deleteRoom(_ id: String) {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        // Delete messages in the room first, then the room itself
        for sql in ["DELETE FROM messages WHERE room_id=?", "DELETE FROM rooms WHERE id=?"] {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
        // If this room was selected, clear selection
        if case .room(let rid) = selection, rid == id {
            selection = .none
        }
        load()
    }

    func deleteMessage(_ id: Int) {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM messages WHERE id=?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int(stmt, 1, Int32(id))
            _ = sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        load()
    }

    // MARK: - ID helpers

    private func nextRoomId(db: OpaquePointer?) -> String {
        var stmt: OpaquePointer?
        var n = 1
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM rooms", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                n = Int(sqlite3_column_int(stmt, 0)) + 1
            }
        }
        sqlite3_finalize(stmt)
        let candidate = String(format: "R-%03d", n)
        // fallback: append timestamp if collision
        var exists = false
        if sqlite3_prepare_v2(db, "SELECT 1 FROM rooms WHERE id=?", -1, &stmt, nil) == SQLITE_OK {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, candidate, -1, SQLITE_TRANSIENT)
            exists = sqlite3_step(stmt) == SQLITE_ROW
        }
        sqlite3_finalize(stmt)
        if exists {
            return "R-\(Int(Date().timeIntervalSince1970))"
        }
        return candidate
    }

    private func nextTicketId(db: OpaquePointer?) -> String {
        var stmt: OpaquePointer?
        var n = 1
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM tickets", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                n = Int(sqlite3_column_int(stmt, 0)) + 1
            }
        }
        sqlite3_finalize(stmt)
        let candidate = String(format: "T-%03d", n)
        var exists = false
        if sqlite3_prepare_v2(db, "SELECT 1 FROM tickets WHERE id=?", -1, &stmt, nil) == SQLITE_OK {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, candidate, -1, SQLITE_TRANSIENT)
            exists = sqlite3_step(stmt) == SQLITE_ROW
        }
        sqlite3_finalize(stmt)
        if exists {
            return "T-\(Int(Date().timeIntervalSince1970))"
        }
        return candidate
    }

    // MARK: - Load (called every 1.5s)

    private func load() {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            pollError = "open db failed: \(dbPath)"
            return
        }
        defer { sqlite3_close(db) }

        loadDMPairs(db: db)
        loadRooms(db: db)
        loadTickets(db: db)
        loadAgents(db: db)
        loadOnline(db: db)
        loadMessages(db: db)
        loadUnreadCounts(db: db)
        loadReadReceipts(db: db)
        maybePlaySound(db: db)

        // Mark currently visible messages as read for me (when convo is selected,
        // we treat them as seen — drives the unread badge to clear and emits read receipts).
        markVisibleMessagesRead(db: db)

        pollError = nil
    }

    /// When user is actively looking at a conversation, mark its visible messages
    /// as read by `me` so unread badges clear + read receipts go blue for others.
    private func markVisibleMessagesRead(db: OpaquePointer?) {
        guard !messages.isEmpty else { return }
        let ids = messages.filter { $0.from != me }.map { $0.id }
        guard !ids.isEmpty else { return }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for mid in ids {
            var stmt: OpaquePointer?
            let sql = "INSERT OR IGNORE INTO message_reads (message_id, agent, read_at) VALUES (?, ?, datetime('now'))"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(mid))
                sqlite3_bind_text(stmt, 2, me, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    private func loadDMPairs(db: OpaquePointer?) {
        var stmt: OpaquePointer?
        var pairs = Set<String>()
        var result: [DMPair] = []
        let sql = "SELECT DISTINCT from_agent, to_agent FROM messages WHERE (room_id IS NULL OR room_id='') AND (ticket_id IS NULL OR ticket_id='')"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let fRaw = String(cString: sqlite3_column_text(stmt, 0))
                let tRaw = String(cString: sqlite3_column_text(stmt, 1))
                let f = fRaw.lowercased()
                let t = tRaw.lowercased()
                // Filter out non-DM rows masquerading as DMs
                if t.isEmpty || f.isEmpty { continue }
                if t == "room" || t == "ticket" || t == "@all" || t == "all" { continue }
                if f == t { continue }  // self-DM noise
                let p = canonicalPair(f, t)
                let key = "\(p.0)|\(p.1)"
                if pairs.insert(key).inserted {
                    result.append(DMPair(a: p.0, b: p.1))
                }
            }
        }
        sqlite3_finalize(stmt)
        // Ensure built-in pairs exist for "me" so user can start a DM with no history
        for other in knownAgents where other != me {
            let p = canonicalPair(me, other)
            let key = "\(p.0)|\(p.1)"
            if pairs.insert(key).inserted {
                result.append(DMPair(a: p.0, b: p.1))
            }
        }
        result.sort { "\($0.a)\($0.b)" < "\($1.a)\($1.b)" }
        if result != dmPairs { dmPairs = result }
    }

    /// Compute unread counts per conversation for the current user, using message_reads receipts.
    private func loadUnreadCounts(db: OpaquePointer?) {
        var counts: [String: Int] = [:]
        // For each msg the user could see (DM to me, @all, mentioned me, room with me as member)
        // count those without a message_reads entry for me.
        let sql = """
            SELECT m.id, m.from_agent, m.to_agent, m.room_id
            FROM messages m
            WHERE m.from_agent != ?
              AND (m.to_agent = ? OR m.to_agent = '@all'
                   OR m.mentions LIKE ?
                   OR m.room_id IN (SELECT id FROM rooms WHERE members LIKE ?))
              AND NOT EXISTS (
                SELECT 1 FROM message_reads r
                WHERE r.message_id = m.id AND r.agent = ?
              )
        """
        var stmt: OpaquePointer?
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, me, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, me, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, "%\"\(me)\"%", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, "%\"\(me)\"%", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, me, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let from = String(cString: sqlite3_column_text(stmt, 1))
                let to = String(cString: sqlite3_column_text(stmt, 2))
                let roomId: String? = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 3))
                if let rid = roomId, !rid.isEmpty {
                    counts["room:\(rid)", default: 0] += 1
                } else if to == me {
                    counts["dm:\(from)", default: 0] += 1
                }
            }
        }
        sqlite3_finalize(stmt)
        if counts != unreadCounts { unreadCounts = counts }
    }

    /// Load read receipts (which agents have read which msg) for currently visible messages.
    private func loadReadReceipts(db: OpaquePointer?) {
        guard !messages.isEmpty else {
            if !readBy.isEmpty { readBy = [:] }
            return
        }
        let ids = messages.map { String($0.id) }.joined(separator: ",")
        var out: [Int: Set<String>] = [:]
        var stmt: OpaquePointer?
        let sql = "SELECT message_id, agent FROM message_reads WHERE message_id IN (\(ids))"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let mid = Int(sqlite3_column_int(stmt, 0))
                let agent = String(cString: sqlite3_column_text(stmt, 1))
                out[mid, default: []].insert(agent)
            }
        }
        sqlite3_finalize(stmt)
        if out != readBy { readBy = out }
    }

    /// Play a soft notification sound when new msgs arrive (current user not the sender).
    private func maybePlaySound(db: OpaquePointer?) {
        guard soundEnabled else { return }
        var stmt: OpaquePointer?
        var maxId = 0
        if sqlite3_prepare_v2(db, "SELECT MAX(id) FROM messages WHERE from_agent != ?", -1, &stmt, nil) == SQLITE_OK {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, me, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                maxId = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        if lastSeenMaxId == 0 {
            // first load — set baseline, don't play sound
            lastSeenMaxId = maxId
            return
        }
        if maxId > lastSeenMaxId {
            lastSeenMaxId = maxId
            NSSound(named: "Tink")?.play()
        }
    }

    private func loadRooms(db: OpaquePointer?) {
        var stmt: OpaquePointer?
        var result: [ChatRoom] = []
        // Exclude dm:* auto-rooms and group rooms.
        let sql = """
            SELECT id, name, category, ticket_id, members, created_by, created_at, description
            FROM rooms
            WHERE name NOT LIKE 'dm:%'
              AND (name NOT LIKE 'team:%' AND name NOT LIKE 'ticket:%')
              AND COALESCE(category, '') != 'group'
            ORDER BY created_at DESC LIMIT 50
        """
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let name = String(cString: sqlite3_column_text(stmt, 1))
                let cat = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? "" : String(cString: sqlite3_column_text(stmt, 2))
                let tid: String? = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 3))
                let membersJSON = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? "[]" : String(cString: sqlite3_column_text(stmt, 4))
                let createdBy = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? "" : String(cString: sqlite3_column_text(stmt, 5))
                let createdAt = sqlite3_column_type(stmt, 6) == SQLITE_NULL ? "" : String(cString: sqlite3_column_text(stmt, 6))
                let desc = sqlite3_column_type(stmt, 7) == SQLITE_NULL ? "" : String(cString: sqlite3_column_text(stmt, 7))
                let members = parseMembers(membersJSON)
                result.append(ChatRoom(id: id, name: name, category: cat, ticketId: tid, members: members, createdBy: createdBy, createdAt: createdAt, description: desc))
            }
        }
        sqlite3_finalize(stmt)
        if result != rooms { rooms = result }
    }

    private func loadTickets(db: OpaquePointer?) {
        var stmt: OpaquePointer?
        var result: [ChatTicket] = []
        let sql = "SELECT id, title, description, category, owner_agent, status, priority, created_by, created_at, updated_at, due_at, parent_ticket, cost_usd, cost_ceiling_usd, artifact, closed_at, repo, branch, pr_url, pr_state FROM tickets ORDER BY updated_at DESC, created_at DESC LIMIT 20"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let title = String(cString: sqlite3_column_text(stmt, 1))
                let desc = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? "" : String(cString: sqlite3_column_text(stmt, 2))
                let cat = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? "" : String(cString: sqlite3_column_text(stmt, 3))
                let owner: String? = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 4))
                let status = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? "new" : String(cString: sqlite3_column_text(stmt, 5))
                let prio = sqlite3_column_type(stmt, 6) == SQLITE_NULL ? "p2" : String(cString: sqlite3_column_text(stmt, 6))
                let by = sqlite3_column_type(stmt, 7) == SQLITE_NULL ? "" : String(cString: sqlite3_column_text(stmt, 7))
                let ca = sqlite3_column_type(stmt, 8) == SQLITE_NULL ? "" : String(cString: sqlite3_column_text(stmt, 8))
                let ua = sqlite3_column_type(stmt, 9) == SQLITE_NULL ? "" : String(cString: sqlite3_column_text(stmt, 9))
                let due: String? = sqlite3_column_type(stmt, 10) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 10))
                let parent: String? = sqlite3_column_type(stmt, 11) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 11))
                let costUsd: Double? = sqlite3_column_type(stmt, 12) == SQLITE_NULL ? nil : Double(sqlite3_column_double(stmt, 12))
                let costCeiling: Double? = sqlite3_column_type(stmt, 13) == SQLITE_NULL ? nil : Double(sqlite3_column_double(stmt, 13))
                let artifact: String? = sqlite3_column_type(stmt, 14) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 14))
                let closedAt: String? = sqlite3_column_type(stmt, 15) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 15))
                let repo: String? = sqlite3_column_type(stmt, 16) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 16))
                let branch: String? = sqlite3_column_type(stmt, 17) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 17))
                let prUrl: String? = sqlite3_column_type(stmt, 18) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 18))
                let prState: String? = sqlite3_column_type(stmt, 19) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 19))
                result.append(ChatTicket(id: id, title: title, description: desc, category: cat, ownerAgent: owner, status: status, priority: prio, createdBy: by, createdAt: ca, updatedAt: ua, dueAt: due, parentTicket: parent, costUsd: costUsd, costCeilingUsd: costCeiling, artifact: artifact, closedAt: closedAt, repo: repo, branch: branch, prUrl: prUrl, prState: prState))
            }
        }
        sqlite3_finalize(stmt)
        if result != tickets { tickets = result }
    }

    private func loadAgents(db: OpaquePointer?) {
        var stmt: OpaquePointer?
        var result: [AgentRow] = []
        let sql = "SELECT name, display_name, role_lane, model_id, provider FROM agents WHERE enabled=1 ORDER BY name"
        var usesFallback = true
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                usesFallback = false
                let name = String(cString: sqlite3_column_text(stmt, 0))
                let displayName = sqlite3_column_type(stmt, 1) == SQLITE_NULL ? name : String(cString: sqlite3_column_text(stmt, 1))
                let roleLane: String? = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 2))
                let modelId: String? = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 3))
                let provider: String? = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 4))
                result.append(AgentRow(name: name, displayName: displayName, roleLane: roleLane, modelId: modelId, provider: provider))
            }
        }
        sqlite3_finalize(stmt)
        
        if usesFallback || result.isEmpty {
            result = [
                AgentRow(name: "pm", displayName: "Project Manager", roleLane: "pm", modelId: "claude-haiku-4.5", provider: "anthropic"),
                AgentRow(name: "eng", displayName: "Engineer", roleLane: "eng", modelId: "qwen3-coder", provider: "alibaba"),
                AgentRow(name: "reviewer", displayName: "Reviewer", roleLane: "review", modelId: "deepseek-r1", provider: "deepseek"),
                AgentRow(name: "qa", displayName: "QA", roleLane: "qa", modelId: "claude-haiku-4.5", provider: "anthropic")
            ]
        }
        
        if result != workers { workers = result }
    }

    private func loadOnline(db: OpaquePointer?) {
        var stmt: OpaquePointer?
        var set = Set<String>()
        let sql = "SELECT DISTINCT from_agent FROM messages WHERE created_at > datetime('now', '-5 minutes')"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                set.insert(String(cString: sqlite3_column_text(stmt, 0)))
            }
        }
        sqlite3_finalize(stmt)
        if set != onlineAgents { onlineAgents = set }
    }

    private func loadMessages(db: OpaquePointer?) {
        var stmt: OpaquePointer?
        var result: [ChatMessage] = []

        var sql = "SELECT id, from_agent, to_agent, content, created_at, read_at, reply_to, room_id, mentions, ticket_id FROM messages WHERE 1=1"
        var binds: [(Int32, String)] = []

        switch selection {
        case .none:
            // show nothing
            sql += " AND 1=0"
        case .dm(let a, let b):
            sql += " AND (room_id IS NULL OR room_id='') AND (ticket_id IS NULL OR ticket_id='') AND ((from_agent=? AND to_agent=?) OR (from_agent=? AND to_agent=?))"
            binds.append((1, a)); binds.append((2, b))
            binds.append((3, b)); binds.append((4, a))
        case .room(let rid):
            sql += " AND room_id=?"
            binds.append((1, rid))
        case .ticket(let tid):
            sql += " AND ticket_id=?"
            binds.append((1, tid))
        case .agent:
            // No message feed for agent detail
            sql += " AND 1=0"
        case .kanban:
            // No message feed in kanban — the main pane shows the board grid instead
            sql += " AND 1=0"
        }

        // Filter mode (Active = last 24h, Mentions = me in mentions, Unread = read_at NULL and not from me)
        switch filter {
        case .all: break
        case .active:
            sql += " AND created_at > datetime('now', '-1 day')"
        case .mentions:
            sql += " AND mentions LIKE ?"
            binds.append((Int32(binds.count + 1), "%\"\(me)\"%"))
        case .unread:
            sql += " AND read_at IS NULL AND from_agent != ?"
            binds.append((Int32(binds.count + 1), me))
        }

        sql += " ORDER BY id ASC LIMIT 500"

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for (idx, val) in binds {
                sqlite3_bind_text(stmt, idx, val, -1, SQLITE_TRANSIENT)
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(stmt, 0))
                let from = String(cString: sqlite3_column_text(stmt, 1))
                let to = String(cString: sqlite3_column_text(stmt, 2))
                let content = String(cString: sqlite3_column_text(stmt, 3))
                let createdAt = sqlite3_column_type(stmt, 4) == SQLITE_NULL ? "" : String(cString: sqlite3_column_text(stmt, 4))
                let readAt: String? = sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 5))
                let replyTo: Int? = sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 6))
                let roomId: String? = sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 7))
                let mentions: String? = sqlite3_column_type(stmt, 8) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 8))
                let ticketId: String? = sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, 9))
                result.append(ChatMessage(id: id, from: from, to: to, content: content, createdAt: createdAt, readAt: readAt, replyTo: replyTo, roomId: roomId, mentions: mentions, ticketId: ticketId))
            }
        }
        sqlite3_finalize(stmt)
        if result.map(\.id) != messages.map(\.id) || result.count != messages.count {
            messages = result
        }
    }

    // MARK: - utils

    func canonicalPair(_ a: String, _ b: String) -> (String, String) {
        if a <= b { return (a, b) } else { return (b, a) }
    }

    private func parseMembers(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return arr.compactMap { $0 as? String }
    }
}

// MARK: - Message grouping

fileprivate struct MessageGroup: Identifiable {
    let id: Int  // first message id
    let from: String
    let messages: [ChatMessage]
}

fileprivate func groupMessages(_ msgs: [ChatMessage]) -> [MessageGroup] {
    var out: [MessageGroup] = []
    var current: [ChatMessage] = []
    var lastFrom: String? = nil
    for m in msgs {
        if m.from == lastFrom {
            current.append(m)
        } else {
            if !current.isEmpty {
                out.append(MessageGroup(id: current[0].id, from: lastFrom ?? "?", messages: current))
            }
            current = [m]
            lastFrom = m.from
        }
    }
    if !current.isEmpty {
        out.append(MessageGroup(id: current[0].id, from: lastFrom ?? "?", messages: current))
    }
    return out
}

// MARK: - Main view

struct AgentChatPopupView: View {
    @StateObject private var store = ChatStore()
    @State private var composeText: String = ""
    @State private var kanbanTypeFilter: String = "all"
    @State private var bdSyncResult: String? = nil
    @State private var rightOpen: Bool = true
    @State private var showNewConvSheet: Bool = false
    @State private var showMentionPopover: Bool = false
    @State private var mentionPrefix: String = ""
    @AppStorage("sidebar.collapsed.dm") private var dmCollapsed: Bool = false
    @AppStorage("sidebar.collapsed.rooms") private var roomsCollapsed: Bool = false
    @AppStorage("sidebar.collapsed.workers") private var workersCollapsed: Bool = false
    @State private var showWorkersBoard: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            topToolbar
            Divider().background(chatPrimary.opacity(0.25))
            HStack(spacing: 0) {
                leftSidebar
                Divider().background(chatPrimary.opacity(0.15))
                mainPane
                if rightOpen {
                    Divider().background(chatPrimary.opacity(0.15))
                    rightSidebar
                }
            }
        }
        .background(chatBg.ignoresSafeArea())
        .onAppear { store.startPolling() }
        .onDisappear { store.stopPolling() }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .sheet(isPresented: $showNewConvSheet) {
            NewConversationSheet(store: store, isPresented: $showNewConvSheet)
        }
        .onChange(of: store.selection) { _, newVal in
            // Picking a real conversation drops you out of the workers board.
            // Ignore .none transitions (the Agents row itself sets selection = .none
            // before flipping showWorkersBoard = true — we don't want to fight it).
            if showWorkersBoard && newVal != .none {
                showWorkersBoard = false
            }
        }
    }

    // MARK: - Top toolbar

    private var topToolbar: some View {
        HStack(spacing: 10) {
            MascotHeaderView()
            Text("Sherpa Chat")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(chatTextHi)

            Button {
                showNewConvSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 11, weight: .semibold))
                    Text("New Conversation").font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [chatAccent, chatPrimary],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                )
            }
            .buttonStyle(.plain)

            Spacer()

            // Filter picker
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11)).foregroundColor(chatTextMid)
                Picker("Filter", selection: $store.filter) {
                    ForEach(FilterMode.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(chatAccent)
                .frame(width: 110)
            }

            // Identity picker
            HStack(spacing: 6) {
                Text("you are:").font(.system(size: 10)).foregroundColor(chatTextLow)
                identityBadge(store.me)
                Picker("Me", selection: $store.me) {
                    ForEach(knownAgents, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(chatAccent)
                .frame(width: 90)
            }


            Button {
                rightOpen.toggle()
            } label: {
                Image(systemName: rightOpen ? "sidebar.right" : "sidebar.right")
                    .font(.system(size: 13))
                    .foregroundColor(rightOpen ? chatAccent : chatTextMid)
            }
            .buttonStyle(.plain)
            .help(rightOpen ? "Hide details" : "Show details")

            if let err = store.pollError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange).help(err)
            } else {
                Circle().fill(.green).frame(width: 6, height: 6).help("Live (4s)")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(chatPanel)
    }

    // MARK: - Left sidebar

    private var leftSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sidebarSection(title: "Direct Messages", icon: "bubble.left", isCollapsed: $dmCollapsed, count: store.dmPairs.count) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(store.dmPairs) { pair in
                            let other = pair.other(than: store.me)
                            let pairKey = ConvSelection.dm(pair.a, pair.b)
                            let unread = store.unreadCounts["dm:\(other)"] ?? 0
                            sidebarRow(
                                isActive: store.selection == pairKey,
                                leading: {
                                    AnyView(
                                        VStack(spacing: 1) {
                                            agentBadge(other, size: 18)
                                            let tag = modelTag(for: other)
                                            if !tag.isEmpty {
                                                Text(tag)
                                                    .font(.system(size: 8, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                                    .opacity(0.7)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)
                                            }
                                        }
                                        .frame(width: 28)
                                    )
                                }
                            ) {
                                Text(other)
                                    .font(.system(size: 12, weight: unread > 0 ? .bold : .medium))
                                    .foregroundColor(chatTextHi)
                                if store.onlineAgents.contains(other) {
                                    Circle().fill(.green).frame(width: 5, height: 5)
                                }
                                Spacer(minLength: 4)
                                if unread > 0 {
                                    Text("\(unread)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Capsule().fill(chatAccent))
                                }
                            } onTap: {
                                store.selection = pairKey
                            }
                        }
                        if store.dmPairs.isEmpty {
                            Text("no dms yet").font(.system(size: 10)).foregroundColor(chatTextLow)
                                .padding(.horizontal, 8)
                        }
                    }
                }

                sidebarSection(title: "Rooms", icon: "person.3", isCollapsed: $roomsCollapsed, count: store.rooms.count) {
                    VStack(alignment: .leading, spacing: 1) {
                        let myRooms = store.rooms.filter { $0.members.contains(store.me) || $0.members.isEmpty }
                        ForEach(myRooms) { room in
                            let key = ConvSelection.room(room.id)
                            let unread = store.unreadCounts["room:\(room.id)"] ?? 0
                            sidebarRow(
                                isActive: store.selection == key,
                                leading: {
                                    AnyView(
                                        Image(systemName: "number")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(chatAccent)
                                            .frame(width: 18, height: 18)
                                    )
                                }
                            ) {
                                Text(room.name)
                                    .font(.system(size: 12, weight: unread > 0 ? .bold : .medium))
                                    .foregroundColor(chatTextHi).lineLimit(1)
                                Spacer(minLength: 4)
                                if unread > 0 {
                                    Text("\(unread)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Capsule().fill(chatAccent))
                                } else {
                                    Text("\(room.members.count)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(chatTextLow)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Capsule().fill(chatPanel))
                                }
                            } onTap: {
                                store.selection = key
                            }
                            .contextMenu {
                                Button("Delete room", role: .destructive) {
                                    confirmAndDeleteRoom(room)
                                }
                            }
                        }
                        if myRooms.isEmpty {
                            Text("no rooms").font(.system(size: 10)).foregroundColor(chatTextLow)
                                .padding(.horizontal, 8)
                        }
                    }
                }

                // Pinned Kanban board view above per-ticket entries.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "rectangle.grid.3x2").font(.system(size: 10, weight: .semibold))
                            .foregroundColor(chatAccent)
                        Text("BOARD".uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(chatTextMid)
                            .tracking(0.5)
                    }
                    .padding(.horizontal, 10)
                    VStack(alignment: .leading, spacing: 1) {
                    sidebarRow(
                        isActive: store.selection == .kanban,
                        leading: {
                            AnyView(
                                Image(systemName: "square.grid.3x2.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(chatAccent)
                                    .frame(width: 18, height: 18)
                            )
                        }
                    ) {
                        Text("Kanban").font(.system(size: 12, weight: .medium))
                            .foregroundColor(chatTextHi)
                        Spacer(minLength: 4)
                        let openCount = store.tickets.filter { $0.status != "done" }.count
                        if openCount > 0 {
                            Text("\(openCount)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(chatTextLow)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(chatPanel))
                        }
                    } onTap: {
                        store.selection = .kanban
                    }
                    }
                }

                sidebarSection(title: "AI Workers", icon: "cpu", isCollapsed: $workersCollapsed, count: 1) {
                    VStack(alignment: .leading, spacing: 1) {
                        sidebarRow(
                            isActive: showWorkersBoard,
                            leading: {
                                AnyView(
                                    Image(systemName: "person.3.sequence")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(chatAccent)
                                        .frame(width: 18, height: 18)
                                )
                            }
                        ) {
                            Text("Agents")
                                .font(.system(size: 12, weight: showWorkersBoard ? .bold : .medium))
                                .foregroundColor(chatTextHi)
                            Spacer(minLength: 4)
                            Text("\(allWorkerCards().count)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(chatTextLow)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Capsule().fill(chatPanel))
                        } onTap: {
                            store.selection = .none
                            showWorkersBoard = true
                        }
                    }
                }

                // Per-ticket entries removed — use Kanban board view instead.
                // (Click any card in Kanban to open that ticket's convo.)
                Spacer(minLength: 8)
            }
            .padding(.vertical, 12)
        }
        .frame(width: 180)
        .background(chatSidebar)
    }

    private func sidebarSection<C: View>(title: String, icon: String, isCollapsed: Binding<Bool>, count: Int = 0, onTap: (() -> Void)? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if let action = onTap {
                    action()
                } else {
                    isCollapsed.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isCollapsed.wrappedValue ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(chatAccent)
                    Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                        .foregroundColor(chatAccent)
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(chatTextMid)
                        .tracking(0.5)
                    if count > 0 {
                        Text("(\(count))")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(chatTextLow)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
            }
            .buttonStyle(.plain)
            if !isCollapsed.wrappedValue {
                content()
            }
        }
    }

    private func sidebarRow<L: View>(
        isActive: Bool,
        leading: () -> AnyView,
        @ViewBuilder _ label: () -> L,
        onTap: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            leading()
            label()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(
            HStack(spacing: 0) {
                Rectangle().fill(isActive ? chatAccent : Color.clear).frame(width: 2)
                Rectangle().fill(isActive ? chatAccent.opacity(0.12) : Color.clear)
            }
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    // MARK: - Main pane

    private var mainPane: some View {
        VStack(spacing: 0) {
            if showWorkersBoard {
                WorkersBoardView()
            } else {
                conversationHeader
                Divider().background(chatPrimary.opacity(0.15))
                if store.selection == .kanban {
                    kanbanBoard
                } else if case .agent(let name) = store.selection {
                    AgentDetailPane(agentName: name)
                } else {
                    messageFeed
                    Divider().background(chatPrimary.opacity(0.25))
                    composer
                }
            }
        }
        .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var conversationHeader: some View {
        Group {
            switch store.selection {
            case .none:
                HStack {
                    Text("Pick a conversation from the left")
                        .font(.system(size: 12)).foregroundColor(chatTextLow)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(chatPanel.opacity(0.5))
            case .dm(let a, let b):
                let other = (a == store.me) ? b : a
                HStack(spacing: 10) {
                    agentBadge(other, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(other).font(.system(size: 13, weight: .semibold)).foregroundColor(chatTextHi)
                        HStack(spacing: 4) {
                            Circle().fill(store.onlineAgents.contains(other) ? .green : chatTextLow.opacity(0.4))
                                .frame(width: 5, height: 5)
                            Text(store.onlineAgents.contains(other) ? "online" : "idle")
                                .font(.system(size: 10)).foregroundColor(chatTextMid)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(chatPanel.opacity(0.5))
            case .room(let rid):
                if let room = store.rooms.first(where: { $0.id == rid }) {
                    HStack(spacing: 10) {
                        Image(systemName: "number")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(chatAccent)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(chatPanel))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(room.name).font(.system(size: 13, weight: .semibold)).foregroundColor(chatTextHi)
                            Text("\(room.members.count) members · \(room.category)")
                                .font(.system(size: 10)).foregroundColor(chatTextMid)
                        }
                        Spacer()
                        HStack(spacing: -4) {
                            ForEach(room.members.prefix(5), id: \.self) { m in
                                agentBadge(m, size: 18)
                                    .overlay(Circle().stroke(chatPanel, lineWidth: 1.5))
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(chatPanel.opacity(0.5))
                }
            case .ticket(let tid):
                if let t = store.tickets.first(where: { $0.id == tid }) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundColor(statusColor(t.status))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(chatPanel))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title).font(.system(size: 13, weight: .semibold)).foregroundColor(chatTextHi)
                            HStack(spacing: 6) {
                                Text(t.id).font(.system(size: 10, design: .monospaced)).foregroundColor(chatTextLow)
                                statusPill(t.status)
                                priorityPill(t.priority)
                            }
                        }
                        Spacer()
                        if t.ownerAgent != store.me {
                            Button {
                                store.claimTicket(t.id)
                            } label: {
                                Text("Claim")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(chatPrimary))
                            }
                            .buttonStyle(.plain)
                        }
                        Menu {
                            ForEach(["new", "in_progress", "blocked", "review", "done"], id: \.self) { s in
                                Button(s) { store.updateTicketStatus(t.id, status: s) }
                            }
                        } label: {
                            Text("Status").font(.system(size: 11))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 5).fill(chatPanel))
                                .foregroundColor(chatTextHi)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(chatPanel.opacity(0.5))
                }
            case .agent:
                HStack { Text("Agent").foregroundColor(chatTextLow); Spacer() }
                    .padding(.horizontal, 16).padding(.vertical, 12).background(chatPanel.opacity(0.5))
            case .kanban:
                HStack(spacing: 10) {
                    Image(systemName: "square.grid.3x2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(chatAccent)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(chatPanel))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Kanban Board").font(.system(size: 13, weight: .semibold)).foregroundColor(chatTextHi)
                        Text("\(store.tickets.filter { $0.status != "done" }.count) open · \(store.tickets.count) total")
                            .font(.system(size: 10)).foregroundColor(chatTextMid)
                    }
                    Spacer()
                    Button {
                        showNewConvSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("New ticket")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(chatAccent))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(chatPanel.opacity(0.5))
            }
        }
    }

    // MARK: - Kanban board

    private let kanbanColumns: [(String, String)] = [
        ("new", "New"),
        ("in_progress", "In progress"),
        ("blocked", "Blocked"),
        ("review", "Review"),
        ("done", "Done")
    ]

    private var kanbanBoard: some View {
        VStack(spacing: 0) {
            // Filter toolbar: type (epic / story / bug / task / review) + bd sync
            HStack(spacing: 10) {
                Text("Type:").font(.system(size: 11)).foregroundColor(chatTextLow)
                Picker("", selection: $kanbanTypeFilter) {
                    Text("all").tag("all")
                    Text("epic").tag("epic")
                    Text("story").tag("story")
                    Text("bug").tag("bug")
                    Text("task").tag("task")
                    Text("review").tag("review")
                    Text("docs").tag("docs")
                }
                .pickerStyle(.menu)
                .frame(width: 100)

                Spacer()

                Button {
                    syncBeads()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Sync beads")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(chatTextHi)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(chatPanel))
                }
                .buttonStyle(.plain)
                .help("Push current tickets to ~/.beads/beads.db via `bd` CLI")

                if let result = bdSyncResult {
                    Text(result)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(chatTextLow)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(chatPanel.opacity(0.3))

            kanbanColumnsView
        }
    }

    private var kanbanColumnsView: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(kanbanColumns, id: \.0) { (status, label) in
                    let cards = store.tickets.filter {
                        $0.status == status &&
                        (kanbanTypeFilter == "all" || $0.category == kanbanTypeFilter)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Circle().fill(statusColor(status)).frame(width: 8, height: 8)
                            Text(label).font(.system(size: 12, weight: .semibold))
                                .foregroundColor(chatTextHi)
                            Spacer()
                            Text("\(cards.count)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(chatTextLow)
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 8)

                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(cards) { t in
                                    kanbanCard(t)
                                }
                                if cards.isEmpty {
                                    Text("empty")
                                        .font(.system(size: 10))
                                        .foregroundColor(chatTextLow.opacity(0.6))
                                        .padding(.vertical, 12)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 8)
                        }
                    }
                    .frame(width: 220)
                    .background(RoundedRectangle(cornerRadius: 10).fill(chatPanel.opacity(0.35)))
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(chatBg)
    }

    private func kanbanCard(_ t: ChatTicket) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Type pill (epic / story / bug / task / review / docs)
                if !t.category.isEmpty {
                    Text(t.category)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(typeColor(t.category)))
                }
                priorityPill(t.priority)
                Spacer()
                Text(t.id).font(.system(size: 9, design: .monospaced))
                    .foregroundColor(chatTextLow)
            }
            Text(t.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(chatTextHi)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 4) {
                if let owner = t.ownerAgent, !owner.isEmpty {
                    agentBadge(owner, size: 14)
                    Text(owner).font(.system(size: 10)).foregroundColor(chatTextMid)
                } else {
                    Text("unassigned").font(.system(size: 10)).foregroundColor(chatTextLow.opacity(0.7))
                }
                Spacer()
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(chatPanel))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(statusColor(t.status).opacity(0.3), lineWidth: 0.75))
        .contentShape(Rectangle())
        .onTapGesture { store.selection = .ticket(t.id) }
        .contextMenu {
            Menu("Assign owner") {
                ForEach(knownAgents.filter { $0 != "sai" }, id: \.self) { a in
                    Button(a) { store.assignTicket(t.id, owner: a) }
                }
                Button("Unassign") { store.assignTicket(t.id, owner: nil) }
            }
            Menu("Status") {
                ForEach(["new","in_progress","blocked","review","done"], id: \.self) { s in
                    Button(s) { store.updateTicketStatus(t.id, status: s) }
                }
            }
            Divider()
            Button("Open ticket") { store.selection = .ticket(t.id) }
        }
    }

    /// Distinct color per ticket type for the Kanban pill.
    private func typeColor(_ category: String) -> Color {
        switch category.lowercased() {
        case "epic":   return Color(red: 0.55, green: 0.35, blue: 0.85)
        case "story":  return Color(red: 0.30, green: 0.60, blue: 0.85)
        case "bug":    return Color(red: 0.90, green: 0.35, blue: 0.35)
        case "task":   return Color(red: 0.40, green: 0.70, blue: 0.45)
        case "review": return Color(red: 0.85, green: 0.55, blue: 0.20)
        case "docs":   return Color(red: 0.65, green: 0.50, blue: 0.85)
        default:       return chatTextLow
        }
    }

    /// Sync current chat-tickets to local beads CLI (bd create / update).
    /// Best-effort: skip if `bd` CLI not installed.
    private func syncBeads() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Detect bd
            let probe = Process()
            probe.launchPath = "/bin/bash"
            probe.arguments = ["-c", "command -v bd"]
            let pipe = Pipe()
            probe.standardOutput = pipe
            probe.standardError = pipe
            try? probe.run()
            probe.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if !out.contains("/bd") {
                DispatchQueue.main.async {
                    self.bdSyncResult = "bd not installed — run `brew install beads`"
                }
                return
            }
            // Pull-only sync first (read remote). Per-ticket bd create/update
            // requires a deeper schema map — keep this as a one-way push of
            // chat-ticket titles + status to bd via `bd create -t '<title>'`.
            // Skip if title already exists in bd.
            let tickets = self.store.tickets
            var pushed = 0
            // Priority words → bd's 0-4 scheme (P0 urgent ... P4 low)
            func bdPriority(_ p: String) -> String {
                switch p.lowercased() {
                case "urgent", "p0": return "P0"
                case "high", "p1":   return "P1"
                case "p2", "":       return "P2"
                case "normal":       return "P2"
                case "p3":           return "P3"
                case "low", "p4":    return "P4"
                default:             return "P2"
                }
            }
            for t in tickets {
                let title = t.title.replacingOccurrences(of: "'", with: "''")
                let prio = bdPriority(t.priority)
                // bd create [title] — title POSITIONAL. BEADS_DIR env points at the workspace.
                let cmd = "BEADS_DIR=$HOME/.beads bd list --json 2>/dev/null | grep -q '\(title)' || BEADS_DIR=$HOME/.beads bd create '\(title)' -p \(prio) --external-ref 'chat-ticket:\(t.id)' >/dev/null 2>&1"
                let p = Process()
                p.launchPath = "/bin/bash"
                p.arguments = ["-c", cmd]
                try? p.run()
                p.waitUntilExit()
                if p.terminationStatus == 0 { pushed += 1 }
            }
            // Final bd sync (git push)
            let sync = Process()
            sync.launchPath = "/bin/bash"
            sync.arguments = ["-c", "BEADS_DIR=$HOME/.beads bd sync 2>&1"]
            try? sync.run()
            sync.waitUntilExit()
            DispatchQueue.main.async {
                self.bdSyncResult = "synced \(pushed)/\(tickets.count) to bd"
            }
        }
    }

    private var messageFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                let groups = groupMessages(store.messages)
                LazyVStack(alignment: .leading, spacing: 10) {
                    if groups.isEmpty {
                        VStack {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 24))
                                .foregroundColor(chatTextLow.opacity(0.5))
                            Text("No messages yet").font(.system(size: 11)).foregroundColor(chatTextLow)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    ForEach(groups) { grp in
                        messageGroupView(grp).id(grp.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: store.messages.last?.id ?? 0) { _, newId in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(newId, anchor: .bottom)
                }
            }
            .onChange(of: store.messages.count) { _, _ in
                // Fires after load() finishes loading messages for a new selection.
                // Defer scroll to next runloop tick so the LazyVStack has rendered.
                if let last = store.messages.last?.id {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .onChange(of: store.selection) { _, _ in
                // Immediate scroll attempt (may run before messages reload)
                if let last = store.messages.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private func messageGroupView(_ grp: MessageGroup) -> some View {
        let isMe = grp.from == store.me
        return HStack(alignment: .top, spacing: 10) {
            if isMe { Spacer(minLength: 40) }
            if !isMe { agentBadge(grp.from, size: 28) }
            VStack(alignment: isMe ? .trailing : .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if isMe {
                        Text(prettyTime(grp.messages.first?.createdAt ?? ""))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(chatTextLow)
                    }
                    VStack(alignment: isMe ? .trailing : .leading, spacing: 0) {
                        Text(grp.from)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(agentColor(grp.from))
                        let tag = modelTag(for: grp.from)
                        if !tag.isEmpty {
                            Text(tag)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.secondary)
                                .opacity(0.7)
                        }
                    }
                    if !isMe {
                        Text(prettyTime(grp.messages.first?.createdAt ?? ""))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(chatTextLow)
                    }
                }
                ForEach(grp.messages) { msg in
                    messageBubble(msg, isMe: isMe)
                }
            }
            if isMe { agentBadge(grp.from, size: 28) }
            if !isMe { Spacer(minLength: 40) }
        }
    }

    /// Read-receipt state for one message based on store.readBy.
    /// - sent (single grey check): msg exists, no receipts from others
    /// - delivered (double grey): at least one other agent has a receipt
    /// - read by all (double blue): all expected recipients have receipts
    private func receiptState(for msg: ChatMessage) -> (icon: String, color: Color)? {
        guard msg.from == store.me else { return nil }
        let readers = store.readBy[msg.id] ?? []
        let others = readers.subtracting([store.me])
        // Determine expected recipients
        let expected: Set<String>
        if let rid = msg.roomId, let room = store.rooms.first(where: { $0.id == rid }) {
            expected = Set(room.members).subtracting([store.me])
        } else {
            expected = [msg.to]
        }
        if expected.isEmpty {
            return ("checkmark", chatTextLow)  // single grey
        }
        if others.isSuperset(of: expected) {
            return ("checkmark.circle.fill", Color(red: 0.30, green: 0.65, blue: 1.0))  // double blue
        }
        if !others.isEmpty {
            return ("checkmark.circle", chatTextLow)  // double grey
        }
        return ("checkmark", chatTextLow)  // single grey
    }

    private func messageBubble(_ msg: ChatMessage, isMe: Bool = false) -> some View {
        VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
            HStack(spacing: 4) {
                renderContent(msg.content)
                    .font(.system(size: 12))
                    .foregroundColor(chatTextHi)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isMe
                                  ? chatAccent.opacity(0.20)
                                  : agentColor(msg.from).opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isMe
                                    ? chatAccent.opacity(0.35)
                                    : agentColor(msg.from).opacity(0.18),
                                    lineWidth: 0.5)
                    )
                    .help(prettyTime(msg.createdAt))
                    .contextMenu {
                        Button("Copy") {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(msg.content, forType: .string)
                        }
                        Divider()
                        Button("Delete message", role: .destructive) {
                            confirmAndDeleteMessage(msg)
                        }
                    }
                if let receipt = receiptState(for: msg) {
                    Image(systemName: receipt.icon)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(receipt.color)
                        .help("Read receipt")
                }
            }
        }
    }

    @ViewBuilder
    private func renderContent(_ s: String) -> some View {
        // Render @mentions as colored chips by chunking on whitespace
        let parts = s.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        FlowText(parts: parts)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    pickAndAttachFile()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 14))
                        .foregroundColor(chatTextMid)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 6).fill(chatPanel))
                }
                .buttonStyle(.plain)
                .help("Attach file (path inserted into message)")

                ZStack(alignment: .topLeading) {
                    TextField("Type a message…  use @ to mention", text: $composeText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .font(.system(size: 12))
                        .foregroundColor(chatTextHi)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(chatPanel)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.06), lineWidth: 0.5))
                        .onChange(of: composeText) { _, newVal in
                            updateMentionState(newVal)
                        }
                        .onSubmit { sendMessage() }
                }
                .popover(isPresented: $showMentionPopover, arrowEdge: .top) {
                    mentionPopover
                }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(colors: [chatAccent, chatPrimary],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                }
                .buttonStyle(.plain)
                .disabled(composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.selection == .none)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send (⌘↩)")
            }
            .padding(12)
            .background(chatPanel.opacity(0.4))
        }
    }

    private var mentionPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(matchingAgents(prefix: mentionPrefix), id: \.self) { agent in
                Button {
                    insertMention(agent)
                } label: {
                    HStack(spacing: 6) {
                        agentBadge(agent, size: 16)
                        Text(agent).font(.system(size: 12)).foregroundColor(chatTextHi)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if matchingAgents(prefix: mentionPrefix).isEmpty {
                Text("no matches").font(.system(size: 10))
                    .foregroundColor(chatTextLow)
                    .padding(8)
            }
        }
        .frame(minWidth: 120)
        .background(chatPanel)
    }

    private func matchingAgents(prefix: String) -> [String] {
        let lower = prefix.lowercased()
        let pool = ["all"] + knownAgents   // "@all" first = broadcast to room
        if lower.isEmpty { return pool }
        return pool.filter { $0.hasPrefix(lower) }
    }

    private func pickAndAttachFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            let separator = composeText.isEmpty ? "" : "\n"
            composeText += "\(separator)📎 \(url.path)"
        }
    }

    private func updateMentionState(_ text: String) {
        // Detect trailing "@<word>" pattern
        if let range = text.range(of: "@[A-Za-z0-9_]*$", options: .regularExpression) {
            mentionPrefix = String(text[range]).dropFirst().lowercased()
            showMentionPopover = true
        } else {
            showMentionPopover = false
            mentionPrefix = ""
        }
    }

    private func insertMention(_ agent: String) {
        if let range = composeText.range(of: "@[A-Za-z0-9_]*$", options: .regularExpression) {
            composeText.replaceSubrange(range, with: "@\(agent) ")
        } else {
            composeText += "@\(agent) "
        }
        showMentionPopover = false
        mentionPrefix = ""
    }

    // MARK: - Right sidebar

    private var rightSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch store.selection {
                case .none:
                    Text("Select a conversation").font(.system(size: 11)).foregroundColor(chatTextLow)
                case .dm(let a, let b):
                    let other = (a == store.me) ? b : a
                    rightSection(title: "Direct Message") {
                        HStack(spacing: 8) {
                            agentBadge(other, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(other).font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(chatTextHi)
                                HStack(spacing: 4) {
                                    Circle().fill(store.onlineAgents.contains(other) ? .green : chatTextLow.opacity(0.4))
                                        .frame(width: 5, height: 5)
                                    Text(store.onlineAgents.contains(other) ? "online" : "idle")
                                        .font(.system(size: 10)).foregroundColor(chatTextMid)
                                }
                            }
                        }
                    }
                case .room(let rid):
                    if let room = store.rooms.first(where: { $0.id == rid }) {
                        rightSection(title: "Members (\(room.members.count))") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(room.members, id: \.self) { m in
                                    HStack(spacing: 6) {
                                        agentBadge(m, size: 18)
                                        Text(m).font(.system(size: 11)).foregroundColor(chatTextHi)
                                        Spacer()
                                        Circle().fill(store.onlineAgents.contains(m) ? .green : chatTextLow.opacity(0.3))
                                            .frame(width: 5, height: 5)
                                        // Remove button — visible on hover, not for the current user themselves
                                        if m != store.me {
                                            Button {
                                                _ = store.removeMemberFromRoom(rid, agent: m)
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(chatTextLow.opacity(0.6))
                                            }
                                            .buttonStyle(.plain)
                                            .help("Remove \(m) from room")
                                        }
                                    }
                                }
                                // Add-member row: dropdown of non-member known agents
                                let candidates = knownAgents.filter { !room.members.contains($0) }
                                if !candidates.isEmpty {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus.circle")
                                            .font(.system(size: 11))
                                            .foregroundColor(chatAccent)
                                        Menu {
                                            ForEach(candidates, id: \.self) { a in
                                                Button(a) {
                                                    _ = store.addMemberToRoom(rid, agent: a)
                                                }
                                            }
                                        } label: {
                                            Text("Add member")
                                                .font(.system(size: 11))
                                                .foregroundColor(chatAccent)
                                        }
                                        .buttonStyle(.plain)
                                        .menuStyle(.borderlessButton)
                                        Spacer()
                                    }
                                    .padding(.top, 4)
                                }
                            }
                        }
                        if !room.description.isEmpty {
                            rightSection(title: "Description") {
                                Text(room.description).font(.system(size: 11))
                                    .foregroundColor(chatTextMid)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if let tid = room.ticketId, let t = store.tickets.first(where: { $0.id == tid }) {
                            rightSection(title: "Linked Ticket") {
                                Button {
                                    store.selection = .ticket(t.id)
                                } label: {
                                    HStack(spacing: 6) {
                                        Circle().fill(statusColor(t.status)).frame(width: 7, height: 7)
                                        Text(t.id).font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(chatTextLow)
                                        Text(t.title).font(.system(size: 11)).foregroundColor(chatTextHi)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                case .ticket(let tid):
                    if let t = store.tickets.first(where: { $0.id == tid }) {
                        rightSection(title: t.id) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(t.title).font(.system(size: 12, weight: .semibold)).foregroundColor(chatTextHi)
                                HStack(spacing: 6) {
                                    statusPill(t.status); priorityPill(t.priority)
                                }
                                if !t.description.isEmpty {
                                    Text(t.description).font(.system(size: 11))
                                        .foregroundColor(chatTextMid)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                HStack(spacing: 4) {
                                    Text("category:").font(.system(size: 10)).foregroundColor(chatTextLow)
                                    Text(t.category).font(.system(size: 10)).foregroundColor(chatTextMid)
                                }
                                HStack(spacing: 4) {
                                    Text("owner:").font(.system(size: 10)).foregroundColor(chatTextLow)
                                    Text(t.ownerAgent ?? "unassigned").font(.system(size: 10)).foregroundColor(chatTextMid)
                                }
                                HStack(spacing: 4) {
                                    Text("created:").font(.system(size: 10)).foregroundColor(chatTextLow)
                                    Text(t.createdAt.prefix(16).description).font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(chatTextMid)
                                }
                                if let due = t.dueAt, !due.isEmpty {
                                    HStack(spacing: 4) {
                                        Text("due:").font(.system(size: 10)).foregroundColor(chatTextLow)
                                        Text(due.prefix(16).description).font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(chatTextMid)
                                    }
                                }
                            }
                        }
                        // Cost section
                        if let costUsd = t.costUsd, costUsd > 0 || (t.costCeilingUsd ?? 0) > 0 {
                            rightSection(title: "Cost") {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Text(String(format: "$%.2f", t.costUsd ?? 0))
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(chatTextHi)
                                        if let ceiling = t.costCeilingUsd, ceiling > 0 {
                                            Text("/ $\(String(format: "%.2f", ceiling))")
                                                .font(.system(size: 10))
                                                .foregroundColor(chatTextLow)
                                        }
                                    }
                                    if let ceiling = t.costCeilingUsd, ceiling > 0, let cost = t.costUsd {
                                        let pct = (cost / ceiling) * 100
                                        let barColor: Color = pct > 100 ? .red : (pct > 80 ? .orange : chatAccent)
                                        ProgressView(value: min(pct / 100, 1.0))
                                            .tint(barColor)
                                            .frame(height: 4)
                                    }
                                }
                            }
                        }
                        
                        // GitHub PR section
                        if let prUrl = t.prUrl, !prUrl.isEmpty {
                            rightSection(title: "GitHub") {
                                VStack(alignment: .leading, spacing: 6) {
                                    if let branch = t.branch, !branch.isEmpty {
                                        HStack(spacing: 4) {
                                            Text("branch:").font(.system(size: 10)).foregroundColor(chatTextLow)
                                            Text(branch).font(.system(size: 10, design: .monospaced)).foregroundColor(chatTextMid)
                                        }
                                    }
                                    Link(destination: URL(string: prUrl) ?? URL(fileURLWithPath: "/")) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "link.circle")
                                                .font(.system(size: 10))
                                            Text(prUrl.replacingOccurrences(of: "https://", with: ""))
                                                .font(.system(size: 10))
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            Spacer()
                                        }
                                        .foregroundColor(chatAccent)
                                    }
                                    if let prState = t.prState, !prState.isEmpty {
                                        HStack(spacing: 4) {
                                            let stateColor: Color = prState == "MERGED" ? .purple : (prState == "OPEN" ? .green : .gray)
                                            Circle().fill(stateColor).frame(width: 6, height: 6)
                                            Text(prState.uppercased())
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundColor(stateColor)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Artifact section
                        if let artifact = t.artifact, !artifact.isEmpty {
                            rightSection(title: "Artifact") {
                                DisclosureGroup("View JSON") {
                                    ScrollView(.horizontal) {
                                        Text(artifact)
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundColor(chatTextMid)
                                            .padding(6)
                                            .background(chatPanel)
                                            .cornerRadius(4)
                                    }
                                }
                                .font(.system(size: 10))
                            }
                        }
                        
                        // Closed timestamp
                        if let closedAt = t.closedAt, !closedAt.isEmpty {
                            rightSection(title: "Closed") {
                                Text("Closed: \(closedAt.prefix(19))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(chatTextLow)
                            }
                        }

                        rightSection(title: "Actions") {
                            VStack(spacing: 4) {
                                // Done tickets get ONLY the Reopen button (no Claim, no Status change, no Link).
                                if t.status == "done" {
                                    Button {
                                        store.updateTicketStatus(t.id, status: "in_progress")
                                    } label: {
                                        HStack { Image(systemName: "arrow.uturn.backward.circle"); Text("Reopen"); Spacer() }
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8).padding(.vertical, 5)
                                            .background(RoundedRectangle(cornerRadius: 5).fill(chatAccent))
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    // Live actions (only when ticket is still open)
                                    Button {
                                        store.claimTicket(t.id)
                                    } label: {
                                        HStack { Image(systemName: "hand.raised"); Text("Claim"); Spacer() }
                                            .font(.system(size: 11))
                                            .foregroundColor(chatTextHi)
                                            .padding(.horizontal, 8).padding(.vertical, 5)
                                            .background(RoundedRectangle(cornerRadius: 5).fill(chatPanel))
                                    }
                                    .buttonStyle(.plain)
                                    Menu {
                                        ForEach(["new", "in_progress", "blocked", "review", "done"], id: \.self) { s in
                                            Button(s) { store.updateTicketStatus(t.id, status: s) }
                                        }
                                    } label: {
                                        HStack { Image(systemName: "arrow.right.circle"); Text("Change Status"); Spacer() }
                                            .font(.system(size: 11))
                                            .foregroundColor(chatTextHi)
                                            .padding(.horizontal, 8).padding(.vertical, 5)
                                            .background(RoundedRectangle(cornerRadius: 5).fill(chatPanel))
                                    }
                                    .menuStyle(.borderlessButton)
                                    Menu {
                                        ForEach(knownAgents.filter { $0 != "sai" }, id: \.self) { a in
                                            Button(a) { store.assignTicket(t.id, owner: a) }
                                        }
                                        Button("Unassign") { store.assignTicket(t.id, owner: nil) }
                                    } label: {
                                        HStack { Image(systemName: "person.crop.circle"); Text("Assign"); Spacer() }
                                            .font(.system(size: 11))
                                            .foregroundColor(chatTextHi)
                                            .padding(.horizontal, 8).padding(.vertical, 5)
                                            .background(RoundedRectangle(cornerRadius: 5).fill(chatPanel))
                                    }
                                    .menuStyle(.borderlessButton)
                                    Button {
                                        let id = store.createRoom(name: "room for \(t.id)", members: knownAgents, description: "Linked to \(t.id)", ticketId: t.id)
                                        if let id = id { store.selection = .room(id) }
                                    } label: {
                                        HStack { Image(systemName: "person.3"); Text("Link Room"); Spacer() }
                                            .font(.system(size: 11))
                                            .foregroundColor(chatTextHi)
                                            .padding(.horizontal, 8).padding(.vertical, 5)
                                            .background(RoundedRectangle(cornerRadius: 5).fill(chatPanel))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                case .agent(let agentName):
                    if let worker = store.workers.first(where: { $0.name == agentName }) {
                        rightSection(title: worker.displayName.uppercased()) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    agentBadge(worker.name, size: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(worker.displayName).font(.system(size: 12, weight: .semibold)).foregroundColor(chatTextHi)
                                        if let provider = worker.provider {
                                            Text(provider).font(.system(size: 10, design: .monospaced)).foregroundColor(chatTextLow)
                                        }
                                    }
                                }
                                Divider().opacity(0.3)
                                if let modelId = worker.modelId {
                                    HStack(spacing: 4) {
                                        Text("model:").font(.system(size: 10)).foregroundColor(chatTextLow)
                                        Text(modelId).font(.system(size: 10, design: .monospaced)).foregroundColor(chatTextMid)
                                    }
                                }
                                if let role = worker.roleLane, !role.isEmpty {
                                    HStack(spacing: 4) {
                                        Text("lane:").font(.system(size: 10)).foregroundColor(chatTextLow)
                                        Text(role).font(.system(size: 10, design: .monospaced)).foregroundColor(chatTextMid)
                                    }
                                }
                            }
                        }
                    }
                case .kanban:
                    rightSection(title: "Board summary") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(["new","in_progress","blocked","review","done"], id: \.self) { s in
                                let n = store.tickets.filter { $0.status == s }.count
                                HStack {
                                    Circle().fill(statusColor(s)).frame(width: 7, height: 7)
                                    Text(s).font(.system(size: 11)).foregroundColor(chatTextMid)
                                    Spacer()
                                    Text("\(n)").font(.system(size: 11, design: .monospaced)).foregroundColor(chatTextHi)
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
            }
            .padding(12)
        }
        .frame(width: 200)
        .background(chatSidebar.opacity(0.7))
    }

    private func rightSection<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(chatTextMid)
                .tracking(0.5)
            content()
        }
    }

    // MARK: - Pills / badges

    private func statusPill(_ s: String) -> some View {
        Text(s.replacingOccurrences(of: "_", with: " "))
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(statusColor(s)))
    }

    private func priorityPill(_ p: String) -> some View {
        Text(p.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(priorityColor(p)))
    }

    private func agentBadge(_ name: String, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(agentColor(name)).frame(width: size, height: size)
            Text(agentInitial(name))
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundColor(.white)
        }
        .help(name)
    }

    private func identityBadge(_ name: String) -> some View {
        HStack(spacing: 4) {
            agentBadge(name, size: 16)
            Text(name).font(.system(size: 10, weight: .medium)).foregroundColor(chatTextMid)
        }
    }

    // MARK: - Send

    private func sendMessage() {
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Extract mentions
        var mentions: [String] = []
        let re = try? NSRegularExpression(pattern: "@([A-Za-z0-9_]+)")
        if let re = re {
            let ns = text as NSString
            re.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m = m, m.numberOfRanges >= 2 else { return }
                mentions.append(ns.substring(with: m.range(at: 1)).lowercased())
            }
        }
        if store.sendMessage(content: text, mentions: mentions) {
            composeText = ""
            showMentionPopover = false
        }
    }

    private func confirmAndDeleteRoom(_ room: ChatRoom) {
        let alert = NSAlert()
        alert.messageText = "Delete room \"\(room.name)\"?"
        alert.informativeText = "This permanently removes the room and all messages inside it (\(room.id)). This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.deleteRoom(room.id)
        }
    }

    private func confirmAndDeleteMessage(_ msg: ChatMessage) {
        let alert = NSAlert()
        alert.messageText = "Delete this message?"
        alert.informativeText = "From \(msg.from) at \(prettyTime(msg.createdAt)). This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            store.deleteMessage(msg.id)
        }
    }

    private func prettyTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let out = DateFormatter(); out.dateFormat = "HH:mm:ss"; return out.string(from: d)
        }
        let parts = iso.split(separator: " ")
        if parts.count == 2 { return String(parts[1]).prefix(8).description }
        return String(iso.suffix(8))
    }
}

// MARK: - Mascot header (gentle wave loop, falls back to bubble icon if PNG missing)

fileprivate struct MascotHeaderView: View {
    @State private var wave: Double = -8
    private let mascot: NSImage? = loadMascotImage()

    var body: some View {
        Group {
            if let img = mascot {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .rotationEffect(.degrees(wave))
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                            wave = 8
                        }
                    }
            } else {
                ZStack {
                    Circle().fill(LinearGradient(colors: [chatAccent, chatPrimary],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 28, height: 28)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
        .help("Erpa")
    }
}

// MARK: - FlowText (renders @mentions as colored chips inline)

fileprivate struct FlowText: View {
    let parts: [String]

    var body: some View {
        // simple HStack-based; lines wrap via let SwiftUI handle via VStack-of-HStacks
        // Use Text concatenation for proper wrapping.
        let combined = parts.enumerated().reduce(Text("")) { acc, pair in
            let (i, p) = pair
            let prefix = i == 0 ? "" : " "
            if p.hasPrefix("@") && p.count > 1 {
                let agent = String(p.dropFirst()).trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                if knownAgents.contains(agent.lowercased()) {
                    return acc + Text(prefix) + Text(p)
                        .foregroundColor(agentColor(agent))
                        .fontWeight(.semibold)
                }
            }
            return acc + Text(prefix + p)
        }
        combined
    }
}

// MARK: - New conversation sheet

fileprivate struct NewConversationSheet: View {
    static func sessionStamp() -> String {
        let f = DateFormatter(); f.dateFormat = "MMdd-HHmm"; return f.string(from: Date())
    }

    @ObservedObject var store: ChatStore
    @Binding var isPresented: Bool

    enum ConvType: String, CaseIterable, Identifiable {
        case dm = "DM"
        case room = "Room"
        case ticket = "Ticket"
        var id: String { rawValue }
    }

    @State private var type: ConvType = .room
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var selectedMembers: Set<String> = []
    @State private var priority: String = "p2"
    @State private var category: String = "general"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Conversation")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(chatTextHi)

            Picker("Type", selection: $type) {
                ForEach(ConvType.allCases) { t in Text(t.rawValue).tag(t) }
            }
            .pickerStyle(.segmented)

            if type == .dm {
                Text("Pick agent to DM").font(.system(size: 11)).foregroundColor(chatTextMid)
                ForEach(knownAgents.filter { $0 != store.me }, id: \.self) { a in
                    Button {
                        store.createDM(with: a)
                        isPresented = false
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(agentColor(a)).frame(width: 18, height: 18)
                                .overlay(Text(String(a.prefix(1)).uppercased())
                                    .font(.system(size: 9, weight: .bold)).foregroundColor(.white))
                            Text(a).font(.system(size: 12)).foregroundColor(chatTextHi)
                            Spacer()
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 5).fill(chatPanel))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(type == .room ? "Room name" : "Ticket title")
                            .font(.system(size: 11)).foregroundColor(chatTextMid)
                        Spacer()
                        if type == .room {
                            Button("auto-name") {
                                title = "sherpa-island-\(Self.sessionStamp())"
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(chatAccent)
                        }
                    }
                    TextField(type == .room
                              ? "e.g. sherpa-island-\(Self.sessionStamp()) (or click auto-name)"
                              : "Ticket title (required)", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                if type == .ticket {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description").font(.system(size: 11)).foregroundColor(chatTextMid)
                        TextField("", text: $description, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Priority").font(.system(size: 11)).foregroundColor(chatTextMid)
                            Picker("", selection: $priority) {
                                ForEach(["p0", "p1", "p2", "p3"], id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 100)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Category").font(.system(size: 11)).foregroundColor(chatTextMid)
                            TextField("", text: $category).textFieldStyle(.roundedBorder).frame(width: 140)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(type == .room ? "Members" : "Owner (optional)")
                        .font(.system(size: 11)).foregroundColor(chatTextMid)
                    HStack(spacing: 6) {
                        ForEach(knownAgents, id: \.self) { a in
                            Button {
                                if type == .ticket {
                                    selectedMembers = [a]   // owner = single
                                } else {
                                    if selectedMembers.contains(a) {
                                        selectedMembers.remove(a)
                                    } else {
                                        selectedMembers.insert(a)
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Circle().fill(agentColor(a)).frame(width: 14, height: 14)
                                    Text(a).font(.system(size: 11))
                                        .foregroundColor(chatTextHi)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(selectedMembers.contains(a) ? chatAccent.opacity(0.3) : chatPanel)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(selectedMembers.contains(a) ? chatAccent : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 5).fill(chatPanel))
                    .foregroundColor(chatTextHi)

                if type != .dm {
                    Button("Create") { create() }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(LinearGradient(colors: [chatAccent, chatPrimary],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .foregroundColor(.white)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(chatBg)
    }

    private func create() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        switch type {
        case .dm: break
        case .room:
            var members = Array(selectedMembers)
            if !members.contains(store.me) { members.append(store.me) }
            if let id = store.createRoom(name: t, members: members, description: "", ticketId: nil) {
                store.selection = .room(id)
                isPresented = false
            }
        case .ticket:
            let owner = selectedMembers.first
            if let id = store.createTicket(title: t, description: description, owner: owner, priority: priority, category: category) {
                store.selection = .ticket(id)
                isPresented = false
            }
        }
    }
}

// MARK: - Window controller (preserves singleton + .show() API)

@MainActor
final class AgentChatPopupWindowController: NSWindowController {
    static let shared = AgentChatPopupWindowController()

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        win.title = "Sherpa Chat"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        win.contentView = NSHostingView(rootView: AgentChatPopupView())
        win.minSize = NSSize(width: 720, height: 540)
        super.init(window: win)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        guard let win = window else { return }
        if !win.isVisible, let screen = NSScreen.main {
            let f = screen.visibleFrame
            let w: CGFloat = 920, h: CGFloat = 680
            win.setFrame(NSRect(x: f.midX - w/2, y: f.midY - h/2, width: w, height: h), display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}

/* DISABLED-PREVIEW #Preview { AgentChatPopupView() } */
