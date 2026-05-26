import SwiftUI

struct CommandPalette: View {
    @State private var searchText: String = ""
    @Binding var isPresented: Bool

    private let mockResults: [CommandResult] = [
        CommandResult(
            icon: "magnifyingglass.circle.fill",
            title: "/memoryr <query>",
            subtitle: "Search memory with FTS5 + semantic",
            action: "memoryr"
        ),
        CommandResult(
            icon: "archivebox.circle.fill",
            title: "/wrap",
            subtitle: "Distill session to handoff",
            action: "wrap"
        ),
        CommandResult(
            icon: "arrow.turn.down.right.circle.fill",
            title: "/handoff",
            subtitle: "Topic-anchored context save",
            action: "handoff"
        ),
        CommandResult(
            icon: "briefcase.circle.fill",
            title: "claude-bid",
            subtitle: "Switch to bid project",
            action: "project:claude-bid"
        ),
        CommandResult(
            icon: "chart.bar.circle.fill",
            title: "claude-sales",
            subtitle: "Switch to sales project",
            action: "project:claude-sales"
        )
    ]

    private var filteredResults: [CommandResult] {
        if searchText.isEmpty {
            return mockResults
        }
        return mockResults.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.secondary)

                    TextField(
                        "Search memory, run skill, switch project...",
                        text: $searchText
                    )
                    .font(.system(size: 13, weight: .regular))
                    .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
            .padding(12)
            .background(Material.ultraThin)

            Divider()
                .frame(height: 0.5)
                .background(Color(nsColor: .separatorColor))

            if filteredResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)

                    Text("No results")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Material.ultraThin)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredResults.enumerated()), id: \.offset) { index, result in
                            CommandResultRow(result: result)

                            if index < filteredResults.count - 1 {
                                Divider()
                                    .frame(height: 0.5)
                                    .background(Color(nsColor: .separatorColor))
                            }
                        }
                    }
                }
                .background(Material.ultraThin)
            }
        }
        .frame(width: 600)
        .frame(maxHeight: 400)
        .background(Material.ultraThin)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 8)
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onKeyPress(.return) {
            if !filteredResults.isEmpty {
                executeCommand(filteredResults[0].action)
            }
            return .handled
        }
    }

    private func executeCommand(_ action: String) {
        isPresented = false
    }
}

struct CommandResult {
    let icon: String
    let title: String
    let subtitle: String
    let action: String
}

struct CommandResultRow: View {
    let result: CommandResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.primary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary)

                Text(result.subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/* DISABLED-PREVIEW #Preview {
    CommandPalette(isPresented: .constant(true))
} */
