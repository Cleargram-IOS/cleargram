import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramUIPreferences
import ConvertOpusToAAC

// On-device transcription of a voice or video message, in one of several candidate languages.
//
// Upstream already ships every piece of the mechanism: `transcribeAudio(path:locale:)` (in the
// stock file next to this one) drives `SFSpeechRecognizer` with `requiresOnDeviceRecognition`,
// and `convertOpusToAAC` decodes the media into something the Speech framework can open. What
// it does not ship is a caller worth having — the public wrapper recognizes in
// `Locale.current` and nothing else, so a Russian voice message on an English phone comes back
// as word salad, and the round-video node has no local path at all.
//
// So the fork owns the two decisions and stock keeps the machinery:
//
//   * **which languages to try** — the list picked in Cleargram Settings, or the system
//     language when nothing is picked, which is stock behaviour exactly;
//   * **which result to keep** — Speech has no language identification, for audio or
//     otherwise, so the only way to "detect" the language is to recognize in each candidate
//     and judge the outputs. See `clearBestTranscription`.
//
// Video messages need no special handling: `convertOpusToAAC` decodes through
// `SoftwareAudioSource`, which is FFMpeg-backed and picks the audio stream out of whatever
// container it is handed — an MP4 round video as readily as an OGG voice message. It always
// writes a mono AAC m4a, which is exactly what the recognizer wants.
//
// Nothing here talks to Telegram: the audio never leaves the device, and no transcription
// request is made to the server.

// What the recognizers will actually be run with. Empty config = the system language, i.e.
// stock behaviour. The cap is `ClearConfig.maxTranscriptionLocales` — every extra language is
// another full pass over the audio — and it is re-applied here rather than trusted from the
// picker, since the list also arrives from an imported settings file.
func clearTranscriptionLocales() -> [String] {
    let configured = ClearConfig.transcriptionLocales.filter { !$0.isEmpty }
    if !configured.isEmpty {
        return Array(configured.prefix(ClearConfig.maxTranscriptionLocales))
    }
    // `Locale.current.identifier` can carry ICU keywords the recognizer knows nothing about —
    // a phone set to English with the region on Russia reports `en_US@rg=ruzzzz` (UTS #35
    // regional override: date, time and unit formats from RU, language untouched).
    return [String(Locale.current.identifier.prefix(while: { $0 != "@" }))]
}

// Pick the transcription that most likely got the language right.
//
// There is no honest signal here, only a least-bad one. Running the text through
// `NLLanguageRecognizer` sounds right and isn't: an English recognizer fed Russian speech
// emits English words, so the check confirms the wrong answer with high confidence. What is
// left is the recognizer's own per-segment confidence, which upstream also sorts on.
//
// Two things are added to that. A recognizer that heard nothing is not a candidate at all —
// an empty string always beats a bad transcription on confidence, and it is never what the
// reader wants. And ties break towards the language listed first, so a phone that reports zero
// confidence for everything (which happens) degrades to "the user's primary language" instead
// of to a coin flip — `sorted(by:)` is not stable, so the order has to be part of the
// comparison rather than assumed.
func clearBestTranscription(_ results: [TranscriptionResult?]) -> LocallyTranscribedAudio? {
    let candidates = results.enumerated().compactMap { index, value -> (text: String, isFinal: Bool, score: Float, index: Int)? in
        guard let value, !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        // Averaging over zero segments yields NaN, and a NaN in the comparator makes the sort
        // inconsistent — which Swift's sort is entitled to trap on, not just get wrong.
        let score = value.confidence.isFinite ? value.confidence : 0.0
        return (value.text, value.isFinal, score, index)
    }
    let best = candidates.sorted { lhs, rhs in
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        return lhs.index < rhs.index
    }.first
    return best.map { LocallyTranscribedAudio(text: $0.text, isFinal: $0.isFinal) }
}

// Recognize the file in every candidate language, then keep the best result.
//
// The passes run one after another rather than at once: several recognition tasks over the
// same audio contend for the same on-device resources, and this already runs while the user
// waits. Same chaining upstream's own wrapper uses.
public func clearTranscribeAudio(path: String) -> Signal<LocallyTranscribedAudio?, NoError> {
    var resultSignal: Signal<[TranscriptionResult?], NoError> = .single([])
    for locale in clearTranscriptionLocales() {
        resultSignal = resultSignal
        |> mapToSignal { accumulated -> Signal<[TranscriptionResult?], NoError> in
            return transcribeAudio(path: path, locale: locale)
            |> map { result -> [TranscriptionResult?] in
                return accumulated + [result]
            }
        }
    }
    return resultSignal
    |> map { results -> LocallyTranscribedAudio? in
        return clearBestTranscription(results)
    }
}

public func clearTranscribeMessageLocally(
    engine: TelegramEngine,
    messageId: EngineMessage.Id
) -> Signal<LocallyTranscribedAudio?, NoError> {
    return engine.data.get(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))
    |> mapToSignal { message -> Signal<String?, NoError> in
        guard let message else {
            return .single(nil)
        }
        guard let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile else {
            return .single(nil)
        }
        // Only what is already on disk — a partial download would transcribe to a fragment.
        return engine.resources.data(id: EngineMediaResource.Id(file.resource.id))
        |> take(1)
        |> map { data -> String? in
            return data.isComplete ? data.path : nil
        }
    }
    |> mapToSignal { path -> Signal<String?, NoError> in
        guard let path else {
            return .single(nil)
        }
        return convertOpusToAAC(sourcePath: path, allocateTempFile: {
            return EngineTempBox.shared.tempFile(fileName: "audio.m4a").path
        })
    }
    |> mapToSignal { path -> Signal<LocallyTranscribedAudio?, NoError> in
        guard let path else {
            return .single(nil)
        }
        return clearTranscribeAudio(path: path)
    }
}
