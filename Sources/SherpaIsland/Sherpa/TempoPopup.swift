import SwiftUI
import Foundation
import AppKit
import AVFoundation

// MARK: - Run mode

enum TempoMode: String, CaseIterable, Identifiable {
    case day1 = "1 day"
    case day7 = "7 days"
    case day30 = "30 days"
    case month2 = "2 months"

    var id: String { rawValue }

    var args: [String] {
        switch self {
        case .day1:   return ["--days", "1"]
        case .day7:   return ["--days", "7"]
        case .day30:  return ["--days", "30"]
        case .month2: return ["--months", "2"]
        }
    }

    var icon: String {
        switch self {
        case .day1:   return "1.circle.fill"
        case .day7:   return "7.circle.fill"
        case .day30:  return "30.circle.fill"
        case .month2: return "calendar.circle.fill"
        }
    }
}

// MARK: - Result

struct TempoResult {
    let ticket: String
    let logged: Int
    let dup: Int
    let hol: Int
    let failed: Int
    let mode: String
    let rawOutput: String

    var summary: String {
        if failed > 0 { return "Failed \(failed) days on \(ticket)" }
        if logged == 0 { return "Nothing new — \(ticket) up to date" }
        return "Logged \(logged) day\(logged == 1 ? "" : "s") on \(ticket)"
    }

    static func parse(stdout: String, mode: String) -> TempoResult? {
        guard let line = stdout.components(separatedBy: .newlines)
            .last(where: { $0.hasPrefix("RESULT ") }) else { return nil }
        var dict: [String: String] = [:]
        for pair in line.dropFirst("RESULT ".count).components(separatedBy: " ") {
            let kv = pair.components(separatedBy: "=")
            if kv.count == 2 { dict[kv[0]] = kv[1] }
        }
        return TempoResult(
            ticket: dict["ticket"] ?? "?",
            logged: Int(dict["logged"] ?? "0") ?? 0,
            dup:    Int(dict["dup"]    ?? "0") ?? 0,
            hol:    Int(dict["hol"]    ?? "0") ?? 0,
            failed: Int(dict["failed"] ?? "0") ?? 0,
            mode: mode,
            rawOutput: stdout
        )
    }
}

// MARK: - Runner

@MainActor
final class TempoRunner: ObservableObject {
    @Published var isRunning = false
    @Published var lastResult: TempoResult?
    @Published var lastError: String?
    @Published var liveLog: String = ""

    func run(ticket: String, mode: TempoMode) async {
        isRunning = true
        lastError = nil
        liveLog = ""

        var args: [String] = ["--ticket", ticket]
        args.append(contentsOf: mode.args)

        do {
            let (stdout, stderr, code) = try await runShell(
                executable: NSHomeDirectory() + "/.claude/scripts/tempo_fill_week.sh",
                args: args
            )
            liveLog = stderr  // script logs to stderr
            if code == 0, let parsed = TempoResult.parse(stdout: stdout, mode: mode.rawValue) {
                lastResult = parsed
            } else if let parsed = TempoResult.parse(stdout: stdout, mode: mode.rawValue) {
                lastResult = parsed
                lastError = "exit \(code) — \(parsed.failed) failures"
            } else {
                lastError = "Script failed (exit \(code))"
            }
        } catch {
            lastError = error.localizedDescription
        }
        isRunning = false
    }

    func openLogInConsole() {
        let path = NSHomeDirectory() + "/Library/Logs/tempo_fill.log"
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func runShell(executable: String, args: [String]) async throws -> (String, String, Int32) {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = [executable] + args
                let out = Pipe(); let err = Pipe()
                p.standardOutput = out
                p.standardError  = err
                do {
                    try p.run()
                    p.waitUntilExit()
                    let so = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let se = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    cont.resume(returning: (so, se, p.terminationStatus))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - View

// Tempo brand palette + neutral pro base (slate/charcoal — no wallpaper bleed)
fileprivate let tempoBlue   = Color(red: 0.106, green: 0.310, blue: 0.749)  // #1B4FBF accent
fileprivate let tempoCyan   = Color(red: 0.25,  green: 0.55,  blue: 0.95)
fileprivate let bgPrimary   = Color(red: 0.165, green: 0.192, blue: 0.255)  // #2A3141 brighter slate
fileprivate let bgSecondary = Color(red: 0.204, green: 0.235, blue: 0.302)  // panel header
fileprivate let bgElev      = Color(red: 0.243, green: 0.275, blue: 0.345)  // input bg
fileprivate let textHi      = Color(red: 0.95,  green: 0.96,  blue: 0.98)
fileprivate let textMid     = Color(red: 0.72,  green: 0.75,  blue: 0.80)
fileprivate let textLow     = Color(red: 0.55,  green: 0.58,  blue: 0.64)

struct TempoPopupView: View {
    @StateObject private var runner = TempoRunner()
    @State private var ticket: String = "ECS-204373"
    @State private var selectedMode: TempoMode = .day7
    @State private var voiceOn: Bool = true
    @State private var showFullLog: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(tempoBlue.opacity(0.3))
            inputSection
            Divider().background(tempoBlue.opacity(0.15))
            modeSection
            Divider().background(tempoBlue.opacity(0.15))
            actionSection
            if let result = runner.lastResult {
                Divider().background(tempoBlue.opacity(0.15))
                resultSection(result)
            }
            if let err = runner.lastError {
                Divider().background(.red.opacity(0.3))
                errorSection(err)
            }
            if showFullLog && !runner.liveLog.isEmpty {
                Divider().background(tempoBlue.opacity(0.15))
                logSection
            }
            Spacer(minLength: 0)
        }
        .background(bgPrimary.ignoresSafeArea())
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(LinearGradient(colors: [tempoCyan, tempoBlue],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 32, height: 32)
                Image(systemName: "clock.badge.checkmark.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Tempo Worklog Filler")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(textHi)
                Text("8h/day · idempotent · auto-backfill")
                    .font(.system(size: 11))
                    .foregroundColor(textLow)
            }
            Spacer()
            Toggle(isOn: $voiceOn) {
                Image(systemName: voiceOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 12))
                    .foregroundColor(voiceOn ? tempoCyan : textLow)
            }
            .toggleStyle(.button)
            .tint(tempoBlue)
            .help("Voice announcement on completion")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(bgSecondary)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ticket")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(textMid)
            HStack(spacing: 10) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 13))
                    .foregroundColor(tempoCyan)
                TextField("e.g. ECS-204373", text: $ticket)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(textHi)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(bgElev)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
        .padding(16)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fill range")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(textMid)
            HStack(spacing: 8) {
                ForEach(TempoMode.allCases) { mode in
                    ModeButton(
                        mode: mode,
                        selected: selectedMode == mode,
                        action: { selectedMode = mode }
                    )
                }
            }
        }
        .padding(16)
    }

    private var actionSection: some View {
        HStack(spacing: 10) {
            Button {
                Task { await fillAction() }
            } label: {
                HStack(spacing: 6) {
                    if runner.isRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(runner.isRunning ? "Filling…" : "Fill Now")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(runner.isRunning || ticket.trimmingCharacters(in: .whitespaces).isEmpty)

            Button {
                runner.openLogInConsole()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text("View Log")
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private func resultSection(_ r: TempoResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: r.failed > 0 ? "exclamationmark.triangle.fill" :
                                    (r.logged > 0 ? "checkmark.circle.fill" : "info.circle.fill"))
                    .foregroundStyle(r.failed > 0 ? .red : (r.logged > 0 ? .green : .secondary))
                Text(r.summary)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button {
                    withAnimation { showFullLog.toggle() }
                } label: {
                    Text(showFullLog ? "Hide log" : "Show log")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            HStack(spacing: 14) {
                StatChip(label: "Logged", value: r.logged, color: .green)
                StatChip(label: "Skipped (dup)", value: r.dup, color: .blue)
                StatChip(label: "Holiday", value: r.hol, color: .orange)
                if r.failed > 0 {
                    StatChip(label: "Failed", value: r.failed, color: .red)
                }
            }
        }
        .padding(14)
    }

    private func errorSection(_ err: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            Text(err).font(.system(size: 11)).foregroundStyle(.red)
            Spacer()
        }
        .padding(14)
    }

    private var logSection: some View {
        ScrollView {
            Text(runner.liveLog)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 160)
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
        .padding(14)
    }

    // MARK: - Actions

    private func fillAction() async {
        let trimmed = ticket.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await runner.run(ticket: trimmed, mode: selectedMode)
        if voiceOn, let r = runner.lastResult {
            await speakAsync(r.summary)
        } else if voiceOn, let e = runner.lastError {
            await speakAsync("Tempo error: \(e)")
        }
    }

    private func speakAsync(_ text: String) async {
        TempoSpeech.shared.speak(text)
    }
}

@MainActor
final class TempoSpeech {
    static let shared = TempoSpeech()
    private let synth = AVSpeechSynthesizer()
    private init() {}
    func speak(_ text: String) {
        let utt = AVSpeechUtterance(string: text)
        utt.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.en-US.Zoe")
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utt.rate = AVSpeechUtteranceDefaultSpeechRate
        utt.volume = 0.85
        synth.speak(utt)
    }
}

// MARK: - Subviews

private struct ModeButton: View {
    let mode: TempoMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: mode.icon)
                    .font(.system(size: 18))
                Text(mode.rawValue)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected
                        ? LinearGradient(colors: [tempoCyan.opacity(0.35), tempoBlue.opacity(0.45)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.white.opacity(0.04), Color.white.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? tempoCyan : Color.white.opacity(0.1),
                            lineWidth: selected ? 1.5 : 0.5)
            )
            .foregroundColor(selected ? .white : .white.opacity(0.7))
        }
        .buttonStyle(.plain)
    }
}

private struct StatChip: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(value)").font(.system(size: 12, weight: .semibold))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Window controller (for menu-bar launch)

@MainActor
final class TempoPopupWindowController: NSWindowController, NSWindowDelegate {
    static let shared = TempoPopupWindowController()

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Tempo Worklog Filler"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        win.contentView = NSHostingView(rootView: TempoPopupView())
        win.minSize = NSSize(width: 460, height: 380)
        super.init(window: win)
        win.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        guard let win = window else { return }
        if !win.isVisible {
            if let screen = NSScreen.main {
                let f = screen.visibleFrame
                let w: CGFloat = 520, h: CGFloat = 480
                win.setFrame(NSRect(x: f.midX - w/2, y: f.midY - h/2, width: w, height: h), display: true)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    // Hide instead of releasing so subsequent show() reuses same window state
    func windowWillClose(_ notification: Notification) {
        // No-op; window will hide naturally
    }
}

#Preview { TempoPopupView() }
