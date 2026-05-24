import SwiftUI
import AVFoundation

/// Comprehensive settings panel for SherpaIsland, organized into 6 tabs:
/// Widgets, Theme, Voice, Sounds, Animation, and Advanced.
@MainActor
struct SettingsView: View {
    @ObservedObject var prefs: BuddyPreferences
    @State private var selectedTab: SettingsTab = .widgets
    @State private var widgetStates: [String: Bool] = [:]
    @State private var synthesizer = AVSpeechSynthesizer()
    @State private var soundPlayer: NSSound?
    @State private var animationPreviewScale: CGFloat = 1.0

    let windowWidth: CGFloat = 600
    let windowHeight: CGFloat = 500

    var body: some View {
        ZStack {
            // Liquid glass background
            Color(nsColor: .controlBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: 8) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Button(action: { selectedTab = tab }) {
                            VStack(spacing: 4) {
                                Image(systemName: tab.iconName)
                                    .font(.system(size: 18, weight: .regular))
                                Text(tab.label)
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                            .background(selectedTab == tab ? Color.gray.opacity(0.1) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Material.ultraThin)
                .overlay(
                    Divider()
                        .frame(height: 0.5)
                    , alignment: .bottom
                )

                // Content area
                TabView(selection: $selectedTab) {
                    WidgetsTabView(prefs: prefs, widgetStates: $widgetStates)
                        .tag(SettingsTab.widgets)

                    ThemeTabView(prefs: prefs)
                        .tag(SettingsTab.theme)

                    VoiceTabView(prefs: prefs, synthesizer: $synthesizer)
                        .tag(SettingsTab.voice)

                    SoundsTabView(prefs: prefs, soundPlayer: $soundPlayer)
                        .tag(SettingsTab.sounds)

                    AnimationTabView(animationPreviewScale: $animationPreviewScale)
                        .tag(SettingsTab.animation)

                    AdvancedTabView(prefs: prefs)
                        .tag(SettingsTab.advanced)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .frame(width: windowWidth, height: windowHeight)
        .background(Material.ultraThin)
    }
}

enum SettingsTab: CaseIterable, Hashable {
    case widgets, theme, voice, sounds, animation, advanced

    var label: String {
        switch self {
        case .widgets: return "Widgets"
        case .theme: return "Theme"
        case .voice: return "Voice"
        case .sounds: return "Sounds"
        case .animation: return "Animation"
        case .advanced: return "Advanced"
        }
    }

    var iconName: String {
        switch self {
        case .widgets: return "square.grid.2x2"
        case .theme: return "paintpalette.fill"
        case .voice: return "waveform"
        case .sounds: return "speaker.wave.3"
        case .animation: return "sparkles"
        case .advanced: return "gearshape.2.fill"
        }
    }
}

// MARK: - Widgets Tab

struct WidgetsTabView: View {
    @ObservedObject var prefs: BuddyPreferences
    @Binding var widgetStates: [String: Bool]

    let widgetGroups: [(group: String, widgets: [String])] = [
        ("Claude", ["StatusMonitor", "SessionTimer", "ContextUsage"]),
        ("System", ["CPUMonitor", "MemoryMonitor", "BatteryStatus"]),
        ("Media", ["NowPlaying", "VolumeControl", "BrightnessControl"]),
        ("Overlays", ["PermissionAlert", "ThermalWarning", "NotificationCenter"]),
        ("Inherited", ["LegacyTimer", "LegacyStatus", "NetworkMonitor", "StorageMonitor"])
    ]

    var enabledCount: Int {
        widgetStates.values.filter { $0 }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Live count display
                HStack {
                    Text("Enabled Widgets")
                        .font(.headline)
                    Spacer()
                    Text("\(enabledCount) of 17 widgets enabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top)

                // Widget groups
                ForEach(widgetGroups, id: \.group) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.group)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        ForEach(group.widgets, id: \.self) { widget in
                            Toggle(widget, isOn: Binding(
                                get: { widgetStates[widget] ?? false },
                                set: { widgetStates[widget] = $0 }
                            ))
                            .toggleStyle(.switch)
                            .padding(.horizontal)
                        }
                    }
                }

                // Reset button
                Button(action: resetToDefaults) {
                    Text("Reset to Defaults")
                        .frame(maxWidth: .infinity)
                        .padding(10)
                }
                .buttonStyle(.bordered)
                .padding()

                Spacer()
            }
        }
    }

    func resetToDefaults() {
        for widget in widgetStates.keys {
            widgetStates[widget] = false
        }
        // Reset to 8 default widgets
        let defaults = ["StatusMonitor", "SessionTimer", "ContextUsage", "CPUMonitor",
                       "MemoryMonitor", "BatteryStatus", "NowPlaying", "NetworkMonitor"]
        for widget in defaults {
            widgetStates[widget] = true
        }
    }
}

// MARK: - Theme Tab

struct ThemeTabView: View {
    @ObservedObject var prefs: BuddyPreferences
    @State private var accentColor: Color = .blue
    @State private var glassIntensity: Material = .ultraThin
    @State private var appearance: Appearance = .auto
    @State private var notchOpacity: Double = 0.9

    enum Appearance: String, CaseIterable {
        case auto, dark, light
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Accent color picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Accent Color")
                        .font(.headline)

                    HStack(spacing: 12) {
                        ForEach([Color.blue, Color.green, Color.purple, Color.orange, Color.pink, Color.red], id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .stroke(accentColor == color ? Color.white : Color.clear, lineWidth: 2)
                                )
                                .onTapGesture { accentColor = color }
                        }
                    }
                    .padding()
                    .background(Material.ultraThin)
                    .cornerRadius(8)
                }
                .padding()

                // Glass intensity
                VStack(alignment: .leading, spacing: 12) {
                    Text("Glass Intensity")
                        .font(.headline)

                    VStack(spacing: 8) {
                        ForEach([Material.ultraThin, Material.thin, Material.regular, Material.thick], id: \.self) { material in
                            HStack {
                                Text(material == Material.ultraThin ? "Ultra Thin" :
                                     material == Material.thin ? "Thin" :
                                     material == Material.regular ? "Regular" : "Thick")
                                Spacer()
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(material)
                                    .frame(width: 120, height: 40)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(6)
                            .onTapGesture { glassIntensity = material }
                        }
                    }
                    .padding()
                    .background(Material.ultraThin)
                    .cornerRadius(8)
                }
                .padding()

                // Appearance mode
                VStack(alignment: .leading, spacing: 12) {
                    Text("Appearance")
                        .font(.headline)

                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }
                .padding()

                // Notch panel opacity
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Notch Panel Opacity")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.1f", notchOpacity))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $notchOpacity, in: 0.5...1.0, step: 0.05)
                        .padding()

                    RoundedRectangle(cornerRadius: 8)
                        .fill(Material.ultraThin)
                        .opacity(notchOpacity)
                        .frame(height: 60)
                        .padding()
                }
                .padding()

                Spacer()
            }
        }
    }
}

// MARK: - Voice Tab

struct VoiceTabView: View {
    @ObservedObject var prefs: BuddyPreferences
    @Binding var synthesizer: AVSpeechSynthesizer
    @State private var selectedVoice: AVSpeechSynthesisVoice?
    @State private var voiceRate: Float = 0.5
    @State private var voiceVolume: Float = 1.0

    var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Master voice toggle
                Toggle("Voice Enabled", isOn: $prefs.voiceEnabled)
                    .toggleStyle(.switch)
                    .padding()

                if prefs.voiceEnabled {
                    Divider()
                        .padding()

                    // Voice picker
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Voice")
                            .font(.headline)

                        Picker("Voice", selection: $selectedVoice) {
                            ForEach(availableVoices, id: \.identifier) { voice in
                                Text(voice.name).tag(voice as AVSpeechSynthesisVoice?)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding()
                    }
                    .padding()

                    // Rate slider
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Speech Rate")
                                .font(.headline)
                            Spacer()
                            Text(String(format: "%.1f", voiceRate))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Slider(value: $voiceRate, in: 0.0...1.0, step: 0.1)
                            .padding()
                    }
                    .padding()

                    // Volume slider
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Volume")
                                .font(.headline)
                            Spacer()
                            Text(String(format: "%.0f%%", voiceVolume * 100))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Slider(value: $voiceVolume, in: 0.0...1.0, step: 0.05)
                            .padding()
                    }
                    .padding()

                    // Test button
                    Button(action: speakSample) {
                        Text("Speak Sample")
                            .frame(maxWidth: .infinity)
                            .padding(10)
                    }
                    .buttonStyle(.bordered)
                    .padding()

                    Divider()
                        .padding()

                    // Event triggers
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Announce When")
                            .font(.headline)

                        VStack(spacing: 8) {
                            ForEach(SherpaVoiceEvent.allCases, id: \.self) { event in
                                Toggle(isOn: Binding(
                                    get: { prefs.voiceEvents[event] ?? true },
                                    set: { prefs.setVoiceEvent(event, $0) }
                                )) {
                                    HStack {
                                        Image(systemName: event.icon)
                                            .font(.system(size: 14))
                                        Text(event.label)
                                    }
                                }
                                .toggleStyle(.switch)
                            }
                        }
                        .padding()
                    }
                    .padding()
                }

                Spacer()
            }
        }
    }

    func speakSample() {
        let utterance = AVSpeechUtterance(string: "Hello, this is a sample voice announcement.")
        utterance.rate = voiceRate * AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = voiceVolume
        if let voice = selectedVoice {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
    }
}

// MARK: - Sounds Tab

struct SoundsTabView: View {
    @ObservedObject var prefs: BuddyPreferences
    @State private var notificationSoundEnabled = true
    @State private var taskCompleteSoundEnabled = true
    @State private var selectedSound = "Pop"
    @Binding var soundPlayer: NSSound?

    let soundEffects = ["Tink", "Pop", "Glass", "Hero", "Funk", "Frog", "Submarine", "Ping"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Notification sound toggle
                Toggle("Play sound on notification", isOn: $notificationSoundEnabled)
                    .toggleStyle(.switch)
                    .padding()

                // Task complete sound toggle
                Toggle("Play sound on task complete", isOn: $taskCompleteSoundEnabled)
                    .toggleStyle(.switch)
                    .padding()

                Divider()
                    .padding()

                // Sound effect picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sound Effect")
                        .font(.headline)

                    Picker("Sound Effect", selection: $selectedSound) {
                        ForEach(soundEffects, id: \.self) { sound in
                            Text(sound).tag(sound)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding()
                }
                .padding()

                // Test button
                Button(action: playTestSound) {
                    Text("Test")
                        .frame(maxWidth: .infinity)
                        .padding(10)
                }
                .buttonStyle(.bordered)
                .padding()

                Spacer()
            }
        }
    }

    func playTestSound() {
        // Map sound name to system sound or custom resources
        let soundName: String
        switch selectedSound {
        case "Tink": soundName = "Tink"
        case "Pop": soundName = "Pop"
        case "Glass": soundName = "Glass"
        case "Hero": soundName = "Hero"
        case "Funk": soundName = "Funk"
        case "Frog": soundName = "Frog"
        case "Submarine": soundName = "Submarine"
        case "Ping": soundName = "Ping"
        default: soundName = "Pop"
        }

        if let sound = NSSound(named: soundName) {
            soundPlayer = sound
            sound.play()
        }
    }
}

// MARK: - Animation Tab

struct AnimationTabView: View {
    @State private var animationsEnabled = true
    @State private var reduceMotion = false
    @State private var springStiffness: Double = 0.5
    @Binding var animationPreviewScale: CGFloat

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Animations enabled toggle
                Toggle("Animations Enabled", isOn: $animationsEnabled)
                    .toggleStyle(.switch)
                    .padding()

                // Reduce motion toggle
                Toggle("Reduce Motion", isOn: $reduceMotion)
                    .toggleStyle(.switch)
                    .padding()

                Divider()
                    .padding()

                // Spring stiffness slider
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Spring Stiffness")
                            .font(.headline)
                        Spacer()
                        Text(String(format: "%.1f", springStiffness))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $springStiffness, in: 0.1...1.0, step: 0.05)
                        .padding()
                }
                .padding()

                Divider()
                    .padding()

                // Preview zone
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preview")
                        .font(.headline)

                    VStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor)
                            .frame(width: 80, height: 40)
                            .scaleEffect(animationPreviewScale)
                            .animation(
                                .spring(response: 0.3, dampingFraction: 0.7 - (springStiffness * 0.2), blendDuration: 0.1),
                                value: animationPreviewScale
                            )
                            .onAppear {
                                withAnimation {
                                    animationPreviewScale = 1.2
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation {
                                        animationPreviewScale = 1.0
                                    }
                                }
                            }
                    }
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    .padding()
                }
                .padding()

                Spacer()
            }
        }
    }
}

// MARK: - Advanced Tab

struct AdvancedTabView: View {
    @ObservedObject var prefs: BuddyPreferences
    @State private var usagePollInterval: Double = 300
    @State private var sensorPollInterval: Double = 1
    @State private var mcpHealthCheckEnabled = true
    @State private var showResetConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Usage poll interval
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Usage Poll Interval")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(usagePollInterval))s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $usagePollInterval, in: 60...3600, step: 60)
                        .padding()
                }
                .padding()

                // Sensor poll interval
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Sensor Poll Interval")
                            .font(.headline)
                        Spacer()
                        Text("\(Int(sensorPollInterval))s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $sensorPollInterval, in: 1...60, step: 1)
                        .padding()
                }
                .padding()

                // MCP health check
                Toggle("MCP Health Check", isOn: $mcpHealthCheckEnabled)
                    .toggleStyle(.switch)
                    .padding()

                Divider()
                    .padding()

                // Reset button
                Button(action: { showResetConfirm = true }) {
                    Text("Reset All Settings")
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .padding()
                .alert("Reset All Settings?", isPresented: $showResetConfirm) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) { resetAllSettings() }
                } message: {
                    Text("This action cannot be undone.")
                }

                Divider()
                    .padding()

                // About section
                VStack(alignment: .leading, spacing: 12) {
                    Text("About")
                        .font(.headline)

                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)

                    Link(destination: URL(string: "https://github.com/sherpa-island/notchpilot")!) {
                        HStack {
                            Text("GitHub")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                        .padding(.vertical, 8)
                        .foregroundColor(.accentColor)
                    }

                    HStack {
                        Text("License")
                        Spacer()
                        Text("MIT")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .padding()
                .background(Material.ultraThin)
                .cornerRadius(8)
                .padding()

                Spacer()
            }
        }
    }

    func resetAllSettings() {
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
    }
}

#Preview {
    SettingsView(prefs: BuddyPreferences())
        .frame(width: 600, height: 500)
}
