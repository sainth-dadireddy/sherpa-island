import Cocoa
import SwiftUI
import Combine

// MARK: - HUD Type Definition
enum HUDType: Equatable {
    case volume
    case brightness
    case backlight
}

// MARK: - HUD Interceptor
@MainActor
class HUDInterceptor: NSObject, ObservableObject {
    @Published var activeHUD: HUDType?
    @Published var hudValue: Double = 0.0
    @Published var hudVisible: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hideTimer: Timer?
    private var globalMonitor: Any?

    private let hideDelay: TimeInterval = 1.5

    override init() {
        super.init()
        setupEventTap()
        setupGlobalEventMonitor()
    }

    deinit {
        stopEventTap()
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        hideTimer?.invalidate()
    }

    // MARK: - CGEventTap Setup
    private func setupEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.systemDefined.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let interceptor = Refcon.unwrap(refcon) as? HUDInterceptor else {
                    return Unmanaged.passRetained(event)
                }

                return interceptor.handleCGEvent(type, event: event)
            },
            userInfo: Refcon.wrap(self)
        ) else {
            NSLog("Failed to create event tap for HUDInterceptor")
            return
        }

        self.eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - CGEvent Handler
    private func handleCGEvent(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .systemDefined else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = (event.data1 >> 16) & 0xffff
        let keyFlags = event.data1 & 0xffff
        let keyDown = (keyFlags & 0x100) == 0

        guard keyDown else {
            return Unmanaged.passRetained(event)
        }

        switch keyCode {
        case NX_KEYTYPE_SOUND_UP, NX_KEYTYPE_SOUND_DOWN, NX_KEYTYPE_MUTE:
            handleVolumeKey(keyCode, event: event)
            return nil // Suppress macOS native HUD

        case NX_KEYTYPE_BRIGHTNESS_UP, NX_KEYTYPE_BRIGHTNESS_DOWN:
            handleBrightnessKey(keyCode, event: event)
            return nil // Suppress macOS native HUD

        case NX_KEYTYPE_ILLUMINATION_UP, NX_KEYTYPE_ILLUMINATION_DOWN:
            handleBacklightKey(keyCode, event: event)
            return nil // Suppress macOS native HUD

        default:
            return Unmanaged.passRetained(event)
        }
    }

    private func handleVolumeKey(_ keyCode: UInt32, event: CGEvent) {
        activeHUD = .volume
        updateVolumeHUD(keyCode: keyCode)
        showHUD()
    }

    private func handleBrightnessKey(_ keyCode: UInt32, event: CGEvent) {
        activeHUD = .brightness
        updateBrightnessHUD(keyCode: keyCode)
        showHUD()
    }

    private func handleBacklightKey(_ keyCode: UInt32, event: CGEvent) {
        activeHUD = .backlight
        updateBacklightHUD(keyCode: keyCode)
        showHUD()
    }

    // MARK: - Volume Control
    private func updateVolumeHUD(keyCode: UInt32) {
        let audioEngine = AudioEngineProxy.shared
        let currentVolume = audioEngine.currentVolume()

        let newVolume: Float
        switch keyCode {
        case NX_KEYTYPE_SOUND_UP:
            newVolume = min(currentVolume + 0.0625, 1.0)
        case NX_KEYTYPE_SOUND_DOWN:
            newVolume = max(currentVolume - 0.0625, 0.0)
        case NX_KEYTYPE_MUTE:
            newVolume = audioEngine.isMuted() ? currentVolume : 0.0
        default:
            newVolume = currentVolume
        }

        audioEngine.setVolume(newVolume)
        hudValue = Double(newVolume) * 100.0
    }

    // MARK: - Brightness Control
    private func updateBrightnessHUD(keyCode: UInt32) {
        let brightnessProxy = BrightnessProxy.shared
        let currentBrightness = brightnessProxy.currentBrightness()

        let newBrightness: Float
        switch keyCode {
        case NX_KEYTYPE_BRIGHTNESS_UP:
            newBrightness = min(currentBrightness + 0.0625, 1.0)
        case NX_KEYTYPE_BRIGHTNESS_DOWN:
            newBrightness = max(currentBrightness - 0.0625, 0.0)
        default:
            newBrightness = currentBrightness
        }

        brightnessProxy.setBrightness(newBrightness)
        hudValue = Double(newBrightness) * 100.0
    }

    // MARK: - Backlight Control
    private func updateBacklightHUD(keyCode: UInt32) {
        let backlightProxy = BacklightProxy.shared
        let currentBacklight = backlightProxy.currentLevel()

        let newBacklight: Float
        switch keyCode {
        case NX_KEYTYPE_ILLUMINATION_UP:
            newBacklight = min(currentBacklight + 0.1, 1.0)
        case NX_KEYTYPE_ILLUMINATION_DOWN:
            newBacklight = max(currentBacklight - 0.1, 0.0)
        default:
            newBacklight = currentBacklight
        }

        backlightProxy.setLevel(newBacklight)
        hudValue = Double(newBacklight) * 100.0
    }

    // MARK: - Global Event Monitor (Fallback)
    private func setupGlobalEventMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard let self = self else { return }
            Task { @MainActor in
                let keyCode = UInt32((event.data1 >> 16) & 0xffff)
                let keyFlags = event.data1 & 0xffff
                let keyDown = (keyFlags & 0x100) == 0

                guard keyDown else { return }

                switch keyCode {
                case NX_KEYTYPE_SOUND_UP, NX_KEYTYPE_SOUND_DOWN, NX_KEYTYPE_MUTE:
                    self.activeHUD = .volume
                    self.updateVolumeHUD(keyCode: keyCode)
                    self.showHUD()

                case NX_KEYTYPE_BRIGHTNESS_UP, NX_KEYTYPE_BRIGHTNESS_DOWN:
                    self.activeHUD = .brightness
                    self.updateBrightnessHUD(keyCode: keyCode)
                    self.showHUD()

                case NX_KEYTYPE_ILLUMINATION_UP, NX_KEYTYPE_ILLUMINATION_DOWN:
                    self.activeHUD = .backlight
                    self.updateBacklightHUD(keyCode: keyCode)
                    self.showHUD()

                default:
                    break
                }
            }
        }
    }

    // MARK: - HUD Visibility Control
    private func showHUD() {
        hideTimer?.invalidate()
        hudVisible = true

        hideTimer = Timer.scheduledTimer(withTimeInterval: hideDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.hudVisible = false
                self?.activeHUD = nil
            }
        }
    }
}

// MARK: - Helper: Refcon Wrapper
private struct Refcon {
    static func wrap<T: AnyObject>(_ object: T) -> UnsafeMutableRawPointer {
        let retained = Unmanaged.passRetained(object)
        return retained.toOpaque()
    }

    static func unwrap(_ pointer: UnsafeMutableRawPointer?) -> AnyObject? {
        guard let pointer = pointer else { return nil }
        let unmanaged = Unmanaged<AnyObject>.fromOpaque(pointer)
        return unmanaged.takeUnretainedValue()
    }
}

// MARK: - Audio Engine Proxy
class AudioEngineProxy {
    static let shared = AudioEngineProxy()

    private init() {}

    func currentVolume() -> Float {
        var volume: Float = 0.5
        // TODO: Query actual system volume via AVAudioSession or IOKit
        return volume
    }

    func setVolume(_ value: Float) {
        // TODO: Set system volume via IOKit/CoreAudio
    }

    func isMuted() -> Bool {
        // TODO: Query mute state
        return false
    }
}

// MARK: - Brightness Proxy
class BrightnessProxy {
    static let shared = BrightnessProxy()

    private init() {}

    func currentBrightness() -> Float {
        // Query via IOKit displays
        return 0.5
    }

    func setBrightness(_ value: Float) {
        // Set via IOKit displays
    }
}

// MARK: - Backlight Proxy
class BacklightProxy {
    static let shared = BacklightProxy()

    private init() {}

    func currentLevel() -> Float {
        // Query keyboard backlight via IOKit
        return 0.5
    }

    func setLevel(_ value: Float) {
        // Set keyboard backlight
    }
}

// MARK: - SwiftUI HUD Overlay View
struct HUDOverlayView: View {
    @ObservedObject var interceptor: HUDInterceptor

    var body: some View {
        if interceptor.hudVisible, let hudType = interceptor.activeHUD {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: iconForHUDType(hudType))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background bar
                            Capsule()
                                .fill(Color.white.opacity(0.2))

                            // Progress bar
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            .white.opacity(0.6),
                                            .white.opacity(0.4)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * CGFloat(interceptor.hudValue / 100.0))
                        }
                    }
                    .frame(height: 6)

                    Text("\(Int(interceptor.hudValue))")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 35, alignment: .trailing)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .frame(width: 240)
            .background(
                ZStack {
                    // Liquid Glass effect
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.black.opacity(0.3),
                                    Color.black.opacity(0.2)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .backdropBlur(radius: 10)
            )
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 4)
            .position(x: NSScreen.main?.frame.midX ?? 512, y: 60)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: interceptor.hudVisible)
        }
    }

    private func iconForHUDType(_ type: HUDType) -> String {
        switch type {
        case .volume:
            return "speaker.wave.3"
        case .brightness:
            return "sun.max"
        case .backlight:
            return "keyboard.fill"
        }
    }
}

// MARK: - Backdrop Blur Modifier
struct BackdropBlurModifier: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: 0)
        }
    }
}

extension View {
    func backdropBlur(radius: CGFloat) -> some View {
        modifier(BackdropBlurModifier(radius: radius))
    }
}

// MARK: - Constants (NX_KEYTYPE_*)
private let NX_KEYTYPE_SOUND_UP: UInt32 = 16
private let NX_KEYTYPE_SOUND_DOWN: UInt32 = 17
private let NX_KEYTYPE_MUTE: UInt32 = 20
private let NX_KEYTYPE_BRIGHTNESS_UP: UInt32 = 2
private let NX_KEYTYPE_BRIGHTNESS_DOWN: UInt32 = 1
private let NX_KEYTYPE_ILLUMINATION_UP: UInt32 = 113
private let NX_KEYTYPE_ILLUMINATION_DOWN: UInt32 = 112
