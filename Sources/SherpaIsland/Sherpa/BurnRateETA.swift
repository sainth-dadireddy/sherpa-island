import Foundation
import SwiftUI
import Combine

@MainActor
final class BurnRateMonitor: ObservableObject {
    @Published var burnPctPerMin: Double = 0.0
    @Published var etaSeconds: Double = 0.0
    @Published var paceDeltaPct: Double = 0.0
    @Published var samples: [(Date, Double)] = []

    private let historyFilePath: String
    private var pollTimer: Timer?
    private var paceHistory: PaceHistory?
    private let queue = DispatchQueue(label: "com.sherpa.burnrate-monitor", qos: .utility)

    struct PaceHistory: Codable {
        var prev_pct5: Double
        var timestamp: Date
        var resetTs: Date?

        enum CodingKeys: String, CodingKey {
            case prev_pct5
            case timestamp
            case resetTs = "reset_ts"
        }
    }

    init() {
        let home = NSHomeDirectory()
        let sherpaDirPath = (home as NSString).appendingPathComponent(".sherpa-island")
        self.historyFilePath = (sherpaDirPath as NSString).appendingPathComponent("pace-history.json")

        loadHistory()
        startPolling()
    }

    deinit {
        Task { @MainActor [weak self] in
            self?.stopPolling()
        }
    }

    // MARK: - Public

    func startPolling(interval: TimeInterval = 10.0) {
        guard pollTimer == nil else { return }

        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollUsage()
            }
        }

        Task {
            await pollUsage()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Private

    private func loadHistory() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: historyFilePath) else {
            paceHistory = nil
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: historyFilePath))
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            paceHistory = try decoder.decode(PaceHistory.self, from: data)
        } catch {
            print("[BurnRateMonitor] failed to load history: \(error)")
            paceHistory = nil
        }
    }

    private func saveHistory(pct: Double, resetTs: Date?) {
        queue.async { [weak self] in
            guard let self else { return }

            let history = PaceHistory(
                prev_pct5: pct,
                timestamp: Date(),
                resetTs: resetTs
            )

            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(history)

                let fileManager = FileManager.default
                let sherpaDirPath = (NSHomeDirectory() as NSString).appendingPathComponent(".sherpa-island")

                if !fileManager.fileExists(atPath: sherpaDirPath) {
                    try fileManager.createDirectory(
                        atPath: sherpaDirPath,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                }

                try data.write(to: URL(fileURLWithPath: self.historyFilePath))

                DispatchQueue.main.async {
                    self.paceHistory = history
                }
            } catch {
                print("[BurnRateMonitor] failed to save history: \(error)")
            }
        }
    }

    private func pollUsage() async {
        let outcome = await UsageAPI.fetchUsage()

        switch outcome {
        case .success(let usage):
            processUsage(usage)
        case .rateLimited(let retryAfter):
            print("[BurnRateMonitor] rate limited, backing off \(retryAfter)s")
        case .failed:
            print("[BurnRateMonitor] usage fetch failed")
        }
    }

    private func processUsage(_ usage: ClaudeUsage) {
        var burnRate = 0.0
        var eta = 0.0
        var paceDelta = 0.0
        var currentPct = 0.0
        var resetTs: Date? = nil

        // Use the 7-day window as primary
        if let window = usage.sevenDay {
            currentPct = window.utilization
            resetTs = window.resetsAt

            if let prev = paceHistory {
                let now = Date()
                let prevTimestamp = prev.timestamp
                let elapsedSeconds = now.timeIntervalSince(prevTimestamp)
                let elapsedMinutes = elapsedSeconds / 60.0

                // Check if in same window (reset timestamps within 60s)
                let isSameWindow = if let currReset = resetTs, let prevReset = prev.resetTs {
                    abs(currReset.timeIntervalSince(prevReset)) < 60
                } else {
                    true // If either is nil, assume same window
                }

                if isSameWindow && elapsedMinutes > 0.1 {
                    let pctDelta = currentPct - prev.prev_pct5
                    burnRate = pctDelta / elapsedMinutes

                    if burnRate > 0 {
                        eta = (100.0 - currentPct) / burnRate * 60.0
                    }

                    // Calculate sustainable burn rate
                    if let reset = resetTs {
                        let minutesUntilReset = reset.timeIntervalSinceNow / 60.0
                        let remainingPct = 100.0 - currentPct

                        if minutesUntilReset > 0 {
                            let sustainable = remainingPct / minutesUntilReset
                            if sustainable > 0 {
                                paceDelta = ((burnRate - sustainable) / sustainable) * 100.0
                            }
                        }
                    }
                }
            }

            // Record sample
            DispatchQueue.main.async {
                self.samples.append((Date(), currentPct))
                if self.samples.count > 1000 {
                    self.samples.removeFirst()
                }
            }
        }

        DispatchQueue.main.async {
            self.burnPctPerMin = burnRate
            self.etaSeconds = eta
            self.paceDeltaPct = paceDelta
        }

        saveHistory(pct: currentPct, resetTs: resetTs)
    }
}

// MARK: - SwiftUI View

struct BurnRateView: View {
    @ObservedObject var monitor: BurnRateMonitor

    var body: some View {
        HStack(spacing: 12) {
            burnPill
            etaPill
            pacePill
        }
        .frame(height: 32)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(liquidGlassBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
    }

    private var burnPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 12))
                .foregroundColor(.cyan)

            Text("burn:\(formatBurn(monitor.burnPctPerMin))/m")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.cyan)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.cyan.opacity(0.12))
        .cornerRadius(6)
    }

    private var etaPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.fill")
                .font(.system(size: 12))
                .foregroundColor(.green)

            Text("eta:\(formatETA(monitor.etaSeconds))")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.green)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.12))
        .cornerRadius(6)
    }

    private var pacePill: some View {
        let isAboveTarget = monitor.paceDeltaPct > 0
        let arrowIcon = isAboveTarget ? "arrow.up.right" : "arrow.down.left"
        let color: Color = isAboveTarget ? .red : .orange

        return HStack(spacing: 4) {
            Image(systemName: arrowIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)

            Text("pace:\(formatPaceDelta(monitor.paceDeltaPct))%")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .cornerRadius(6)
    }

    private var liquidGlassBackground: some View {
        ZStack {
            Color.black.opacity(0.3)

            Color.white.opacity(0.05)
        }
        .background(.ultraThinMaterial)
    }

    private func formatBurn(_ value: Double) -> String {
        return String(format: "%.1f%%", value)
    }

    private func formatETA(_ seconds: Double) -> String {
        guard seconds > 0 else { return "∞" }

        if seconds > 86400 {
            let days = Int(seconds / 86400)
            return "\(days)d"
        } else if seconds > 3600 {
            let hours = Int(seconds / 3600)
            let mins = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h\(mins)m"
        } else if seconds > 60 {
            let mins = Int(seconds / 60)
            return "\(mins)m"
        } else {
            return "\(Int(seconds))s"
        }
    }

    private func formatPaceDelta(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return String(format: "%@%.0f", sign, value)
    }
}

#Preview {
    let monitor = BurnRateMonitor()
    monitor.burnPctPerMin = 0.4
    monitor.etaSeconds = 8220 // 2h 13m
    monitor.paceDeltaPct = 8.0

    return BurnRateView(monitor: monitor)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
}
