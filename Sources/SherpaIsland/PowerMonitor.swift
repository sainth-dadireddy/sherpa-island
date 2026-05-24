import Foundation
import IOKit.ps
import Combine

/// Reads battery state + macOS Low Power Mode every refresh tick.
/// Surfaced in the thermal section so the user can see whether
/// thermal headroom is being limited by an LPM throttle.
@MainActor
final class PowerMonitor: ObservableObject {
    @Published private(set) var batteryPercent: Int = -1   // -1 = unknown
    @Published private(set) var isOnAC: Bool = true
    @Published private(set) var isLowPowerMode: Bool = false
    @Published private(set) var hasBattery: Bool = false

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func refresh() {
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else {
            hasBattery = false
            return
        }
        for src in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue()
                as? [String: Any] else { continue }
            if let cur = desc[kIOPSCurrentCapacityKey] as? Int,
               let max = desc[kIOPSMaxCapacityKey] as? Int,
               max > 0 {
                batteryPercent = Int(round(Double(cur) / Double(max) * 100))
                hasBattery = true
            }
            if let state = desc[kIOPSPowerSourceStateKey] as? String {
                isOnAC = (state == kIOPSACPowerValue)
            }
        }
    }
}
