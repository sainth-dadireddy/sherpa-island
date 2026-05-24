import SwiftUI
import AVFoundation

// MARK: - Enums

enum AccentColor: String, Codable, CaseIterable {
    case system
    case blue
    case green
    case purple
    case orange
    case pink
    case red

    var color: Color {
        switch self {
        case .system: return Color.accentColor
        case .blue: return .blue
        case .green: return .green
        case .purple: return .purple
        case .orange: return .orange
        case .pink: return .pink
        case .red: return .red
        }
    }

    var displayName: String {
        self.rawValue.prefix(1).uppercased() + self.rawValue.dropFirst()
    }
}

enum GlassIntensity: String, Codable, CaseIterable {
    case ultraThin
    case thin
    case regular
    case thick

    var opacity: Double {
        switch self {
        case .ultraThin: return 0.2
        case .thin: return 0.4
        case .regular: return 0.6
        case .thick: return 0.8
        }
    }

    var displayName: String {
        switch self {
        case .ultraThin: return "Ultra Thin"
        case .thin: return "Thin"
        case .regular: return "Regular"
        case .thick: return "Thick"
        }
    }
}

enum AppearancePref: String, Codable, CaseIterable {
    case auto
    case dark
    case light

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }

    var displayName: String {
        self.rawValue.prefix(1).uppercased() + self.rawValue.dropFirst()
    }
}

enum SherpaVoiceEvent: String, Codable, CaseIterable, Hashable {
    case taskComplete
    case permissionNeeded
    case meetingAlert
    case thermalAlert

    var displayName: String {
        switch self {
        case .taskComplete: return "Task Complete"
        case .permissionNeeded: return "Permission Needed"
        case .meetingAlert: return "Meeting Alert"
        case .thermalAlert: return "Thermal Alert"
        }
    }
}

enum SherpaBuddyStyle: String, Codable, CaseIterable {
    case pixel
    case modern
    case blob
    case none

    var displayName: String {
        self.rawValue.prefix(1).uppercased() + self.rawValue.dropFirst()
    }
}

enum SystemSound: String, Codable, CaseIterable {
    case tink
    case chime
    case ding
    case pop
    case bell

    var soundID: SystemSoundID {
        switch self {
        case .tink: return 1104  // Tink
        case .chime: return 1105  // Chime
        case .ding: return 1108  // Ding
        case .pop: return 1111   // Pop
        case .bell: return 1114  // Bell
        }
    }

    var displayName: String {
        self.rawValue.prefix(1).uppercased() + self.rawValue.dropFirst()
    }

    func play() {
        AudioServicesPlaySystemSound(self.soundID)
    }
}

// MARK: - SherpaPreferences

@MainActor
final class SherpaPreferences: ObservableObject {
    static let shared = SherpaPreferences()

    // MARK: Widget Configuration (17 total)
    @Published var enabledWidgets: Set<String> = SherpaPreferences.defaultEnabled {
        didSet { save() }
    }

    static let defaultEnabled: Set<String> = [
        "usage",
        "burnETA",
        "session",
        "temps",
        "fans",
        "battery",
        "nowPlaying",
        "calendar",
        "commandPalette",
        "memoryr",
        "permission"
    ]

    static let allWidgets: [String] = [
        "usage",
        "burnETA",
        "session",
        "cost",
        "mcp",
        "memoryDB",
        "temps",
        "fans",
        "battery",
        "weather",
        "nowPlaying",
        "calendar",
        "time",
        "shelf",
        "hud",
        "commandPalette",
        "memoryr",
        "permission",
        "buddy",
        "voice",
        "heatmap"
    ]

    // MARK: Theme
    @Published var accentColor: AccentColor = .system {
        didSet { save() }
    }

    @Published var glassIntensity: GlassIntensity = .ultraThin {
        didSet { save() }
    }

    @Published var prefersDarkMode: AppearancePref = .auto {
        didSet { save() }
    }

    @Published var notchPanelOpacity: Double = 1.0 {
        didSet {
            let clamped = max(0.0, min(1.0, notchPanelOpacity))
            if notchPanelOpacity != clamped {
                self.notchPanelOpacity = clamped
            }
            save()
        }
    }

    // MARK: Animation
    @Published var animationsEnabled: Bool = true {
        didSet { save() }
    }

    @Published var reduceMotion: Bool = false {
        didSet { save() }
    }

    @Published var springStiffness: Double = 0.4 {
        didSet {
            let clamped = max(0.1, min(1.0, springStiffness))
            if springStiffness != clamped {
                self.springStiffness = clamped
            }
            save()
        }
    }

    // MARK: Voice
    @Published var voiceEnabled: Bool = false {
        didSet { save() }
    }

    @Published var voiceID: String = "com.apple.voice.compact.en-US.Samantha" {
        didSet { save() }
    }

    @Published var voiceRate: Float = 0.5 {
        didSet {
            let clamped = max(0.0, min(1.0, voiceRate))
            if voiceRate != clamped {
                self.voiceRate = clamped
            }
            save()
        }
    }

    @Published var voiceVolume: Float = 0.7 {
        didSet {
            let clamped = max(0.0, min(1.0, voiceVolume))
            if voiceVolume != clamped {
                self.voiceVolume = clamped
            }
            save()
        }
    }

    @Published var voiceEventTypes: Set<SherpaVoiceEvent> = [.taskComplete] {
        didSet { save() }
    }

    // MARK: Buddy
    @Published var buddyEnabled: Bool = true {
        didSet { save() }
    }

    @Published var buddyStyle: SherpaBuddyStyle = .pixel {
        didSet { save() }
    }

    // MARK: Notification Sounds
    @Published var soundOnNotification: Bool = true {
        didSet { save() }
    }

    @Published var soundOnTaskComplete: Bool = true {
        didSet { save() }
    }

    @Published var soundEffect: SystemSound = .tink {
        didSet { save() }
    }

    // MARK: Display Mode
    @Published var defaultExpandHover: Bool = true {
        didSet { save() }
    }

    @Published var collapsedShowDots: Bool = true {
        didSet { save() }
    }

    @Published var compactMode: Bool = false {
        didSet { save() }
    }

    // MARK: Polling Intervals (Advanced)
    @Published var usagePollSeconds: Int = 300 {
        didSet {
            let clamped = max(60, min(3600, usagePollSeconds))
            if usagePollSeconds != clamped {
                self.usagePollSeconds = clamped
            }
            save()
        }
    }

    @Published var sensorPollSeconds: Int = 1 {
        didSet {
            let clamped = max(1, min(60, sensorPollSeconds))
            if sensorPollSeconds != clamped {
                self.sensorPollSeconds = clamped
            }
            save()
        }
    }

    @Published var enabledMCPHealthCheck: Bool = true {
        didSet { save() }
    }

    // MARK: Init & Persistence
    private let userDefaults: UserDefaults
    private let storageKey = "sherpa.preferences.v1"

    init(userDefaults: UserDefaults = UserDefaults(suiteName: "com.sherpa.SherpaIsland") ?? .standard) {
        self.userDefaults = userDefaults
        load()
    }

    // MARK: Load/Save/Reset

    func load() {
        guard let data = userDefaults.data(forKey: storageKey) else { return }

        do {
            let decoded = try JSONDecoder().decode(PreferencesData.self, from: data)

            // Widgets
            enabledWidgets = decoded.enabledWidgets

            // Theme
            accentColor = decoded.accentColor
            glassIntensity = decoded.glassIntensity
            prefersDarkMode = decoded.prefersDarkMode
            notchPanelOpacity = decoded.notchPanelOpacity

            // Animation
            animationsEnabled = decoded.animationsEnabled
            reduceMotion = decoded.reduceMotion
            springStiffness = decoded.springStiffness

            // Voice
            voiceEnabled = decoded.voiceEnabled
            voiceID = decoded.voiceID
            voiceRate = decoded.voiceRate
            voiceVolume = decoded.voiceVolume
            voiceEventTypes = decoded.voiceEventTypes

            // Buddy
            buddyEnabled = decoded.buddyEnabled
            buddyStyle = decoded.buddyStyle

            // Sounds
            soundOnNotification = decoded.soundOnNotification
            soundOnTaskComplete = decoded.soundOnTaskComplete
            soundEffect = decoded.soundEffect

            // Display
            defaultExpandHover = decoded.defaultExpandHover
            collapsedShowDots = decoded.collapsedShowDots
            compactMode = decoded.compactMode

            // Polling
            usagePollSeconds = decoded.usagePollSeconds
            sensorPollSeconds = decoded.sensorPollSeconds
            enabledMCPHealthCheck = decoded.enabledMCPHealthCheck
        } catch {
            os_log("Failed to decode preferences: %{public}@", log: .preferences, type: .error, error.localizedDescription)
        }
    }

    func save() {
        let data = PreferencesData(
            enabledWidgets: enabledWidgets,
            accentColor: accentColor,
            glassIntensity: glassIntensity,
            prefersDarkMode: prefersDarkMode,
            notchPanelOpacity: notchPanelOpacity,
            animationsEnabled: animationsEnabled,
            reduceMotion: reduceMotion,
            springStiffness: springStiffness,
            voiceEnabled: voiceEnabled,
            voiceID: voiceID,
            voiceRate: voiceRate,
            voiceVolume: voiceVolume,
            voiceEventTypes: voiceEventTypes,
            buddyEnabled: buddyEnabled,
            buddyStyle: buddyStyle,
            soundOnNotification: soundOnNotification,
            soundOnTaskComplete: soundOnTaskComplete,
            soundEffect: soundEffect,
            defaultExpandHover: defaultExpandHover,
            collapsedShowDots: collapsedShowDots,
            compactMode: compactMode,
            usagePollSeconds: usagePollSeconds,
            sensorPollSeconds: sensorPollSeconds,
            enabledMCPHealthCheck: enabledMCPHealthCheck
        )

        do {
            let encoded = try JSONEncoder().encode(data)
            userDefaults.set(encoded, forKey: storageKey)
        } catch {
            os_log("Failed to encode preferences: %{public}@", log: .preferences, type: .error, error.localizedDescription)
        }
    }

    func reset() {
        enabledWidgets = Self.defaultEnabled
        accentColor = .system
        glassIntensity = .ultraThin
        prefersDarkMode = .auto
        notchPanelOpacity = 1.0
        animationsEnabled = true
        reduceMotion = false
        springStiffness = 0.4
        voiceEnabled = false
        voiceID = "com.apple.voice.compact.en-US.Samantha"
        voiceRate = 0.5
        voiceVolume = 0.7
        voiceEventTypes = [.taskComplete]
        buddyEnabled = true
        buddyStyle = .pixel
        soundOnNotification = true
        soundOnTaskComplete = true
        soundEffect = .tink
        defaultExpandHover = true
        collapsedShowDots = true
        compactMode = false
        usagePollSeconds = 300
        sensorPollSeconds = 1
        enabledMCPHealthCheck = true
        save()
    }

    // MARK: Widget Management

    func toggleWidget(_ id: String) {
        if enabledWidgets.contains(id) {
            enabledWidgets.remove(id)
        } else {
            enabledWidgets.insert(id)
        }
    }

    func isEnabled(_ id: String) -> Bool {
        enabledWidgets.contains(id)
    }

    func enableWidget(_ id: String) {
        enabledWidgets.insert(id)
    }

    func disableWidget(_ id: String) {
        enabledWidgets.remove(id)
    }

    func resetWidgets() {
        enabledWidgets = Self.defaultEnabled
    }
}

// MARK: - Internal Codable Data Structure

private struct PreferencesData: Codable {
    let enabledWidgets: Set<String>
    let accentColor: AccentColor
    let glassIntensity: GlassIntensity
    let prefersDarkMode: AppearancePref
    let notchPanelOpacity: Double
    let animationsEnabled: Bool
    let reduceMotion: Bool
    let springStiffness: Double
    let voiceEnabled: Bool
    let voiceID: String
    let voiceRate: Float
    let voiceVolume: Float
    let voiceEventTypes: Set<SherpaVoiceEvent>
    let buddyEnabled: Bool
    let buddyStyle: SherpaBuddyStyle
    let soundOnNotification: Bool
    let soundOnTaskComplete: Bool
    let soundEffect: SystemSound
    let defaultExpandHover: Bool
    let collapsedShowDots: Bool
    let compactMode: Bool
    let usagePollSeconds: Int
    let sensorPollSeconds: Int
    let enabledMCPHealthCheck: Bool
}

// MARK: - OSLog Extension

import os

extension OSLog {
    static let preferences = OSLog(subsystem: "com.sherpa.SherpaIsland.Preferences", category: "preferences")
}
