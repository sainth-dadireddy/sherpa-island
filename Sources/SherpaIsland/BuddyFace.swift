import SwiftUI

// MARK: - User-pickable style + color

enum BuddyStyle: String, CaseIterable, Identifiable {
    case eyes
    case orb
    case bars
    case ghost
    case cat
    case bunny

    var id: String { rawValue }

    var label: String {
        switch self {
        case .eyes:  return "Eyes"
        case .orb:   return "Orb"
        case .bars:  return "Bars"
        case .ghost: return "Pulse"
        case .cat:   return "Wave"
        case .bunny: return "Spark"
        }
    }
}

enum BuddyColor: String, CaseIterable, Identifiable {
    case orange
    case blue
    case green
    case purple
    case pink
    case cyan

    var id: String { rawValue }

    var label: String {
        switch self {
        case .orange: return "Claude"
        case .blue:   return "Blue"
        case .green:  return "Green"
        case .purple: return "Purple"
        case .pink:   return "Pink"
        case .cyan:   return "Cyan"
        }
    }

    var base: Color {
        switch self {
        case .orange: return Color(red: 0.80, green: 0.47, blue: 0.36) // #CC785C
        case .blue:   return Color(red: 0.35, green: 0.72, blue: 1.00) // #5AB8FF
        case .green:  return Color(red: 0.44, green: 0.83, blue: 0.42) // #70D46B
        case .purple: return Color(red: 0.66, green: 0.55, blue: 0.91) // #A88BE8
        case .pink:   return Color(red: 0.94, green: 0.38, blue: 0.57) // #EF6192
        case .cyan:   return Color(red: 0.30, green: 0.81, blue: 0.88) // #4DD0E1
        }
    }

    var glow: Color { base.opacity(0.85) }
}

// MARK: - BuddyFace dispatcher

struct BuddyFace: View {
    enum Mode: Equatable {
        case sleeping
        case idle
        case active
        case curious   // permission request / alert
        case content   // happy / done
        case focused   // concentrated editing
        case shocked   // dangerous action
    }

    let mode: Mode
    var size: CGFloat = 8
    var colorOverride: BuddyColor? = nil
    /// Force a specific style instead of reading from prefs. Used by
    /// the Settings gallery so each chip can animate its own style.
    var styleOverride: BuddyStyle? = nil

    @EnvironmentObject private var prefs: BuddyPreferences

    private var effectiveColor: BuddyColor { colorOverride ?? prefs.color }
    private var effectiveStyle: BuddyStyle { styleOverride ?? prefs.style }

    var body: some View {
        Group {
            switch effectiveStyle {
            case .eyes:  EyesBuddy(mode: mode, size: size, color: effectiveColor)
            case .orb:   OrbBuddy(mode: mode, size: size, color: effectiveColor)
            case .bars:  BarsBuddy(mode: mode, size: size, color: effectiveColor)
            case .ghost: PulseBuddy(mode: mode, size: size, color: effectiveColor)
            case .cat:   WaveBuddy(mode: mode, size: size, color: effectiveColor)
            case .bunny: SparkBuddy(mode: mode, size: size, color: effectiveColor)
            }
        }
        .id(effectiveStyle)
    }
}

// MARK: - Shared helpers

/// Shared danger-red for the shocked state, overriding the user's accent.
private let shockColor = Color(red: 0.92, green: 0.28, blue: 0.22)

/// Standard body-color ramp based on mode. All character buddies use the
/// user's picked accent color; the ramp just dims it based on mood.
private func bodyColor(_ mode: BuddyFace.Mode, _ color: BuddyColor) -> Color {
    switch mode {
    case .active, .curious: return color.base
    case .focused:          return color.base.opacity(0.95)
    case .shocked:          return shockColor
    case .content:          return color.base.opacity(0.85)
    case .idle:             return color.base.opacity(0.9)
    case .sleeping:         return color.base.opacity(0.4)
    }
}

/// Mode-aware blink loop, shared by all character buddies.
///
/// Content mode holds the closed pose ~2× longer — reads as a happy squint
/// rather than a functional blink.
@MainActor
private func runBlinkLoop(
    mode: BuddyFace.Mode,
    setBlink: @escaping (Bool) -> Void
) async {
    // Shocked buddies don't blink — their eyes are wide with alarm.
    if mode == .shocked {
        setBlink(false)
        return
    }
    while !Task.isCancelled {
        let (mean, jitter): (UInt64, UInt64) = {
            switch mode {
            case .curious:  return (1_200_000_000, 600_000_000)
            case .active:   return (3_800_000_000, 1_400_000_000)
            case .focused:  return (4_800_000_000, 1_200_000_000)   // calm concentration
            case .content:  return (5_200_000_000, 1_800_000_000)
            case .idle:     return (4_200_000_000, 1_500_000_000)
            case .sleeping: return (5_000_000_000, 0)
            case .shocked:  return (9_000_000_000, 0)  // unreachable
            }
        }()
        let holdDur: UInt64 = mode == .content ? 260_000_000 : 130_000_000

        let delay = mean &+ UInt64.random(in: 0..<max(jitter, 1))
        try? await Task.sleep(nanoseconds: delay)
        if Task.isCancelled { return }
        withAnimation(.easeIn(duration: 0.09)) { setBlink(true) }
        try? await Task.sleep(nanoseconds: holdDur)
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.12)) { setBlink(false) }
    }
}

// MARK: - Eyes (with look-around gaze)

private struct EyesBuddy: View {
    let mode: BuddyFace.Mode
    let size: CGFloat
    let color: BuddyColor

    @State private var blink = false
    @State private var pulse: CGFloat = 1.0
    @State private var breathe: CGFloat = 0
    @State private var gaze: CGSize = .zero
    @State private var blinkTask: Task<Void, Never>?
    @State private var gazeTask: Task<Void, Never>?

    private var eyeColor: Color {
        switch mode {
        case .shocked:          return shockColor
        case .active, .curious: return color.base
        case .focused:          return color.base.opacity(0.95)
        case .content:          return color.base.opacity(0.85)
        case .idle:             return color.base.opacity(0.8)
        case .sleeping:         return color.base.opacity(0.3)
        }
    }

    private var glowColor: Color {
        switch mode {
        case .shocked:  return shockColor.opacity(0.9)
        case .active:   return color.glow
        case .curious:  return color.glow.opacity(0.7)
        case .focused:  return color.glow.opacity(0.3)
        case .content:  return color.glow.opacity(0.35)
        case .idle:     return color.glow.opacity(0.4)
        case .sleeping: return .clear
        }
    }

    private var baseSize: CGFloat {
        switch mode {
        case .shocked: return size * 1.1    // subtle widening — red is the real tell
        case .curious: return size * 1.15
        case .active:  return size * 1.05
        case .focused: return size * 0.92   // narrowed focus
        default:       return size
        }
    }

    var body: some View {
        HStack(spacing: baseSize * 0.85) {
            eye
            eye
        }
        .scaleEffect(pulse)
        .offset(x: gaze.width, y: breathe + gaze.height)
        .onAppear { start() }
        .onDisappear {
            blinkTask?.cancel()
            gazeTask?.cancel()
        }
        .onChange(of: mode) { _, _ in start() }
    }

    @ViewBuilder
    private var eye: some View {
        if mode == .sleeping {
            Capsule()
                .fill(eyeColor)
                .frame(width: baseSize, height: max(1.5, baseSize * 0.2))
        } else {
            // Tighter glow radius in shocked mode so the red halo doesn't
            // overflow the notch's vertical extent.
            let glowRadius: CGFloat = mode == .shocked
                ? baseSize * 0.22
                : baseSize * 0.55
            Circle()
                .fill(eyeColor)
                .frame(
                    width: baseSize,
                    height: blink ? max(1.5, baseSize * 0.15) : baseSize
                )
                .shadow(color: glowColor, radius: glowRadius)
        }
    }

    private func start() {
        blinkTask?.cancel()
        gazeTask?.cancel()
        pulse = 1.0
        breathe = 0
        withAnimation(.easeOut(duration: 0.25)) { gaze = .zero }

        guard mode != .sleeping else { return }

        switch mode {
        case .active:
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = 1.1
            }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                breathe = -0.8
            }
        case .curious:
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                pulse = 1.06
            }
        case .focused:
            // Calm, steady — no breathing, subtle slow pulse
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = 1.03
            }
        case .shocked:
            // Hold still, wide eyes, very subtle scale pop so we don't
            // overflow the notch height.
            withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
                pulse = 1.05
            }
        case .content:
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                breathe = -0.5
            }
        case .idle:
            // Subtle "alive" idle: slow breathe + gentle pulse so the
            // buddy doesn't look frozen. Gaze loop below still randomly
            // glances around.
            withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) {
                breathe = -0.4
            }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                pulse = 1.02
            }
        case .sleeping:
            break
        }

        blinkTask = Task { @MainActor in
            await runBlinkLoop(mode: mode) { self.blink = $0 }
        }

        // Occasional look-around glance.
        gazeTask = Task { @MainActor in
            while !Task.isCancelled {
                let waitNs: UInt64 = {
                    switch mode {
                    case .curious: return UInt64.random(in: 300_000_000 ... 800_000_000)
                    case .active:  return UInt64.random(in: 2_500_000_000 ... 5_500_000_000)
                    case .content: return UInt64.random(in: 5_000_000_000 ... 9_000_000_000)
                    default:       return UInt64.random(in: 3_500_000_000 ... 7_000_000_000)
                    }
                }()
                try? await Task.sleep(nanoseconds: waitNs)
                if Task.isCancelled { return }

                let angle = Double.random(in: 0 ... 2 * .pi)
                let dist = size * 0.18
                let dx = CGFloat(cos(angle)) * dist
                let dy = CGFloat(sin(angle)) * dist * 0.55
                withAnimation(.easeOut(duration: 0.2)) {
                    gaze = CGSize(width: dx, height: dy)
                }
                try? await Task.sleep(
                    nanoseconds: UInt64.random(in: 400_000_000 ... 900_000_000)
                )
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    gaze = .zero
                }
            }
        }
    }
}

// MARK: - Orb (inner spark + sonar ring)

private struct OrbBuddy: View {
    let mode: BuddyFace.Mode
    let size: CGFloat
    let color: BuddyColor

    @State private var pulse: CGFloat = 1.0
    @State private var breathe: CGFloat = 0
    @State private var sparkPulse: CGFloat = 1.0
    @State private var sonarScale: CGFloat = 0
    @State private var sonarOpacity: Double = 0
    @State private var sonarTask: Task<Void, Never>?

    private var fillColor: Color {
        switch mode {
        case .shocked:          return shockColor
        case .active, .curious: return color.base
        case .focused:          return color.base.opacity(0.88)
        case .content:          return color.base.opacity(0.78)
        case .idle:             return color.base.opacity(0.8)
        case .sleeping:         return color.base.opacity(0.25)
        }
    }

    private var glowColor: Color {
        switch mode {
        case .shocked: return shockColor.opacity(0.9)
        case .active:  return color.glow
        case .curious: return color.glow.opacity(0.65)
        case .focused: return color.glow.opacity(0.4)
        case .content: return color.glow.opacity(0.35)
        default:       return .clear
        }
    }

    var body: some View {
        let orbSize = size * 2.1

        ZStack {
            // Expanding sonar ring, only visible in active mode.
            if mode == .active {
                Circle()
                    .strokeBorder(color.base.opacity(0.8), lineWidth: 1.2)
                    .frame(width: orbSize, height: orbSize)
                    .scaleEffect(sonarScale)
                    .opacity(sonarOpacity)
            }

            // Main orb body.
            Circle()
                .fill(fillColor)
                .frame(width: orbSize, height: orbSize)
                .overlay(
                    // Inner highlight — fixed gradient for depth.
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.38), .clear],
                                center: UnitPoint(x: 0.3, y: 0.28),
                                startRadius: 0,
                                endRadius: orbSize * 0.55
                            )
                        )
                        .blendMode(.plusLighter)
                )
                .shadow(color: glowColor, radius: orbSize * 0.5)

            // Inner spark: a smaller bright dot that pulses independently
            // of the outer pulse, giving the orb a second heartbeat.
            if mode != .sleeping {
                Circle()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: orbSize * 0.18, height: orbSize * 0.18)
                    .offset(x: -orbSize * 0.08, y: -orbSize * 0.1)
                    .scaleEffect(sparkPulse)
                    .blur(radius: 0.5)
            }
        }
        .scaleEffect(pulse)
        .offset(y: breathe)
        .onAppear { start() }
        .onDisappear { sonarTask?.cancel() }
        .onChange(of: mode) { _, _ in start() }
    }

    private func start() {
        sonarTask?.cancel()
        pulse = 1.0
        breathe = 0
        sparkPulse = 1.0
        sonarScale = 0
        sonarOpacity = 0

        switch mode {
        case .active:
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = 1.13
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                breathe = -0.6
            }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                sparkPulse = 1.3
            }
            sonarTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_400_000_000)
                    if Task.isCancelled { return }
                    sonarScale = 0.95
                    sonarOpacity = 0.7
                    withAnimation(.easeOut(duration: 1.6)) {
                        sonarScale = 2.2
                        sonarOpacity = 0
                    }
                }
            }
        case .curious:
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                pulse = 1.08
            }
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                sparkPulse = 1.4
            }
        case .focused:
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulse = 1.05
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                sparkPulse = 1.1
            }
        case .shocked:
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                pulse = 1.1
            }
            sparkPulse = 1.25
        case .content:
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                pulse = 1.04
            }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                sparkPulse = 1.15
            }
        case .idle:
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                sparkPulse = 1.2
            }
        case .sleeping:
            break
        }
    }
}

// MARK: - Bars (audio waveform)

private struct BarsBuddy: View {
    let mode: BuddyFace.Mode
    let size: CGFloat
    let color: BuddyColor

    private var barColor: Color {
        switch mode {
        case .shocked:          return shockColor
        case .active, .curious: return color.base
        case .focused:          return color.base.opacity(0.9)
        case .content:          return color.base.opacity(0.80)
        case .idle:             return color.base.opacity(0.8)
        case .sleeping:         return color.base.opacity(0.3)
        }
    }

    private var amplitude: CGFloat {
        switch mode {
        case .shocked:  return 0.45
        case .active:   return 0.55
        case .curious:  return 0.48
        case .focused:  return 0.22
        case .content:  return 0.18
        case .idle:     return 0.12
        case .sleeping: return 0
        }
    }

    private var speed: Double {
        switch mode {
        case .shocked:  return 9.0
        case .active:   return 4.5
        case .curious:  return 6.5
        case .focused:  return 1.8
        case .content:  return 1.6
        case .idle:     return 1.0
        case .sleeping: return 0
        }
    }

    var body: some View {
        let barWidth = size * 0.38
        let baseH = size * 0.95
        let maxH = baseH * (1 + amplitude)
        let minH = max(size * 0.25, baseH * (1 - amplitude))

        TimelineView(
            .animation(minimumInterval: 1.0 / 60, paused: mode == .sleeping)
        ) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: size * 0.32) {
                ForEach(0..<4, id: \.self) { i in
                    let phase = Double(i) * 0.9
                    let wave = sin(t * speed + phase)
                    let h = baseH + CGFloat(wave) * amplitude * baseH
                    Capsule()
                        .fill(barColor)
                        .frame(width: barWidth, height: clamp(h, min: minH, max: maxH))
                }
            }
        }
        .frame(height: maxH)
    }

    private func clamp(_ x: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat {
        Swift.min(Swift.max(x, lo), hi)
    }
}

// MARK: - Pulse (concentric rings, rate + intensity track mode)

private struct PulseBuddy: View {
    let mode: BuddyFace.Mode
    let size: CGFloat
    let color: BuddyColor

    private var fillColor: Color {
        switch mode {
        case .shocked:                       return shockColor
        case .active, .curious:              return color.base
        case .focused, .content, .idle:      return color.base.opacity(0.9)
        case .sleeping:                      return color.base.opacity(0.4)
        }
    }

    /// Higher = faster rings expand outward.
    private var rate: Double {
        switch mode {
        case .shocked:  return 3.0
        case .curious:  return 2.2
        case .active:   return 1.5
        case .focused:  return 0.8
        case .content:  return 1.0
        case .idle:     return 0.5
        case .sleeping: return 0.15
        }
    }

    private var ringCount: Int { mode == .sleeping ? 1 : 3 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<ringCount, id: \.self) { i in
                    let phase = ((t * rate) + Double(i) / Double(ringCount))
                        .truncatingRemainder(dividingBy: 1)
                    let scale = 0.35 + 1.55 * CGFloat(phase)
                    Circle()
                        .stroke(fillColor.opacity(1.0 - phase), lineWidth: 1.4)
                        .frame(width: size * scale * 1.6, height: size * scale * 1.6)
                }
                // Core
                Circle()
                    .fill(fillColor)
                    .frame(width: size * 0.5, height: size * 0.5)
                    .shadow(
                        color: color.glow.opacity(mode == .sleeping ? 0 : 0.6),
                        radius: size * 0.35
                    )
            }
            .frame(width: size * 2.4, height: size * 2.4)
        }
    }
}

// MARK: - Wave (sine line, frequency + amplitude track mode)

private struct WaveBuddy: View {
    let mode: BuddyFace.Mode
    let size: CGFloat
    let color: BuddyColor

    private var lineColor: Color {
        switch mode {
        case .shocked:                       return shockColor
        case .active, .curious:              return color.base
        case .focused, .content, .idle:      return color.base.opacity(0.9)
        case .sleeping:                      return color.base.opacity(0.4)
        }
    }

    /// Phase advance rate (Hz)
    private var freq: Double {
        switch mode {
        case .shocked:  return 3.5
        case .curious:  return 2.4
        case .active:   return 1.8
        case .focused:  return 0.9
        case .content:  return 1.1
        case .idle:     return 0.6
        case .sleeping: return 0.18
        }
    }

    private var amplitude: CGFloat {
        switch mode {
        case .shocked:  return 0.85
        case .curious:  return 0.7
        case .active:   return 0.6
        case .focused:  return 0.32
        case .content:  return 0.3
        case .idle:     return 0.22
        case .sleeping: return 0.08
        }
    }

    private var cycles: Double {
        switch mode {
        case .shocked: return 4.0
        case .curious: return 3.5
        case .active:  return 3.0
        case .focused: return 2.2
        case .content: return 2.4
        case .idle:    return 1.8
        case .sleeping:return 1.2
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                var path = Path()
                let mid = sz.height / 2
                let amp = sz.height * 0.45 * amplitude
                let steps = Int(sz.width)
                let phase = CGFloat(t * freq * 2.0 * .pi)
                for i in 0...steps {
                    let x = CGFloat(i)
                    let y = mid + sin((x / sz.width) * CGFloat(cycles) * .pi + phase) * amp
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else      { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(path, with: .color(lineColor), lineWidth: max(1.5, size * 0.18))
            }
            .frame(width: size * 2.8, height: size * 1.5)
        }
    }
}

// MARK: - Spark (orbiting particles + radiant core)

private struct SparkBuddy: View {
    let mode: BuddyFace.Mode
    let size: CGFloat
    let color: BuddyColor

    private var fillColor: Color {
        switch mode {
        case .shocked:                       return shockColor
        case .active, .curious:              return color.base
        case .focused, .content, .idle:      return color.base.opacity(0.9)
        case .sleeping:                      return color.base.opacity(0.4)
        }
    }

    private var particleCount: Int {
        switch mode {
        case .shocked: return 16
        case .curious: return 12
        case .active:  return 10
        case .focused: return 6
        case .content: return 8
        case .idle:    return 5
        case .sleeping: return 0
        }
    }

    private var speed: Double {
        switch mode {
        case .shocked: return 1.6
        case .curious: return 1.3
        case .active:  return 1.0
        case .focused: return 0.6
        case .content: return 0.7
        case .idle:    return 0.4
        case .sleeping: return 0.1
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, sz in
                let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let maxR = sz.width * 0.48
                for i in 0..<particleCount {
                    let lifeT = (t * speed + Double(i) * 0.18)
                        .truncatingRemainder(dividingBy: 1.6) / 1.6
                    let cycle = CGFloat(lifeT)
                    let angle = (Double(i) / Double(max(particleCount, 1))) * 2 * .pi
                        + t * 0.4
                    let r = maxR * cycle
                    let x = center.x + CGFloat(cos(angle)) * r
                    let y = center.y + CGFloat(sin(angle)) * r
                    let alpha = 1.0 - lifeT
                    let dot = CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)
                    ctx.fill(Path(ellipseIn: dot), with: .color(fillColor.opacity(alpha)))
                }
                // Core
                let core = CGRect(
                    x: center.x - size * 0.22,
                    y: center.y - size * 0.22,
                    width: size * 0.44,
                    height: size * 0.44
                )
                ctx.fill(Path(ellipseIn: core), with: .color(fillColor))
            }
            .frame(width: size * 2.4, height: size * 2.4)
        }
    }
}
