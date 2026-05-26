import Foundation
import Combine
import SwiftUI

enum MCPStatus: String, Equatable {
    case connected
    case failed
    case unknown
}

struct MCPServer: Identifiable, Equatable {
    let id: String
    let name: String
    let status: MCPStatus
    let transport: String
}

@MainActor
final class MCPHealthMonitor: ObservableObject {
    @Published var servers: [MCPServer] = []

    private var timer: Timer?
    private let updateInterval: TimeInterval = 30.0
    private let timeoutInterval: TimeInterval = 3.0
    private let claudeBinaryPath = "/usr/bin/env"

    init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        stopMonitoring()
        updateMCPServers()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMCPServers()
            }
        }
    }

    nonisolated func stopMonitoring() {
        Task { @MainActor [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
        }
    }

    private func updateMCPServers() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudeBinaryPath)
        process.arguments = ["-i", "claude", "mcp", "list"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()

        var outputData: Data?
        var timedOut = false

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()

                let timer = Timer.scheduledTimer(withTimeInterval: self.timeoutInterval, repeats: false) { _ in
                    if process.isRunning {
                        process.terminate()
                        timedOut = true
                    }
                }

                process.waitUntilExit()
                timer.invalidate()

                outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            } catch {
                timedOut = true
            }
            dispatchGroup.leave()
        }

        dispatchGroup.wait()

        if timedOut {
            DispatchQueue.main.async {
                self.servers = [MCPServer(id: "error", name: "claude", status: .unknown, transport: "unknown")]
            }
            return
        }

        guard let data = outputData, let output = String(data: data, encoding: .utf8) else {
            DispatchQueue.main.async {
                self.servers = [MCPServer(id: "error", name: "claude", status: .unknown, transport: "unknown")]
            }
            return
        }

        let parsed = parseMCPOutput(output)
        DispatchQueue.main.async {
            self.servers = parsed
        }
    }

    private func parseMCPOutput(_ output: String) -> [MCPServer] {
        var servers: [MCPServer] = []
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 1 else { continue }

            let nameRaw = parts[0].trimmingCharacters(in: .whitespaces)
            let statusRaw = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""

            let status: MCPStatus
            if statusRaw.contains("✓") || statusRaw.contains("Connected") {
                status = .connected
            } else if statusRaw.contains("✗") || statusRaw.contains("Failed") {
                status = .failed
            } else {
                status = .unknown
            }

            let server = MCPServer(
                id: nameRaw,
                name: nameRaw,
                status: status,
                transport: "stdio"
            )
            servers.append(server)
        }

        return servers.isEmpty ? [MCPServer(id: "none", name: "none", status: .unknown, transport: "unknown")] : servers
    }
}

struct MCPHealthView: View {
    @StateObject private var monitor = MCPHealthMonitor()

    var body: some View {
        HStack(spacing: 8) {
            ForEach(monitor.servers) { server in
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.05)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.1))
                        )
                        .backdrop()

                    HStack(spacing: 6) {
                        statusIcon(for: server.status)
                            .font(.system(size: 12, weight: .semibold))

                        Text(truncateName(server.name))
                            .font(.system(size: 11, weight: .regular, design: .default))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .frame(height: 28)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func statusIcon(for status: MCPStatus) -> some View {
        Group {
            switch status {
            case .connected:
                Image(systemName: "circle.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "circle.fill")
                    .foregroundColor(.red)
            case .unknown:
                Image(systemName: "circle.fill")
                    .foregroundColor(.gray)
            }
        }
    }

    private func truncateName(_ name: String) -> String {
        if name.count > 8 {
            return String(name.prefix(8)) + "…"
        }
        return name
    }
}

extension View {
    func backdrop() -> some View {
        self.background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
    }
}

/* DISABLED-PREVIEW #Preview {
    MCPHealthView()
        .frame(height: 50)
        .background(Color.black)
} */
