import SwiftUI

struct SettingsViewV2: View {
    @AppStorage("sherpa.accentColorName") var accentColorName = "blue"
    @AppStorage("sherpa.glassIntensity") var glassIntensity = "ultraThin"
    @AppStorage("sherpa.notchOpacity") var notchOpacity = 1.0
    @AppStorage("sherpa.voiceEnabled") var voiceEnabled = false
    @AppStorage("sherpa.soundOnNotification") var soundOnNotification = true
    @AppStorage("sherpa.animationsEnabled") var animationsEnabled = true

    // Agent Chat (cross-CLI team) notification toggles
    @AppStorage("AgentChat.voiceEnabled") var chatVoiceEnabled = true
    @AppStorage("AgentChat.notificationsEnabled") var chatNotificationsEnabled = true
    @AppStorage("AgentChat.soundEnabled") var chatSoundEnabled = true

    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            themeTab
                .tabItem {
                    Label("Theme", systemImage: "paintpalette.fill")
                }
                .tag(0)

            voiceAndSoundsTab
                .tabItem {
                    Label("Voice & Sounds", systemImage: "speaker.wave.3")
                }
                .tag(1)

            animationTab
                .tabItem {
                    Label("Animation", systemImage: "sparkles")
                }
                .tag(2)
        }
        .frame(width: 500, height: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Theme Tab
    private var themeTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Accent Color")
                    .font(.system(.body, design: .default))

                HStack(spacing: 12) {
                    ForEach(["blue", "green", "purple", "orange", "pink", "red"], id: \.self) { colorName in
                        Button(action: { accentColorName = colorName }) {
                            Circle()
                                .fill(colorForName(colorName))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Circle()
                                        .stroke(accentColorName == colorName ? Color.primary : Color.clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }

            Divider()
                .foregroundColor(Color(nsColor: .separatorColor))

            VStack(alignment: .leading, spacing: 8) {
                Text("Glass Intensity")
                    .font(.system(.body, design: .default))

                Picker("Glass Intensity", selection: $glassIntensity) {
                    Text("Ultra Thin").tag("ultraThin")
                    Text("Thin").tag("thin")
                    Text("Regular").tag("regular")
                }
                .pickerStyle(.segmented)
            }

            Divider()
                .foregroundColor(Color(nsColor: .separatorColor))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Notch Opacity")
                        .font(.system(.body, design: .default))
                    Spacer()
                    Text(String(format: "%.1f", notchOpacity))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Slider(value: $notchOpacity, in: 0.5...1.0, step: 0.05)
            }

            Spacer()
        }
        .padding(16)
        .background(Material.ultraThin)
    }

    // MARK: - Voice & Sounds Tab
    private var voiceAndSoundsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Voice Enabled")
                    .font(.system(.body, design: .default))
                Spacer()
                Toggle("", isOn: $voiceEnabled)
            }
            .padding(.vertical, 6)

            Divider()
                .foregroundColor(Color(nsColor: .separatorColor))

            HStack {
                Text("Sound on Notification")
                    .font(.system(.body, design: .default))
                Spacer()
                Toggle("", isOn: $soundOnNotification)
            }
            .padding(.vertical, 6)

            Divider()
                .foregroundColor(Color(nsColor: .separatorColor))

            Button(action: playTestSound) {
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                    Text("Test Sound")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.vertical, 6)

            // MARK: - Agent Chat section
            Divider().padding(.vertical, 8)
            Text("Agent Team Chat")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            HStack {
                Text("Voice on new msg")
                Spacer()
                Toggle("", isOn: $chatVoiceEnabled)
            }
            .help("Speaks sender name when a new chat msg arrives")
            .padding(.vertical, 4)

            HStack {
                Text("Banner notification")
                Spacer()
                Toggle("", isOn: $chatNotificationsEnabled)
            }
            .help("macOS notification banner with sender + msg snippet")
            .padding(.vertical, 4)

            HStack {
                Text("Tink sound")
                Spacer()
                Toggle("", isOn: $chatSoundEnabled)
            }
            .help("Tink alert sound on new msg arrival")
            .padding(.vertical, 4)

            Spacer()
        }
        .padding(16)
        .background(Material.ultraThin)
    }

    // MARK: - Animation Tab
    private var animationTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Animations Enabled")
                    .font(.system(.body, design: .default))
                Spacer()
                Toggle("", isOn: $animationsEnabled)
            }
            .padding(.vertical, 6)

            Divider()
                .foregroundColor(Color(nsColor: .separatorColor))

            Text("Reduce motion respects System Settings")
                .font(.system(.caption, design: .default))
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(16)
        .background(Material.ultraThin)
    }

    // MARK: - Helpers
    private func colorForName(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "green": return .green
        case "purple": return .purple
        case "orange": return .orange
        case "pink": return .pink
        case "red": return .red
        default: return .blue
        }
    }

    private func playTestSound() {
        NSSound(named: "Tink")?.play()
    }
}

// DISABLED-AVAIL @available(macOS 14, *)
/* DISABLED-PREVIEW #Preview {
    SettingsViewV2()
} */
