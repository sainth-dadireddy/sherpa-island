import Foundation
import IOKit
import SwiftUI
import Combine

class TemperatureMonitor: ObservableObject {
    @Published var sensors: [String: Double] = [:]
    @Published var isMonitoring: Bool = false
    /// When non-nil, real SMC polling is suspended and the published
    /// sensor dictionary holds synthesized values around this Celsius
    /// reading. Lets the debug shortcut walk the buddy/voice through
    /// every thermal band without actually heating the machine.
    @Published var debugOverrideC: Double? = nil

    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.sherpa.temperature-monitor", qos: .utility)

    private static let smcKeysAppleSilicon: [String: String] = [
        "cpu_p_cores": "TC0P",
        "cpu_e_cores": "Tc0E",
        "gpu": "Tg05",
        "ssd": "TH0A",
        "battery": "TB0T",
        "ambient": "TaLP"
    ]

    deinit {
        stopMonitoring()
    }

    func startMonitoring(interval: TimeInterval = 1.0) {
        guard !isMonitoring else { return }

        DispatchQueue.main.async {
            self.isMonitoring = true
        }

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollSensors()
        }

        pollSensors()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil

        DispatchQueue.main.async {
            self.isMonitoring = false
        }
    }

    /// Inject a synthetic primary-CPU temperature for debug. Passing
    /// nil clears the override and lets the next poll repopulate
    /// `sensors` from real SMC reads.
    func injectDebugTemp(_ celsius: Double?) {
        DispatchQueue.main.async {
            self.debugOverrideC = celsius
            guard let c = celsius else {
                self.sensors = [:]
                return
            }
            self.sensors = [
                "cpu_p_cores": c,
                "cpu_e_cores": max(20, c - 4),
                "gpu":         max(20, c - 2),
                "ssd":         max(28, c - 15),
                "battery":     max(26, c - 25),
                "ambient":     max(22, c - 30)
            ]
        }
    }

    private func pollSensors() {
        if debugOverrideC != nil { return }
        queue.async { [weak self] in
            guard let self else { return }

            var newSensors: [String: Double] = [:]

            // First try ThermalForge — gives REAL Celsius via SMC if the
            // user installed it. Free, open-source, signed helper.
            if let tf = self.readViaThermalForge(), !tf.isEmpty {
                newSensors = tf
            } else {
                // Fallback to direct SMC read (usually fails on Apple Si).
                var allSucceeded = true
                for (name, key) in Self.smcKeysAppleSilicon {
                    if let temp = self.readKey(key) {
                        newSensors[name] = temp
                    } else {
                        allSucceeded = false
                        break
                    }
                }
                if !allSucceeded {
                    if let fallback = self.readViaPowermetrics() {
                        newSensors = fallback
                    }
                }
            }

            DispatchQueue.main.async {
                self.sensors = newSensors
            }
        }
    }

    /// Shell out to `/usr/local/bin/thermalforge status` (or
    /// `/opt/homebrew/bin/thermalforge`) and parse the JSON. Returns
    /// real Celsius temperatures keyed by friendly names. Returns nil
    /// when ThermalForge isn't installed.
    private func readViaThermalForge() -> [String: Double]? {
        let candidates = [
            "/usr/local/bin/thermalforge",
            "/opt/homebrew/bin/thermalforge"
        ]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["status"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        // Bound the wait — daemon may be slow.
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let temps = obj["temperatures"] as? [String: Any]
        else { return nil }
        // Aggregate by family — average the multiple p-core / gpu sensors
        // so the UI doesn't get spammed with TP01/TP02/...
        var pCores: [Double] = []
        var eCores: [Double] = []
        var gpu: [Double] = []
        var others: [String: Double] = [:]
        for (k, v) in temps {
            guard let val = (v as? NSNumber)?.doubleValue else { continue }
            if k.hasPrefix("Tp") || k.hasPrefix("TP") {
                pCores.append(val)
            } else if k.hasPrefix("Te") || k.hasPrefix("TE") {
                eCores.append(val)
            } else if k.hasPrefix("Tg") || k.hasPrefix("TG") {
                gpu.append(val)
            } else if k == "TB0T" { others["battery"] = val }
            else if k == "TaLP" || k == "TAOL" { others["ambient"] = val }
            else if k == "TS0P" { others["ssd"] = val }
        }
        if !pCores.isEmpty { others["cpu_p_cores"] = pCores.reduce(0, +) / Double(pCores.count) }
        if !eCores.isEmpty { others["cpu_e_cores"] = eCores.reduce(0, +) / Double(eCores.count) }
        if !gpu.isEmpty    { others["gpu"]         = gpu.reduce(0, +) / Double(gpu.count) }
        return others.isEmpty ? nil : others
    }

    private func readKey(_ key: String) -> Double? {
        var result: kern_return_t = KERN_FAILURE
        var serviceObject: io_service_t = IO_OBJECT_NULL

        let matchingDict = IOServiceMatching("AppleSMC") as NSMutableDictionary
        serviceObject = IOServiceGetMatchingService(kIOMasterPortDefault, matchingDict)

        guard serviceObject != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(serviceObject) }

        var dataPort: io_connect_t = IO_OBJECT_NULL
        result = IOServiceOpen(serviceObject, mach_task_self_, 0, &dataPort)

        guard result == KERN_SUCCESS && dataPort != IO_OBJECT_NULL else { return nil }
        defer { IOServiceClose(dataPort) }

        var inputStruct = SMCParamStruct()
        var outputStruct = SMCParamStruct()

        inputStruct.key = UInt32(key.utf8.reduce(0) { UInt32($0) << 8 | UInt32($1) })
        inputStruct.command = UInt8(ascii: "r")
        inputStruct.dataLen = 0

        var inputStructSize = MemoryLayout<SMCParamStruct>.size
        var outputStructSize = MemoryLayout<SMCParamStruct>.size

        result = IOConnectCallStructMethod(
            dataPort,
            2,
            &inputStruct,
            inputStructSize,
            &outputStruct,
            &outputStructSize
        )

        guard result == KERN_SUCCESS else { return nil }

        if outputStruct.dataLen > 0 {
            let bytes = outputStruct.bytes

            if outputStruct.dataLen == 2 {
                let intVal = UInt16(bytes.0) << 8 | UInt16(bytes.1)
                return Double(intVal) / 65536.0 * 100.0
            } else if outputStruct.dataLen == 4 {
                let intVal = (UInt32(bytes.0) << 24) | (UInt32(bytes.1) << 16) |
                            (UInt32(bytes.2) << 8) | UInt32(bytes.3)
                return Double(intVal) / 65536.0 / 256.0
            } else if outputStruct.dataLen == 1 {
                return Double(bytes.0)
            }
        }

        return nil
    }

    private func readViaPowermetrics() -> [String: Double]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        process.arguments = ["-n", "1", "-i", "100", "--json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let jsonString = String(data: data, encoding: .utf8),
                  let jsonData = jsonString.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let systemSummary = json["system_summary"] as? [String: Any],
                  let thermalPressure = systemSummary["thermal_pressure"] as? String else {
                return nil
            }

            var temps: [String: Double] = [:]

            if let cpuTemp = systemSummary["cpu_long_term_utilization"] as? Double {
                temps["cpu_p_cores"] = min(cpuTemp * 100, 100.0)
            }

            switch thermalPressure.lowercased() {
            case "nominal":
                temps["ambient"] = 35.0
            case "mild":
                temps["ambient"] = 55.0
            case "moderate":
                temps["ambient"] = 70.0
            case "critical":
                temps["ambient"] = 85.0
            default:
                temps["ambient"] = 40.0
            }

            return temps.count > 0 ? temps : nil
        } catch {
            return nil
        }
    }
}

private struct SMCParamStruct {
    var key: UInt32 = 0
    var vers: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
    var padding: UInt16 = 0
    var length: UInt32 = 0
    var dataLen: UInt32 = 0
    var dataType: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0,
                                                                             0, 0, 0, 0, 0, 0, 0, 0,
                                                                             0, 0, 0, 0, 0, 0, 0, 0,
                                                                             0, 0, 0, 0, 0, 0, 0, 0)
    var command: UInt8 = 0
    var status: UInt8 = 0
}

struct TemperatureView: View {
    @StateObject var monitor = TemperatureMonitor()
    @Environment(\.colorScheme) var colorScheme

    var topThreeSensors: [(String, Double)] {
        monitor.sensors
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(topThreeSensors, id: \.0) { name, temp in
                HStack(spacing: 12) {
                    Text(sensorLabel(name))
                        .font(.system(.caption2, design: .monospaced))
                        .frame(width: 60, alignment: .leading)

                    Text(String(format: "%.1f°C", temp))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(temperatureColor(temp))

                    Spacer()

                    RoundedRectangle(cornerRadius: 2)
                        .fill(temperatureColor(temp))
                        .frame(width: 24, height: 8)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
        .onAppear {
            monitor.startMonitoring(interval: 1.0)
        }
        .onDisappear {
            monitor.stopMonitoring()
        }
    }

    private func sensorLabel(_ name: String) -> String {
        switch name {
        case "cpu_p_cores": return "CPU-P"
        case "cpu_e_cores": return "CPU-E"
        case "gpu": return "GPU"
        case "ssd": return "SSD"
        case "battery": return "BAT"
        case "ambient": return "AMB"
        default: return name.prefix(6).uppercased()
        }
    }

    private func temperatureColor(_ temp: Double) -> Color {
        switch temp {
        case ..<50: return .green
        case 50..<75: return .yellow
        default: return .red
        }
    }
}

#Preview {
    TemperatureView()
        .frame(width: 200, height: 140)
}
