import Foundation
import Combine
import SwiftUI
import os.log

enum NotchMode: String, Equatable {
    case claudeFocus
    case interrupt
    case general
    case meetingAlert
    case powerSaver
    case thermalAlert
    case palette
    case shelf
    case mediaOverlay
}

@MainActor
final class AutoModeSwitcher: ObservableObject {
    @Published var currentMode: NotchMode = .general
    @Published var claudeRunning: Bool = false
    @Published var audioPlaying: Bool = false

    private var lastClaudeActivity: Date?
    private var calendarEventInMin: Int?
    private var batteryPct: Int = 100
    private var batteryCharging: Bool = false
    private var cpuTempC: Double = 0.0

    private var interruptMode: Bool = false
    private var thermalAlertTriggered: Bool = false
    private var thermalAlertStartTime: Date?

    private var updateTimer: Timer?
    private var modeEvaluationTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.sherpa.NotchPilot", category: "AutoModeSwitcher")

    init() {
        startMonitoring()
    }

    deinit {
        Task { @MainActor in
            await stopMonitoring()
        }
    }

    // MARK: - Public Input Methods

    func setLastClaudeActivity(_ date: Date?) {
        self.lastClaudeActivity = date
        evaluateMode()
    }

    func setCalendarEventInMin(_ minutes: Int?) {
        self.calendarEventInMin = minutes
        evaluateMode()
    }

    func setBatteryState(pct: Int, charging: Bool) {
        self.batteryPct = pct
        self.batteryCharging = charging
        evaluateMode()
    }

    func setCPUTemperature(_ tempC: Double) {
        self.cpuTempC = tempC
        checkThermalAlert(tempC)
        evaluateMode()
    }

    func setInterruptMode(_ enabled: Bool) {
        self.interruptMode = enabled
        evaluateMode()
    }

    func setAudioPlaying(_ playing: Bool) {
        self.audioPlaying = playing
        evaluateMode()
    }

    // MARK: - Private Monitoring

    private func startMonitoring() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkClaudeProcess()
            }
        }

        // Initial check
        checkClaudeProcess()
        evaluateMode()
    }

    private func stopMonitoring() async {
        updateTimer?.invalidate()
        updateTimer = nil
        modeEvaluationTask?.cancel()
    }

    private func checkClaudeProcess() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["claude"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let isRunning = !data.isEmpty

            if isRunning != self.claudeRunning {
                self.claudeRunning = isRunning
                if isRunning {
                    self.setLastClaudeActivity(Date())
                }
            }
        } catch {
            logger.error("Failed to check Claude process: \(error.localizedDescription)")
        }
    }

    private func checkThermalAlert(_ tempC: Double) {
        let thermalThreshold: Double = 90.0

        if tempC > thermalThreshold {
            if !thermalAlertTriggered {
                thermalAlertStartTime = Date()
                thermalAlertTriggered = true
            }
        } else {
            thermalAlertTriggered = false
            thermalAlertStartTime = nil
        }
    }

    private func isThermalAlertSustained() -> Bool {
        guard thermalAlertTriggered, let startTime = thermalAlertStartTime else {
            return false
        }
        return Date().timeIntervalSince(startTime) >= 30.0
    }

    // MARK: - Mode Evaluation

    private func evaluateMode() {
        let newMode = decideModeWithAnimation()

        if newMode != currentMode {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentMode = newMode
            }
            logger.info("Mode transitioned to: \(newMode.rawValue)")
        }
    }

    private func decideModeWithAnimation() -> NotchMode {
        // Priority 1: Interrupt (highest priority, externally set)
        if interruptMode {
            return .interrupt
        }

        // Priority 2: Thermal Alert (sustained > 30s at > 90°C)
        if isThermalAlertSustained() {
            return .thermalAlert
        }

        // Priority 3: Power Saver (battery < 20% and not charging)
        if batteryPct < 20 && !batteryCharging {
            return .powerSaver
        }

        // Priority 4: Meeting Alert (event in <= 5 minutes)
        if let eventInMin = calendarEventInMin, eventInMin <= 5 && eventInMin > 0 {
            return .meetingAlert
        }

        // Priority 5: Claude Focus (Claude running and activity < 10 min ago)
        if claudeRunning, let lastActivity = lastClaudeActivity {
            let timeSinceActivity = Date().timeIntervalSince(lastActivity)
            if timeSinceActivity < 600.0 { // 10 minutes
                return .claudeFocus
            }
        }

        // Priority 6: Default
        return .general
    }

    // MARK: - Utility

    func modeDescription() -> String {
        switch currentMode {
        case .claudeFocus:
            return "Claude Focus"
        case .interrupt:
            return "Interrupt"
        case .general:
            return "General"
        case .meetingAlert:
            return "Meeting Alert"
        case .powerSaver:
            return "Power Saver"
        case .thermalAlert:
            return "Thermal Alert"
        case .palette:
            return "Palette"
        case .shelf:
            return "Shelf"
        case .mediaOverlay:
            return "Media Overlay"
        }
    }
}
