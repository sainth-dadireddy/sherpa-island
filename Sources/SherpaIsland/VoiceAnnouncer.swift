import Foundation
import AVFoundation

/// Speaks short notifications for key Claude events using the system voice.
///
/// Kept intentionally low-frequency and deduped so the buddy doesn't become
/// a chatterbox. All events check the user's preference before speaking.
@MainActor
final class VoiceAnnouncer {
    static let shared = VoiceAnnouncer()

    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenAt: [String: Date] = [:]
    private let minGapBetweenSameMessage: TimeInterval = 4

    private init() {}

    func speak(_ text: String, event: VoiceEvent, prefs: BuddyPreferences) {
        guard prefs.voiceAllows(event) else { return }

        // Debounce: don't repeat the same event-class within a short window.
        let key = event.rawValue
        if let last = lastSpokenAt[key],
           Date().timeIntervalSince(last) < minGapBetweenSameMessage {
            return
        }
        lastSpokenAt[key] = Date()

        let utterance = makeUtterance(text: text, prefs: prefs)
        synthesizer.speak(utterance)
    }

    /// Speak a test phrase without the dedupe gate. Used by the
    /// Settings voice picker so the user can sample voices quickly.
    func preview(_ text: String, prefs: BuddyPreferences) {
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(makeUtterance(text: text, prefs: prefs))
    }

    func stopAll() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func makeUtterance(text: String, prefs: BuddyPreferences) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        let rateMul = max(0.5, min(1.5, prefs.voiceRate))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(rateMul)
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.85
        let chosen = prefs.voiceIdentifier.isEmpty
            ? nil
            : AVSpeechSynthesisVoice(identifier: prefs.voiceIdentifier)
        utterance.voice = chosen
            ?? AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.en-US.Ava")
            ?? AVSpeechSynthesisVoice(language: "en-US")
        return utterance
    }
}
