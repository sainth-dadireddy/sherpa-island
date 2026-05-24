import SwiftUI
import ServiceManagement
import CoreGraphics

/// Which utilization window the usage slot displays. The two values
/// match the windows Claude's account page shows: a rolling 5-hour
/// session limit and a rolling 7-day plan limit.
enum UsageSlotWindow: String, CaseIterable, Identifiable {
    case fiveHour
    case weekly

    var id: String { rawValue }

    /// Short label used in the pill itself (squeezed next to the
    /// percentage). Kept short so the capsule stays tight.
    var shortLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly:   return "wk"
        }
    }

    /// Longer label used in the settings row.
    var label: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly:   return "Weekly"
        }
    }
}

/// One configurable cell inside the notch pill. The pill has 3 slots
/// (left, center, right); each one renders one of these. `empty` keeps
/// the slot's width but draws nothing — the notch's overall shape stays
/// the same regardless of which slots are filled. On a notched primary
/// in topCenter the center slot's value is ignored: the hardware notch
/// occupies that slot.
enum NotchSlotItem: String, CaseIterable, Identifiable {
    case empty
    case buddy
    case status
    case usage

    var id: String { rawValue }

    var label: String {
        switch self {
        case .empty:  return "None"
        case .buddy:  return "Buddy"
        case .status: return "Status"
        case .usage:  return "Usage"
        }
    }
}

/// Magnetic snap anchors used while dragging. The pill snaps to one of
/// these when the user releases close enough; otherwise the drop
/// location is honored verbatim (free positioning).
enum NotchSnapAnchor: CaseIterable {
    case left
    case center
    case right

    /// Position fraction along the placeable horizontal range
    /// (0 = pill flush with left edge + padding, 1 = pill flush with
    /// right edge - padding, 0.5 = centered).
    var fraction: CGFloat {
        switch self {
        case .left:   return 0.0
        case .center: return 0.5
        case .right:  return 1.0
        }
    }
}

/// Legacy storage shape from v0.4.x. Kept only so we can migrate old
/// `UserDefaults` values into the new fractional anchor on first
/// launch — not used at runtime anywhere else.
private enum LegacyNotchPosition: String {
    case topLeft, topMidLeft, topCenter, topMidRight, topRight

    var fraction: CGFloat {
        switch self {
        case .topLeft:     return 0.0
        case .topMidLeft:  return 0.25
        case .topCenter:   return 0.5
        case .topMidRight: return 0.75
        case .topRight:    return 1.0
        }
    }
}

/// Categories of events the buddy can announce out loud. Each has its own
/// toggle in preferences so the user can enable just the noise they want.
/// Events that can cause the buddy to pop out of the notch and say
/// something. Each case has its own preference toggle so users can
/// mute individual triggers. Add cases here as new speech kinds are
/// added to `SpeechKind`.
enum SpeechEvent: String, CaseIterable, Identifiable {
    case sessionFinished

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sessionFinished: return "Session finished"
        }
    }

    var icon: String {
        switch self {
        case .sessionFinished: return "checkmark.circle.fill"
        }
    }
}

enum VoiceEvent: String, CaseIterable, Identifiable {
    case permission
    case danger
    case started
    case finished
    case contextHigh
    case idleAlert
    case collision
    case modeChange

    var id: String { rawValue }

    var label: String {
        switch self {
        case .permission:   return "Permission needed"
        case .danger:       return "Dangerous command"
        case .started:      return "Session started"
        case .finished:     return "Session finished"
        case .contextHigh:  return "Context near cap"
        case .idleAlert:    return "Pinned session idle"
        case .collision:    return "Multiple sessions share cwd"
        case .modeChange:   return "Permission mode changed"
        }
    }

    var icon: String {
        switch self {
        case .permission:   return "hand.raised.fill"
        case .danger:       return "exclamationmark.triangle.fill"
        case .started:      return "play.circle.fill"
        case .finished:     return "checkmark.circle.fill"
        case .contextHigh:  return "gauge.with.dots.needle.67percent"
        case .idleAlert:    return "moon.zzz.fill"
        case .collision:    return "exclamationmark.2"
        case .modeChange:   return "slider.horizontal.3"
        }
    }
}

/// User-pickable appearance + sound settings for the buddy, persisted to
/// `UserDefaults`. Injected into the SwiftUI view tree via `.environmentObject`.
@MainActor
final class BuddyPreferences: ObservableObject {
    @Published var style: BuddyStyle {
        didSet {
            UserDefaults.standard.set(style.rawValue, forKey: Self.styleKey)
        }
    }

    @Published var color: BuddyColor {
        didSet {
            UserDefaults.standard.set(color.rawValue, forKey: Self.colorKey)
        }
    }

    /// When true, the buddy stays pinned to the notch at all times,
    /// even with no active Claude session. Off by default — the default
    /// behavior is to fade out 10s after activity ends and re-appear on
    /// the next session (or on hover).
    @Published var alwaysVisible: Bool {
        didSet {
            UserDefaults.standard.set(alwaysVisible, forKey: Self.alwaysVisibleKey)
        }
    }

    /// When true, the app registers itself as a macOS login item via
    /// SMAppService so it auto-launches on every login. Defaults to
    /// true — the natural expectation for a menu-bar utility.
    @Published var startAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(startAtLogin, forKey: Self.startAtLoginKey)
            applyStartAtLogin()
        }
    }

    /// When true, the buddy fires a subtle haptic tick through the
    /// trackpad whenever the notch panel opens or closes. Only works
    /// on devices with a Force Touch trackpad; external mouse/keyboard
    /// users get nothing. Defaults on.
    @Published var hapticsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hapticsEnabled, forKey: Self.hapticsKey)
        }
    }

    /// When true, the notch hides when any app is in fullscreen mode.
    /// Defaults true — fullscreen covers the notch area anyway.
    @Published var hideInFullscreen: Bool {
        didSet {
            UserDefaults.standard.set(hideInFullscreen, forKey: Self.hideFullscreenKey)
        }
    }

    /// When true, permission prompts are suppressed in the notch if the
    /// terminal running the session is the frontmost app. The user can
    /// answer directly in the terminal. Defaults false (always show).
    @Published var suppressPermissionWhenFocused: Bool {
        didSet {
            UserDefaults.standard.set(suppressPermissionWhenFocused, forKey: Self.suppressPermKey)
        }
    }

    /// Master toggle for speech — when off, no event can trigger a
    /// buddy pop-out regardless of per-event flags. Defaults on.
    @Published var speechEnabled: Bool {
        didSet {
            UserDefaults.standard.set(speechEnabled, forKey: Self.speechKey)
        }
    }


    /// Per-event speech toggles.
    @Published var speechEvents: [SpeechEvent: Bool] {
        didSet {
            let raw = speechEvents.reduce(into: [String: Bool]()) { acc, pair in
                acc[pair.key.rawValue] = pair.value
            }
            UserDefaults.standard.set(raw, forKey: Self.speechEventsKey)
        }
    }

    func speechAllows(_ event: SpeechEvent) -> Bool {
        speechEnabled && (speechEvents[event] ?? true)
    }

    func setSpeechEvent(_ event: SpeechEvent, _ enabled: Bool) {
        var copy = speechEvents
        copy[event] = enabled
        speechEvents = copy
    }

    /// Pushes the current `startAtLogin` value to macOS via SMAppService.
    /// Idempotent: safe to call repeatedly. Logs and continues on
    /// failure (e.g. when running from a non-bundled `swift run` build
    /// where the main app service isn't resolvable).
    func applyStartAtLogin() {
        let service = SMAppService.mainApp
        do {
            if startAtLogin {
                if service.status != .enabled {
                    try service.register()
                    print("[SherpaIsland] Registered as login item")
                }
            } else {
                if service.status == .enabled || service.status == .requiresApproval {
                    try service.unregister()
                    print("[SherpaIsland] Unregistered from login items")
                }
            }
        } catch {
            print("[SherpaIsland] start-at-login update failed: \(error)")
        }
    }

    /// Master toggle. If off, NOTHING speaks regardless of per-event flags.
    @Published var voiceEnabled: Bool {
        didSet {
            UserDefaults.standard.set(voiceEnabled, forKey: Self.voiceKey)
        }
    }

    /// Per-event toggles. All default true — user can selectively mute.
    @Published var voiceEvents: [VoiceEvent: Bool] {
        didSet {
            let raw = voiceEvents.reduce(into: [String: Bool]()) { acc, pair in
                acc[pair.key.rawValue] = pair.value
            }
            UserDefaults.standard.set(raw, forKey: Self.voiceEventsKey)
        }
    }

    /// AVSpeechSynthesisVoice identifier the user picked. Empty string =
    /// fall back to the built-in Ava → en-US chain in VoiceAnnouncer.
    @Published var voiceIdentifier: String {
        didSet {
            UserDefaults.standard.set(voiceIdentifier, forKey: Self.voiceIdentifierKey)
        }
    }

    /// Playback rate multiplier applied to AVSpeechUtteranceDefaultSpeechRate.
    /// Range 0.5–1.5. Stored as Double.
    @Published var voiceRate: Double {
        didSet {
            UserDefaults.standard.set(voiceRate, forKey: Self.voiceRateKey)
        }
    }

    /// Shell command Sherpa Island runs (via `/bin/zsh -lc`) when the
    /// hottest temperature sensor crosses into the hot band. Empty =
    /// no action. Example: `sudo pmset -a forcefans 6500` (requires
    /// passwordless sudo entry the user sets up in /etc/sudoers.d).
    @Published var thermalActionCommand: String {
        didSet {
            UserDefaults.standard.set(thermalActionCommand, forKey: Self.thermalActionKey)
        }
    }

    /// Shell command run when temperature is hot/critical AND macOS
    /// Low Power Mode is enabled — so the user can flip out of LPM
    /// for full performance. Example: `sudo pmset -b lowpowermode 0`.
    @Published var lowPowerActionCommand: String {
        didSet {
            UserDefaults.standard.set(lowPowerActionCommand, forKey: Self.lowPowerActionKey)
        }
    }

    /// Shell command run when temperature drops back to cool/warm from
    /// hot or critical — undo whatever the escalation did. Example:
    /// `sudo pmset -b lowpowermode 1 && sudo thermalforge fan set auto`
    /// to re-enable battery saving and stop force-ramping fans.
    @Published var coolDownActionCommand: String {
        didSet {
            UserDefaults.standard.set(coolDownActionCommand, forKey: Self.coolDownActionKey)
        }
    }

    /// Returns true iff the master toggle is on AND this specific event's
    /// flag is on. Use this at every `speak` call site.
    func voiceAllows(_ event: VoiceEvent) -> Bool {
        voiceEnabled && (voiceEvents[event] ?? true)
    }

    func setVoiceEvent(_ event: VoiceEvent, _ enabled: Bool) {
        var copy = voiceEvents
        copy[event] = enabled
        voiceEvents = copy
    }

    /// Where the pill sits on its host screen, expressed as a fraction
    /// from 0 (flush left) to 1 (flush right) of the placeable
    /// horizontal range. Updated by the drag-to-move interaction in
    /// NotchWindow (with magnetic snap to 0.0 / 0.5 / 1.0) and by the
    /// "Reset position" settings button.
    @Published var notchAnchorFraction: CGFloat {
        didSet {
            UserDefaults.standard.set(
                Double(notchAnchorFraction),
                forKey: Self.notchAnchorFractionKey
            )
        }
    }

    /// When true (default) the pill is constrained to the top edge of
    /// the screen — the original notch behavior. When false, drag-and-
    /// drop is fully 2D: the pill rests wherever the user drops it,
    /// using `notchAnchorYFromTop`. Magnetic snap to the three top-edge
    /// anchors only fires while this is on.
    @Published var pinToTopEdge: Bool {
        didSet {
            UserDefaults.standard.set(pinToTopEdge, forKey: Self.pinToTopEdgeKey)
        }
    }

    /// Distance, in points, from the top of the host screen to the
    /// pill's top edge. Only consulted when `pinToTopEdge` is false.
    @Published var notchAnchorYFromTop: CGFloat {
        didSet {
            UserDefaults.standard.set(
                Double(notchAnchorYFromTop),
                forKey: Self.notchAnchorYFromTopKey
            )
        }
    }

    /// Display the notch is currently shown on. `nil` means "follow the
    /// system primary screen." Persisted as an Int because UserDefaults
    /// has no native UInt32 setter; widened for safety.
    @Published var notchScreenID: CGDirectDisplayID? {
        didSet {
            if let id = notchScreenID {
                UserDefaults.standard.set(Int(id), forKey: Self.notchScreenIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.notchScreenIDKey)
            }
        }
    }

    /// What's drawn in the left slot of the pill. Defaults to the buddy
    /// face — that's where it has always lived.
    @Published var notchLeftSlot: NotchSlotItem {
        didSet {
            UserDefaults.standard.set(notchLeftSlot.rawValue, forKey: Self.notchLeftSlotKey)
        }
    }

    /// What's drawn in the center slot. Ignored on the notched primary
    /// in topCenter (hardware notch occupies the slot). Defaults to
    /// `.empty` so silhouette mode keeps its current look.
    @Published var notchCenterSlot: NotchSlotItem {
        didSet {
            UserDefaults.standard.set(notchCenterSlot.rawValue, forKey: Self.notchCenterSlotKey)
        }
    }

    /// What's drawn in the right slot. Defaults to the session-status
    /// text — same as today.
    @Published var notchRightSlot: NotchSlotItem {
        didSet {
            UserDefaults.standard.set(notchRightSlot.rawValue, forKey: Self.notchRightSlotKey)
        }
    }

    /// Which utilization window the `usage` slot shows. Only relevant
    /// when one of the slots is set to `.usage`.
    @Published var usageSlotWindow: UsageSlotWindow {
        didSet {
            UserDefaults.standard.set(usageSlotWindow.rawValue, forKey: Self.usageSlotWindowKey)
        }
    }

    private static let styleKey = "sherpaisland.style"
    private static let colorKey = "sherpaisland.color"
    private static let voiceKey = "sherpaisland.voice"
    private static let voiceEventsKey = "sherpaisland.voice.events"
    private static let voiceIdentifierKey = "sherpaisland.voice.identifier"
    private static let voiceRateKey = "sherpaisland.voice.rate"
    private static let thermalActionKey = "sherpaisland.thermal.action"
    private static let lowPowerActionKey = "sherpaisland.thermal.lpm_off_action"
    private static let coolDownActionKey = "sherpaisland.thermal.cooldown_action"
    private static let alwaysVisibleKey = "sherpaisland.alwaysVisible"
    private static let startAtLoginKey = "sherpaisland.startAtLogin"
    private static let hapticsKey = "sherpaisland.haptics"
    private static let speechKey = "sherpaisland.speech"
    private static let speechEventsKey = "sherpaisland.speech.events"
    private static let suppressPermKey = "sherpaisland.suppressPermissionWhenFocused"
    private static let hideFullscreenKey = "sherpaisland.hideInFullscreen"
    private static let notchPositionKey = "sherpaisland.notchPosition"  // legacy
    private static let notchAnchorFractionKey = "sherpaisland.notchAnchorFraction"
    private static let notchAnchorYFromTopKey = "sherpaisland.notchAnchorYFromTop"
    private static let pinToTopEdgeKey = "sherpaisland.pinToTopEdge"
    private static let notchScreenIDKey = "sherpaisland.notchScreenID"
    private static let notchLeftSlotKey = "sherpaisland.notchLeftSlot"
    private static let notchCenterSlotKey = "sherpaisland.notchCenterSlot"
    private static let notchRightSlotKey = "sherpaisland.notchRightSlot"
    private static let usageSlotWindowKey = "sherpaisland.usageSlotWindow"

    init() {
        let defaults = UserDefaults.standard
        let storedStyle = defaults.string(forKey: Self.styleKey) ?? ""
        let storedColor = defaults.string(forKey: Self.colorKey) ?? ""
        style = BuddyStyle(rawValue: storedStyle) ?? .eyes
        color = BuddyColor(rawValue: storedColor) ?? .green
        // Voice master defaults off so new users don't get surprised.
        voiceEnabled = defaults.object(forKey: Self.voiceKey) as? Bool ?? false
        voiceIdentifier = defaults.string(forKey: Self.voiceIdentifierKey) ?? ""
        voiceRate = defaults.object(forKey: Self.voiceRateKey) as? Double ?? 1.05
        thermalActionCommand = defaults.string(forKey: Self.thermalActionKey) ?? ""
        lowPowerActionCommand = defaults.string(forKey: Self.lowPowerActionKey) ?? ""
        coolDownActionCommand = defaults.string(forKey: Self.coolDownActionKey) ?? ""
        alwaysVisible = defaults.object(forKey: Self.alwaysVisibleKey) as? Bool ?? true
        startAtLogin = defaults.object(forKey: Self.startAtLoginKey) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Self.hapticsKey) as? Bool ?? true
        speechEnabled = defaults.object(forKey: Self.speechKey) as? Bool ?? true
        suppressPermissionWhenFocused = defaults.object(forKey: Self.suppressPermKey) as? Bool ?? false
        // Default to false so the notch stays visible over a
        // fullscreen Space out of the box. Users who prefer the old
        // behavior can flip it back in Settings — the pref still
        // honors whatever value they explicitly saved.
        hideInFullscreen = defaults.object(forKey: Self.hideFullscreenKey) as? Bool ?? false

        if let storedFraction = defaults.object(forKey: Self.notchAnchorFractionKey) as? Double {
            notchAnchorFraction = CGFloat(storedFraction)
        } else if let legacyRaw = defaults.string(forKey: Self.notchPositionKey),
                  let legacy = LegacyNotchPosition(rawValue: legacyRaw) {
            // First launch on the new fractional model — promote the
            // old enum value and drop the obsolete key.
            notchAnchorFraction = legacy.fraction
            defaults.removeObject(forKey: Self.notchPositionKey)
        } else {
            notchAnchorFraction = 0.5
        }
        pinToTopEdge = defaults.object(forKey: Self.pinToTopEdgeKey) as? Bool ?? true
        notchAnchorYFromTop = CGFloat(
            (defaults.object(forKey: Self.notchAnchorYFromTopKey) as? Double) ?? 0
        )
        if let storedScreen = defaults.object(forKey: Self.notchScreenIDKey) as? Int {
            notchScreenID = CGDirectDisplayID(storedScreen)
        } else {
            notchScreenID = nil
        }

        let storedLeft = defaults.string(forKey: Self.notchLeftSlotKey) ?? ""
        notchLeftSlot = NotchSlotItem(rawValue: storedLeft) ?? .buddy
        let storedCenter = defaults.string(forKey: Self.notchCenterSlotKey) ?? ""
        notchCenterSlot = NotchSlotItem(rawValue: storedCenter) ?? .empty
        let storedRight = defaults.string(forKey: Self.notchRightSlotKey) ?? ""
        notchRightSlot = NotchSlotItem(rawValue: storedRight) ?? .status
        let storedWindow = defaults.string(forKey: Self.usageSlotWindowKey) ?? ""
        usageSlotWindow = UsageSlotWindow(rawValue: storedWindow) ?? .fiveHour

        let storedSpeechEvents = (defaults.object(forKey: Self.speechEventsKey) as? [String: Bool]) ?? [:]
        var se: [SpeechEvent: Bool] = [:]
        for event in SpeechEvent.allCases {
            se[event] = storedSpeechEvents[event.rawValue] ?? true
        }
        speechEvents = se

        // Load per-event flags; default each to a sensible value.
        let storedEvents = (defaults.object(forKey: Self.voiceEventsKey) as? [String: Bool]) ?? [:]
        var events: [VoiceEvent: Bool] = [:]
        for e in VoiceEvent.allCases {
            // Defaults: permission + danger + finished on, started off.
            let defaultOn: Bool = (e != .started)
            events[e] = storedEvents[e.rawValue] ?? defaultOn
        }
        voiceEvents = events

        // Reconcile login-item state with the stored pref. didSet
        // doesn't fire from init in Swift, so on first launch we need
        // to manually push the default `true` into SMAppService to
        // actually register the app. Idempotent on subsequent launches.
        applyStartAtLogin()
    }
}
