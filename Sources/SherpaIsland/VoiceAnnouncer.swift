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
        utterance.voice = resolveVoice(identifier: prefs.voiceIdentifier)
        return utterance
    }

    /// Voice resolution chain:
    ///   1. The explicit identifier the user picked (if set + installed)
    ///   2. Premium Zoe (warmest of the downloadable Apple voices)
    ///   3. Any premium-quality English voice the system has
    ///   4. Premium Ava (legacy default)
    ///   5. Any en-US voice
    static func resolveVoice(identifier: String) -> AVSpeechSynthesisVoice? {
        if !identifier.isEmpty,
           let exact = AVSpeechSynthesisVoice(identifier: identifier) {
            return exact
        }
        if let zoe = AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.en-US.Zoe") {
            return zoe
        }
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let premium = voices.first(where: {
            $0.quality == .premium && $0.language.hasPrefix("en")
        }) {
            return premium
        }
        return AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.en-US.Ava")
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    func resolveVoice(identifier: String) -> AVSpeechSynthesisVoice? {
        Self.resolveVoice(identifier: identifier)
    }
}
