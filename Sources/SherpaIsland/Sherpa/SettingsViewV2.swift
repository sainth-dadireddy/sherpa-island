import SwiftUI

struct SettingsViewV2: View {
    @AppStorage("sherpa.useSherpaOrganizer") var useSherpaOrganizer = false
    @AppStorage("sherpa.accentColorName") var accentColorName = "blue"
    @AppStorage("sherpa.glassIntensity") var glassIntensity = "ultraThin"
    @AppStorage("sherpa.notchOpacity") var notchOpacity = 1.0
    @AppStorage("sherpa.voiceEnabled") var voiceEnabled = false
    @AppStorage("sherpa.soundOnNotification") var soundOnNotification = true
    @AppStorage("sherpa.animationsEnabled") var animationsEnabled = true

    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            layoutTab
                .tabItem {
                    Label("Layout", systemImage: "square.grid.2x2")
                }
                .tag(0)

            themeTab
                .tabItem {
                    Label("Theme", systemImage: "paintpalette.fill")
                }
                .tag(1)

            voiceAndSoundsTab
                .tabItem {
                    Label("Voice & Sounds", systemImage: "speaker.wave.3")
                }
                .tag(2)

            animationTab
                .tabItem {
                    Label("Animation", systemImage: "sparkles")
                }
                .tag(3)
        }
        .frame(width: 500, height: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Layout Tab
    private var layoutTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Use Sherpa Island Layout")
                        .font(.system(.body, design: .default))
                    Spacer()
                    Toggle("", isOn: $useSherpaOrganizer)
                }
                .padding(.vertical, 6)

                Divider()
                    .foregroundColor(Color(nsColor: .separatorColor))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Off = classic layout")
                        .font(.system(.caption, design: .default))
                        .foregroundColor(.secondary)
                    Text("On = tabbed Claude/System/Media organizer")
                        .font(.system(.caption, design: .default))
                        .foregroundColor(.secondary)
                }

                Divider()
                    .foregroundColor(Color(nsColor: .separatorColor))

                Text("Changes take effect immediately")
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(16)
        .background(Material.ultraThin)
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

@available(macOS 14, *)
#Preview {
    SettingsViewV2()
}
