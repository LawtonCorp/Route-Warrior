import AVFoundation
import Foundation

/// Something that can say a callout. The drive guide talks to this so
/// tests can listen without a speaker.
@MainActor
protocol GuidanceSpeaking: AnyObject {
    func speak(_ text: String)
}

/// Spoken turn-by-turn (D-052) through the system voice. The audio
/// session is a voice prompt that ducks whatever is playing — music
/// keeps going, quieter, under the callout — and releases the ducking
/// the moment the sentence ends. With CarPlay or Bluetooth connected the
/// phone's audio is the car's, so the callouts reach the speakers
/// without any entitlement.
@MainActor
final class GuidanceVoice: NSObject, GuidanceSpeaking, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let session = AVAudioSession.sharedInstance()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        do {
            try session.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try session.setActive(true)
        } catch {
            // Speaking without the session is still speaking; the worst
            // case is a callout at the same volume as the music.
        }
        // A new callout supersedes one still being read: by the time
        // "in half a mile" is interrupted by "in 500 feet", the second
        // is the one that matters.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    private func release() {
        guard !synthesizer.isSpeaking else { return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.release() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.release() }
    }
}
