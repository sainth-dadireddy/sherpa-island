import Foundation
import SwiftUI

final class CostLedger: ObservableObject {
    @Published var total24h: Double = 0.0
    @Published var byModel: [String: Double] = [:]

    private let costFilePath = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/.sherpa-cost.json")
    private var fileMonitor: DispatchSourceFileSystemObject?

    init() {
        loadCostData()
        startFileMonitoring()
    }

    deinit {
        fileMonitor?.cancel()
    }

    private func loadCostData() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: costFilePath) else {
            DispatchQueue.main.async {
                self.total24h = 0.0
                self.byModel = [:]
            }
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: costFilePath))
            let decoder = JSONDecoder()
            let costData = try decoder.decode(CostData.self, from: data)

            DispatchQueue.main.async {
                self.total24h = costData.total24h
                self.byModel = costData.byModel
            }
        } catch {
            DispatchQueue.main.async {
                self.total24h = 0.0
                self.byModel = [:]
            }
        }
    }

    private func startFileMonitoring() {
        let fileDescriptor = open(costFilePath, O_EVTONLY)
        guard fileDescriptor != -1 else { return }

        let queue = DispatchQueue(label: "com.sherpa.cost-monitor")
        fileMonitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: queue
        )

        fileMonitor?.setEventHandler { [weak self] in
            self?.loadCostData()
        }

        fileMonitor?.setCancelHandler {
            close(fileDescriptor)
        }

        fileMonitor?.resume()
    }

    func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    private struct CostData: Codable {
        let total24h: Double
        let byModel: [String: Double]

        enum CodingKeys: String, CodingKey {
            case total24h = "24h"
            case byModel = "by_model"
        }
    }
}

struct CostLedgerView: View {
    @ObservedObject var costLedger: CostLedger

    var topThreeModels: [(String, Double)] {
        costLedger.byModel
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("24h Cost")
                        .font(.system(.caption, design: .default))
                        .foregroundColor(.secondary)

                    Text(costLedger.formatCurrency(costLedger.total24h))
                        .font(.system(.title3, design: .default))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }

                Spacer()
            }
            .padding(10)
            .background(Material.ultraThin)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )

            if !topThreeModels.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(topThreeModels, id: \.0) { model, cost in
                        HStack(alignment: .center, spacing: 8) {
                            Text(model)
                                .font(.system(.caption2, design: .monospaced))
                                .lineLimit(1)

                            Spacer()

                            Text(costLedger.formatCurrency(cost))
                                .font(.system(.caption2, design: .default))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                }
                .padding(10)
                .background(Material.ultraThin)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
            }
        }
    }
}

#Preview {
    CostLedgerView(costLedger: {
        let ledger = CostLedger()
        ledger.total24h = 24.40
        ledger.byModel = [
            "opus-4.7": 18.20,
            "qwen3-coder": 4.10,
            "nova-pro": 2.10
        ]
        return ledger
    }())
}
