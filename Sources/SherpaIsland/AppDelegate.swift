import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NotchWindow?
    private var onboardingWindow: OnboardingWindow?
    private let monitor = ClaudeMonitor()
    private let hookBridge = HookBridge()
    private let preferences = BuddyPreferences()
    private let heatmap = HeatmapAggregator()
    private let usage = UsageAggregator()
    private let speechController = SpeechController()
    private let updateChecker = UpdateChecker()
    private let hotkeys = GlobalHotkeys()
    private var mouseMonitor: MouseMonitor?

    // Sherpa Island v0.2 additions
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    /// UserDefaults key — set to `true` after the onboarding sequence
    /// completes so future launches skip it.
    private static let onboardingCompletedKey = "onboardingCompleted"

    func applicationDidFinishLaunching(_ notification: Notification) {
        HookInstaller.installIfNeeded()
        hookBridge.start()

        // Always start the regular notch window underneath the intro —
        // the onboarding overlay ends by fading out its backdrop to
        // reveal the notch in its final position, which means the notch
        // needs to already be there.
        startNotchWindow()
        updateChecker.startPeriodicChecks()
        usage.startPeriodicRefresh()
        setupHotkeys()
        setupStatusItem()

        // Re-check accessibility whenever the app gains focus. After the
        // user grants permission in System Settings and switches back, the
        // banner should clear without waiting for the 2s poll tick or a
        // relaunch.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hotkeys.recheckAccessibility()
            }
        }

        // Force the onboarding on every launch when the debug env var
        // is set (useful for iterating on the intro animation without
        // blowing away UserDefaults).
        let forceIntro = ProcessInfo.processInfo.environment["SHERPA_ISLAND_FORCE_ONBOARDING"] != nil
        let alreadyOnboarded = UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey)
        if forceIntro || !alreadyOnboarded {
            showOnboarding()
        }
    }

    private func startNotchWindow() {
        // Derive notch geometry once here so both the window and the
        // mouse monitor use the same values.
        let (nw, nh) = Self.notchGeometry()
        let mm = MouseMonitor(notchWidth: nw, notchHeight: nh)
        self.mouseMonitor = mm

        window = NotchWindow(
            monitor: monitor,
            hookBridge: hookBridge,
            preferences: preferences,
            heatmap: heatmap,
            usage: usage,
            mouseMonitor: mm,
            speechController: speechController,
            updateChecker: updateChecker,
            hotkeys: hotkeys
        )
        window?.show()
        monitor.start()
        mm.start()
    }

    private func showOnboarding() {
        let (nw, nh) = Self.notchGeometry()
        let window = OnboardingWindow(
            preferences: preferences,
            notchWidth: nw,
            notchHeight: nh
        ) { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey)
            self.onboardingWindow?.orderOut(nil)
            self.onboardingWindow = nil
        }
        self.onboardingWindow = window
        window.orderFront(nil)
    }

    private func setupHotkeys() {
        hotkeys.onAllow = { [weak self] in
            guard let perm = self?.hookBridge.pendingPermission else { return }
            self?.hookBridge.allow(perm)
        }
        hotkeys.onDeny = { [weak self] in
            guard let perm = self?.hookBridge.pendingPermission else { return }
            self?.hookBridge.deny(perm)
        }
        hotkeys.onToggle = { [weak self] in
            self?.hotkeys.toggleCount += 1
        }
        hotkeys.start()
    }

    // MARK: - Sherpa Island v0.2: Menubar + Settings window

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "mountain.2.fill", accessibilityDescription: "Sherpa Island")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Sherpa Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Tempo Worklog…", action: #selector(openTempo), keyEquivalent: "t").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Sherpa Island", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")

        item.menu = menu
        self.statusItem = item
    }

    @objc private func openTempo() {
        TempoPopupWindowController.shared.show()
    }

    @objc private func openSettings() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: SettingsViewV2())
        let win = NSWindow(contentViewController: host)
        win.title = "Sherpa Island Settings"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 500, height: 400))
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = win
    }

    private static func notchGeometry() -> (width: CGFloat, height: CGFloat) {
        guard let screen = NSScreen.main else { return (200, 32) }
        let nh: CGFloat = screen.safeAreaInsets.top > 0
            ? screen.safeAreaInsets.top
            : 32
        var nw: CGFloat = 200
        if let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let derived = screen.frame.width - leftArea.width - rightArea.width
            if derived > 40 {
                nw = derived
            }
        }
        return (nw, nh)
    }
}
