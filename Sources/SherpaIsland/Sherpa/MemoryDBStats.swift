import Foundation
import SwiftUI
import SQLite3
import Observation

final class MemoryDBMonitor: ObservableObject {
    @Published var rowCount: Int = 0
    @Published var lastSaveDate: Date? = nil
    @Published var dbSizeBytes: Int64 = 0

    private let dbPath = (("~/.claude/memory/local.db" as NSString).expandingTildeInPath)
    private var refreshTimer: Timer?
    private var fsSource: DispatchSourceFileSystemObject?

    init() {
        refreshData()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        // Timer-based refresh every 60 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.refreshData()
        }

        // File system monitoring for changes
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: dbPath) {
            let fd = open(dbPath, O_EVTONLY)
            if fd != -1 {
                fsSource = DispatchSource.makeFileSystemObjectSource(
                    fileDescriptor: fd,
                    eventMask: .write,
                    queue: .main
                )
                fsSource?.setEventHandler { [weak self] in
                    self?.refreshData()
                }
                fsSource?.setCancelHandler {
                    close(fd)
                }
                fsSource?.resume()
            }
        }
    }

    private func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        fsSource?.cancel()
        fsSource = nil
    }

    func refreshData() {
        let fileManager = FileManager.default

        // Check if DB exists
        guard fileManager.fileExists(atPath: dbPath) else {
            DispatchQueue.main.async {
                self.rowCount = 0
                self.lastSaveDate = nil
                self.dbSizeBytes = 0
            }
            return
        }

        // Get file size
        let sizeBytes: Int64
        do {
            let attrs = try fileManager.attributesOfItem(atPath: dbPath)
            sizeBytes = (attrs[FileAttributeKey.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            sizeBytes = 0
        }

        // Query SQLite
        var rowCount = 0
        var lastSaveDate: Date? = nil
        var db: OpaquePointer?

        if sqlite3_open(dbPath, &db) == SQLITE_OK, let db = db {
            defer { sqlite3_close(db) }

            let query = "SELECT COUNT(*), MAX(created_at) FROM memories"
            var stmt: OpaquePointer?

            if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt {
                defer { sqlite3_finalize(stmt) }

                if sqlite3_step(stmt) == SQLITE_ROW {
                    rowCount = Int(sqlite3_column_int64(stmt, 0))

                    if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
                        if let dateStr = String(cString: sqlite3_column_text(stmt, 1)) as String? {
                            lastSaveDate = ISO8601DateFormatter().date(from: dateStr)
                        }
                    }
                }
            }
        }

        DispatchQueue.main.async {
            self.rowCount = rowCount
            self.lastSaveDate = lastSaveDate
            self.dbSizeBytes = sizeBytes
        }
    }
}

struct MemoryDBStatsView: View {
    @ObservedObject var monitor: MemoryDBMonitor

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.system(size: 14))

            Text("\(monitor.rowCount) rows · last \(humanReadableAge(from: monitor.lastSaveDate))")
                .font(.system(size: 12, weight: .medium, design: .default))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

func humanReadableAge(from date: Date?) -> String {
    guard let date = date else {
        return "never"
    }

    let interval = Date().timeIntervalSince(date)

    if interval < 60 {
        return "now"
    } else if interval < 3600 {
        let minutes = Int(interval / 60)
        return "\(minutes)m ago"
    } else if interval < 86400 {
        let hours = Int(interval / 3600)
        return "\(hours)h ago"
    } else if interval < 604800 {
        let days = Int(interval / 86400)
        return "\(days)d ago"
    } else {
        let weeks = Int(interval / 604800)
        return "\(weeks)w ago"
    }
}

/* DISABLED-PREVIEW #Preview {
    let monitor = MemoryDBMonitor()
    MemoryDBStatsView(monitor: monitor)
} */
