import SwiftUI
import os.log

// MARK: - WidgetTab enum

enum WidgetTab: String, CaseIterable, Identifiable {
    case claude
    case system
    case media

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude:  return "Claude"
        case .system:  return "System"
        case .media:   return "Media"
        }
    }

    var icon: String {
        switch self {
        case .claude:  return "sparkles"
        case .system:  return "gearshape"
        case .media:   return "music.note"
        }
    }
}

// MARK: - NotchOrganizer

@MainActor
struct NotchOrganizer: View {
    @StateObject var autoMode: AutoModeSwitcher
    @State var selectedTab: WidgetTab = .claude

    /// Track collapsed/expanded state
    @State private var isExpanded = false

    /// Inline status indicators (COLLAPSED state)
    @StateObject private var batteryMonitor = BatteryMonitor()
    // AudioMonitor deferred — use NowPlayingMonitor placeholder

    /// Keyboard shortcut to toggle settings sheet
    @State private var showingSettings = false

    private let logger = Logger(subsystem: "com.sherpa.NotchOrganizer", category: "UI")

    var body: some View {
        ZStack {
            // COLLAPSED state: 3-4 inline status dots
            if !isExpanded {
                collapsedView
                    .onHover { hovering in
                        if hovering {
                            isExpanded = true
                        }
                    }
            }
            // EXPANDED state: tab container + content + settings
            else {
                expandedView
                    .onHover { hovering in
                        if !hovering {
                            isExpanded = false
                        }
                    }
            }

            // INTERRUPT mode overlay (full pane)
            if autoMode.currentMode == .interrupt {
                interruptModeOverlay
            }

            // MEETING_ALERT mode overlay
            if autoMode.currentMode == .meetingAlert {
                meetingAlertOverlay
            }

            // THERMAL_ALERT: red banner over current tab
            if autoMode.currentMode == .thermalAlert {
                thermalAlertBanner
            }
        }
        .sheet(isPresented: $showingSettings) {
            settingsSheet
        }
    }

    // MARK: - Collapsed View (3-4 dots)

    private var collapsedView: some View {
        HStack(spacing: 8) {
            // Claude dot (activity indicator)
            Circle()
                .fill(autoMode.claudeRunning ? Color.blue : Color.gray.opacity(0.3))
                .frame(width: 8, height: 8)
                .help("Claude \(autoMode.claudeRunning ? "active" : "idle")")

            // Audio dot
            if autoMode.audioPlaying {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .help("Audio playing")
            }

            // Battery dot (color-coded)
            Circle()
                .fill(batteryStatusColor)
                .frame(width: 8, height: 8)
                .help("Battery \(batteryMonitor.percentage)%")

            // Alert dot (if any)
            if autoMode.currentMode == .thermalAlert || autoMode.currentMode == .interrupt {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .help("Alert active")
            }
        }
        .padding(8)
        .background(Material.ultraThin)
        .cornerRadius(8)
    }

    // MARK: - Expanded View (tabs + content)

    private var expandedView: some View {
        VStack(spacing: 0) {
            // Tab selector (segmented picker)
            Picker("Tab", selection: $selectedTab) {
                ForEach(WidgetTab.allCases) { tab in
                    Label(tab.label, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)
            .background(Material.ultraThin)

            Divider()
                .frame(height: 0.5)

            // Tab content (lazy: only visible tab instantiated)
            Group {
                if selectedTab == .claude {
                    claudeTabContent
                } else if selectedTab == .system {
                    systemTabContent
                } else if selectedTab == .media {
                    mediaTabContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)

            Divider()
                .frame(height: 0.5)

            // Bottom: settings gear button
            HStack {
                Spacer()
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gear")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .padding(6)
                .help("Settings")
            }
            .background(Material.ultraThin)
        }
        .frame(width: 320, height: 320)
        .background(Material.ultraThin)
        .cornerRadius(12)
        .shadow(radius: 8)
    }

    // MARK: - Tab Content

    private var claudeTabContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Usage")
                .font(.subheadline.weight(.semibold))

            // 5h usage
            HStack {
                Text("5h window")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("72%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.blue)
            }

            // 7d usage
            HStack {
                Text("7d window")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("45%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.orange)
            }

            // Burn rate
            HStack {
                Text("Burn rate")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("2.3%/min")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.red)
            }

            Divider()

            Text("Active Sessions")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("leads-dashboard")
                        .font(.caption)
                    Spacer()
                    Text("2m")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("claude-enterprise")
                        .font(.caption)
                    Spacer()
                    Text("12m")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var systemTabContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("System Status")
                .font(.subheadline.weight(.semibold))

            HStack {
                Text("Temperature")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("62°C")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.green)
            }

            HStack {
                Text("Fans")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("3200 RPM")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Battery")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(batteryMonitor.percentage)%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(batteryStatusColor)
            }

            Divider()

            Text("Power")
                .font(.subheadline.weight(.semibold))

            HStack {
                Text("AC Power")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(batteryMonitor.isOnAC ? "Connected" : "Not connected")
                    .font(.caption)
                    .foregroundColor(batteryMonitor.isOnAC ? .green : .secondary)
            }
        }
    }

    private var mediaTabContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Now Playing")
                .font(.subheadline.weight(.semibold))

            HStack {
                Text("Nothing playing")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Text("Calendar")
                .font(.subheadline.weight(.semibold))

            HStack {
                Text("Next event")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("2:30 PM")
                    .font(.caption.monospacedDigit())
            }

            Divider()

            HStack {
                Text("Time")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(timeString)
                    .font(.caption.monospacedDigit())
            }
        }
    }

    // MARK: - Alert Overlays

    private var interruptModeOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            Text("Interrupt Request")
                .font(.headline)

            Text("A permission or action requires your attention.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Review") {
                autoMode.setInterruptMode(false)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(width: 300, height: 200)
        .background(Material.ultraThin)
        .cornerRadius(12)
        .shadow(radius: 8)
    }

    private var meetingAlertOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 32))
                .foregroundColor(.blue)

            Text("Meeting Starting")
                .font(.headline)

            Text("In 3 minutes")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Join Now") {
                // Trigger meeting join action
            }
            .buttonStyle(.bordered)

            Button("Dismiss") {
                // Close overlay
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(width: 280, height: 200)
        .background(Material.ultraThin)
        .cornerRadius(12)
        .shadow(radius: 8)
    }

    private var thermalAlertBanner: some View {
        VStack {
            HStack {
                Image(systemName: "thermometer.high.fill")
                    .foregroundColor(.white)
                Text("Thermal Alert: CPU Overheating")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(8)
            .background(Color.red)
            .cornerRadius(6)
            .padding(8)

            Spacer()
        }
    }

    // MARK: - Settings Sheet

    private var settingsSheet: some View {
        Form {
            Section("Notifications") {
                Toggle("Show Thermal Alerts", isOn: .constant(true))
                Toggle("Show Meeting Alerts", isOn: .constant(true))
            }

            Section("Display") {
                Picker("Theme", selection: .constant("auto")) {
                    Text("Auto").tag("auto")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
            }

            Section("Advanced") {
                Toggle("Log Activity", isOn: .constant(false))
            }
        }
        .frame(width: 400, height: 300)
    }

    // MARK: - Helpers

    private var batteryStatusColor: Color {
        switch batteryMonitor.percentage {
        case 0..<20:
            return .red
        case 20..<50:
            return .orange
        default:
            return .green
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
}

// MARK: - AudioMonitor (placeholder)

@MainActor
final class AudioMonitor: ObservableObject {
    @Published var isPlaying = false
}

#Preview {
    NotchOrganizer(
        autoMode: AutoModeSwitcher()
    )
}
