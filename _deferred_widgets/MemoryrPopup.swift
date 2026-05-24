import SwiftUI
import Foundation

// MARK: - Models

struct MemoryHit: Identifiable, Codable {
    let id: String
    let category: String
    let snippet: String
    let createdAt: Date
    let project: String

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case snippet
        case createdAt = "created_at"
        case project
    }
}

// MARK: - MemoryrSearcher

@MainActor
class MemoryrSearcher: ObservableObject {
    @Published var results: [MemoryHit] = []
    @Published var isSearching = false
    @Published var errorMessage: String?

    private var searchTask: Task<Void, Never>?
    private let debounceDelay: UInt64 = 250_000_000 // 250ms in nanoseconds

    func search(query: String) async {
        searchTask?.cancel()

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }

        isSearching = true
        errorMessage = nil

        let searchQuery = query

        searchTask = Task {
            do {
                // Debounce
                try await Task.sleep(nanoseconds: debounceDelay)

                if Task.isCancelled { return }

                // Try JSON process path first
                let jsonResults = try await searchViaProcess(query: searchQuery)

                if !jsonResults.isEmpty {
                    self.results = jsonResults
                    self.isSearching = false
                    return
                }

                // Fallback to SQLite
                let sqliteResults = try searchViaSQLite(query: searchQuery)
                self.results = sqliteResults
                self.isSearching = false

            } catch {
                self.errorMessage = error.localizedDescription
                self.isSearching = false
            }
        }
    }

    private func searchViaProcess(query: String) async throws -> [MemoryHit] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            NSHomeDirectory() + "/.claude/scripts/memory_manager.py",
            "load-memories",
            "global",
            query,
            "--json"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            return []
        }

        guard let jsonString = String(data: data, encoding: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let hits = try decoder.decode([MemoryHit].self, from: jsonString.data(using: .utf8) ?? Data())
        return hits
    }

    private func searchViaSQLite(query: String) throws -> [MemoryHit] {
        let dbPath = NSHomeDirectory() + "/.claude/memory/local.db"
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: dbPath) else {
            throw NSError(domain: "MemoryrSearcher", code: 1, userInfo: [NSLocalizedDescriptionKey: "Memory database not found"])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            dbPath,
            "SELECT id, category, substr(content, 1, 200) as snippet, created_at, project FROM memories WHERE content LIKE '%\(query)%' ORDER BY created_at DESC LIMIT 10;"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return []
        }

        var results: [MemoryHit] = []
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for line in lines {
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 5 else { continue }

            let dateFormatter = ISO8601DateFormatter()
            let createdAt = dateFormatter.date(from: parts[3]) ?? Date()

            let hit = MemoryHit(
                id: parts[0].trimmingCharacters(in: .whitespaces),
                category: parts[1].trimmingCharacters(in: .whitespaces),
                snippet: parts[2].trimmingCharacters(in: .whitespaces),
                createdAt: createdAt,
                project: parts[4].trimmingCharacters(in: .whitespaces)
            )
            results.append(hit)
        }

        return results
    }
}

// MARK: - Category Styling

struct CategoryStyle {
    let color: Color
    let accentColor: Color

    static func style(for category: String) -> CategoryStyle {
        switch category.lowercased() {
        case "decision":
            return CategoryStyle(color: .blue, accentColor: .cyan)
        case "fix":
            return CategoryStyle(color: .orange, accentColor: .yellow)
        case "learning":
            return CategoryStyle(color: .purple, accentColor: .pink)
        case "architecture":
            return CategoryStyle(color: .green, accentColor: .mint)
        case "handoff":
            return CategoryStyle(color: .red, accentColor: .pink)
        case "pattern":
            return CategoryStyle(color: .indigo, accentColor: .blue)
        case "preference":
            return CategoryStyle(color: .teal, accentColor: .cyan)
        case "bug":
            return CategoryStyle(color: .red, accentColor: .orange)
        case "context":
            return CategoryStyle(color: .gray, accentColor: .white)
        default:
            return CategoryStyle(color: .gray, accentColor: .white)
        }
    }
}

// MARK: - SwiftUI Views

struct MemoryrPopupView: View {
    @StateObject private var searcher = MemoryrSearcher()
    @State private var searchText = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search memories...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .padding(12)

            Divider()

            // Results list
            ScrollView {
                if searcher.isSearching {
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching memories...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                } else if let error = searcher.errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title3)
                            .foregroundColor(.orange)
                        Text("Search Error")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                } else if searcher.results.isEmpty && !searchText.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "book.circle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("No results found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                } else if searcher.results.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("Start typing to search")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                } else {
                    VStack(spacing: 8) {
                        ForEach(searcher.results) { hit in
                            MemoryResultRow(hit: hit, onSelect: {
                                copyToClipboard(hit.id)
                                dismiss()
                            })
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 500, maxHeight: 500)
        .background(
            Material.ultraThin
                .ignoresSafeArea()
        )
        .cornerRadius(12)
        .onChange(of: searchText) { oldValue, newValue in
            Task {
                await searcher.search(query: newValue)
            }
        }
        .onKeyPress(.escape) { press in
            dismiss()
            return .handled
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct MemoryResultRow: View {
    let hit: MemoryHit
    let onSelect: () -> Void

    var body: some View {
        let style = CategoryStyle.style(for: hit.category)

        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    // Category pill
                    Text(hit.category.uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(style.color)
                        .cornerRadius(4)

                    // Project
                    Text(hit.project)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Age
                    Text(relativeDate(hit.createdAt))
                        .font(.caption2)
                        .foregroundColor(.tertiary)
                }

                // Snippet
                Text(hit.snippet)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour, .minute], from: date, to: now)

        if let days = components.day, days > 0 {
            return "\(days)d ago"
        } else if let hours = components.hour, hours > 0 {
            return "\(hours)h ago"
        } else if let minutes = components.minute, minutes > 0 {
            return "\(minutes)m ago"
        } else {
            return "now"
        }
    }
}

// MARK: - Preview

#Preview {
    MemoryrPopupView()
        .preferredColorScheme(.dark)
}
