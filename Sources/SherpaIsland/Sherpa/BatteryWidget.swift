import SwiftUI
import IOKit.ps
import Combine

// MARK: - BatteryMonitor

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published var percentage: Int = 0
    @Published var isCharging: Bool = false
    @Published var minutesUntilFull: Int?
    @Published var minutesUntilEmpty: Int?
    @Published var isOnAC: Bool = false

    private var timer: Timer?
    private var notificationSource: CFRunLoopSource?
    private let updateInterval: TimeInterval = 30.0

    init() {
        updateBatteryStatus()
        startMonitoring()
    }

    deinit {
        Task { @MainActor in
            await self.stopMonitoring()
        }
    }

    // MARK: - Monitoring Control

    func startMonitoring() {
        // Setup polling timer
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateBatteryStatus()
            }
        }

        // Setup notification for instant updates
        setupPowerSourceNotification()
    }

    func stopMonitoring() async {
        timer?.invalidate()
        timer = nil

        if let source = notificationSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            notificationSource = nil
        }
    }

    // MARK: - Battery Status Update

    private func updateBatteryStatus() {
        guard let powerSourcesInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() as? [String: Any] else {
            return
        }

        guard let powerSourcesList = IOPSCopyPowerSourcesList(powerSourcesInfo as CFDictionary)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }

        for powerSource in powerSourcesList {
            // Force-cast since IOPSCopyPowerSourcesList returns CFArray of opaque CFType (effectively CFDictionary)
            let source = unsafeBitCast(powerSource, to: CFTypeRef.self)
            // Convert CFDictionary to Swift Dictionary for safe access
            let description = IOPSGetPowerSourceDescription(powerSourcesInfo as CFDictionary, source)?.takeUnretainedValue() as? [String: Any] ?? [:]

            // Extract current capacity (percentage)
            if let capacity = description[kIOPSCurrentCapacityKey as String] as? Int {
                percentage = capacity
            }

            // Extract charging status
            if let charging = description[kIOPSIsChargingKey as String] as? Bool {
                isCharging = charging
            }

            // Extract power source state (AC vs Battery)
            if let state = description[kIOPSPowerSourceStateKey as String] as? String {
                isOnAC = (state == kIOPSACPowerValue as String)
            }

            // Extract time to full charge (in minutes)
            if let timeToFull = description[kIOPSTimeToFullChargeKey as String] as? Int {
                // -1 indicates unknown or AC power
                minutesUntilFull = (timeToFull == -1) ? nil : timeToFull
            }

            // Extract time to empty (in minutes)
            if let timeToEmpty = description[kIOPSTimeToEmptyKey as String] as? Int {
                // -1 indicates unknown or AC power
                minutesUntilEmpty = (timeToEmpty == -1) ? nil : timeToEmpty
            }
        }
    }

    // MARK: - Power Source Notification

    private func setupPowerSourceNotification() {
        // Deferred to v0.2 — C function pointer can't capture self.
        // 30s polling timer is sufficient for now.
    }
}

// MARK: - BatteryView

struct BatteryView: View {
    @ObservedObject var monitor: BatteryMonitor
    var isExpanded: Bool = false

    var batteryColor: Color {
        if monitor.percentage >= 40 {
            return .green
        } else if monitor.percentage >= 20 {
            return .yellow
        } else {
            return .red
        }
    }

    var batterySymbol: String {
        switch monitor.percentage {
        case 75...:
            return "battery.100"
        case 50..<75:
            return "battery.75"
        case 25..<50:
            return "battery.50"
        case 1..<25:
            return "battery.25"
        default:
            return "battery.0"
        }
    }

    var etaText: String {
        if monitor.isCharging, let minutesUntilFull = monitor.minutesUntilFull {
            let hours = minutesUntilFull / 60
            let minutes = minutesUntilFull % 60
            if hours > 0 {
                return "\(hours)h \(minutes)m to full"
            } else {
                return "\(minutes)m to full"
            }
        } else if !monitor.isOnAC, let minutesUntilEmpty = monitor.minutesUntilEmpty {
            let hours = minutesUntilEmpty / 60
            let minutes = minutesUntilEmpty % 60
            if hours > 0 {
                return "\(hours)h \(minutes)m remaining"
            } else {
                return "\(minutes)m remaining"
            }
        }
        return "—"
    }

    var body: some View {
        ZStack {
            // Liquid Glass Background
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                )

            if isExpanded {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ZStack(alignment: .bottomTrailing) {
                            Image(systemName: batterySymbol)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(batteryColor)

                            if monitor.isCharging {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.yellow)
                                    .offset(x: 2, y: 2)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(monitor.percentage)%")
                                .font(.system(.headline, design: .rounded))
                                .fontWeight(.semibold)

                            Text(etaText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            } else {
                HStack(spacing: 6) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: batterySymbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(batteryColor)

                        if monitor.isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.yellow)
                                .offset(x: 2, y: 2)
                        }
                    }

                    Text("\(monitor.percentage)%")
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var monitor = BatteryMonitor()

    VStack(spacing: 16) {
        Text("Compact")
            .font(.headline)

        BatteryView(monitor: monitor, isExpanded: false)
            .frame(maxWidth: .infinity, alignment: .leading)

        Divider()

        Text("Expanded")
            .font(.headline)

        BatteryView(monitor: monitor, isExpanded: true)
            .frame(maxWidth: .infinity)
    }
    .padding()
}
