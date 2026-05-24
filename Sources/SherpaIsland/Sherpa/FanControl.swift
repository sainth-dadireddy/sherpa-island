import SwiftUI
import Foundation
import AppKit

enum FanMode: String, CaseIterable {
    case auto, quiet, cool, custom
    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .quiet: "Quiet"
        case .cool: "Cool"
        case .custom: "Custom"
        }
    }
}

@MainActor
final class FanController: ObservableObject {
    @Published var leftFanRPM: Int = 0
    @Published var rightFanRPM: Int = 0
    @Published var mode: FanMode = .auto
    @Published var hasController: Bool = false

    private var pollTimer: Timer?
    private let bundleID = "com.crystalidea.macsfancontrol"

    init() {
        detectController()
        startPolling()
    }

    deinit {
        Task { @MainActor [weak self] in
            self?.pollTimer?.invalidate()
        }
    }

    private func detectController() {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        hasController = (url != nil)
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.readFans()
            }
        }
    }

    private func readFans() {
        // v0.1: stub values. v0.2 will read via IOKit SMC F0Ac/F1Ac keys.
        // For now derive a pseudo-value to show widget is alive.
        leftFanRPM = 2140
        rightFanRPM = 2090
    }

    func setMode(_ newMode: FanMode) {
        mode = newMode
        guard hasController else {
            NSLog("[Sherpa Island] FanController: Macs Fan Control not installed — mode ignored")
            return
        }
        let scriptText: String
        switch newMode {
        case .auto:   scriptText = "tell application \"Macs Fan Control\" to set fan mode to \"Auto\""
        case .quiet:  scriptText = "tell application \"Macs Fan Control\" to set fan mode to \"Custom\""
        case .cool:   scriptText = "tell application \"Macs Fan Control\" to set fan mode to \"Custom\""
        case .custom: scriptText = "tell application \"Macs Fan Control\" to set fan mode to \"Custom\""
        }
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptText) {
            script.executeAndReturnError(&error)
        }
    }
}

struct FanControlView: View {
    @StateObject private var controller = FanController()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "fanblades.fill")
                    .foregroundStyle(.secondary)
                Text("Fans")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !controller.hasController {
                    Text("read-only")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            HStack {
                Text("L · \(controller.leftFanRPM) RPM")
                    .font(.system(size: 11).monospacedDigit())
                Spacer()
                Text("R · \(controller.rightFanRPM) RPM")
                    .font(.system(size: 11).monospacedDigit())
            }
            .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(FanMode.allCases, id: \.self) { m in
                    Button(action: { controller.setMode(m) }) {
                        Text(m.displayName)
                            .font(.system(size: 11, weight: controller.mode == m ? .semibold : .regular))
                            .foregroundStyle(controller.mode == m ? .primary : .secondary)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(controller.mode == m ? Color.accentColor.opacity(0.15) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!controller.hasController)
                }
            }
        }
        .padding(12)
        .background(Material.ultraThin)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .cornerRadius(10)
    }
}
