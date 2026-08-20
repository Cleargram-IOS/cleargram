import Foundation
import AudioToolbox
import SwiftSignalKit

// Cleargram: a ten-band graphic equalizer for the music player.
//
// Upstream already builds a `kAudioUnitSubType_NBandEQ` node into the audio graph of
// `MediaPlayerAudioRenderer`, and uses it for exactly one thing: a global boost on voice
// messages played through the earpiece. So the equalizer needs no new node and no new graph —
// it configures the bands of the unit that is already sitting between the mixer and the output.
//
// The band count can only be set while the unit is uninitialized, i.e. before `AUGraphInitialize`,
// so `ClearEqualizerUnit` is built at graph-creation time whether or not the equalizer is
// switched on. With it off every band is bypassed (`kAUNBandEQParam_BypassBand`) and the global
// gain is 0, which is the same pass-through stock's untouched single-band unit performs — and in
// exchange switching the equalizer on is heard on the track already playing instead of the next
// one, which is the entire point of an equalizer you can drag.
//
// This lives in TelegramCore, like `ClearHooks`, because it has readers on opposite sides of the
// module graph: UniversalMediaPlayer owns the audio unit, TelegramUIPreferences owns the stored
// settings and DebugSettingsUI owns the screen. All three already depend on TelegramCore, and
// none of them can see each other.
public enum ClearEqualizer {
    // Octave-spaced ISO centre frequencies — the usual ten-band layout, and the reason the band
    // filters are one octave wide: neighbouring bands then meet at their -3 dB points rather than
    // stacking on top of each other.
    public static let bandFrequencies: [Float] = [32.0, 64.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0]

    public static var bandCount: Int {
        return self.bandFrequencies.count
    }

    // Gains and the preamp are stored in tenths of a decibel: an integer keeps the settings file
    // and the shared-data entry exact, and a tenth is finer than anyone can hear or drag.
    public static let gainLimit: Int32 = 120

    public struct State: Equatable {
        public var enabled: Bool
        public var preamp: Int32
        public var gains: [Int32]

        public init(enabled: Bool, preamp: Int32, gains: [Int32]) {
            self.enabled = enabled
            self.preamp = preamp
            self.gains = gains
        }

        public static var flat: State {
            return State(enabled: false, preamp: 0, gains: [])
        }

        // Stored gains are allowed to be short (an empty list is flat, which is what an untouched
        // install and an imported settings file both look like) or long (a file written by a build
        // with more bands). Everything downstream reads them through here instead.
        public func gain(at index: Int) -> Int32 {
            guard index >= 0, index < self.gains.count else {
                return 0
            }
            return clampGain(self.gains[index])
        }

        public var isFlat: Bool {
            if clampGain(self.preamp) != 0 {
                return false
            }
            return self.normalizedGains.allSatisfy({ $0 == 0 })
        }

        // The list padded to the current band count, so a caller can index it directly.
        public var normalizedGains: [Int32] {
            return (0 ..< ClearEqualizer.bandCount).map { self.gain(at: $0) }
        }
    }

    public static func clampGain(_ value: Int32) -> Int32 {
        return max(-self.gainLimit, min(self.gainLimit, value))
    }

    // "35" -> "+3.5 dB". The one place tenths become text, so the screen and the menu label agree.
    public static func formatGain(_ value: Int32, withUnit: Bool) -> String {
        let clamped = self.clampGain(value)
        let sign = clamped > 0 ? "+" : (clamped < 0 ? "-" : "")
        let magnitude = abs(clamped)
        var text = "\(sign)\(magnitude / 10)"
        if magnitude % 10 != 0 {
            text += ".\(magnitude % 10)"
        }
        return withUnit ? "\(text) dB" : text
    }

    // "1000" -> "1 kHz". Band labels, so they fit under a 30pt-wide slider.
    public static func formatFrequency(_ value: Float) -> String {
        if value >= 1000.0 {
            let thousands = value / 1000.0
            if thousands == thousands.rounded() {
                return "\(Int(thousands))k"
            }
            return String(format: "%.1fk", thousands)
        }
        return "\(Int(value))"
    }

    private static let stateValue = Atomic<State>(value: State.flat)
    private static let listeners = Atomic<[Int32: () -> Void]>(value: [:])
    private static let nextListenerId = Atomic<Int32>(value: 1)

    public static func current() -> State {
        return self.stateValue.with({ $0 })
    }

    // The single writer-side entry point. Called from `ClearConfig.start` whenever the stored
    // settings change, and directly by the equalizer screen while a slider is being dragged —
    // dragging must be audible now, not after a shared-data write has made the round trip.
    public static func update(_ state: State) {
        var changed = false
        let _ = self.stateValue.modify { current in
            if current == state {
                return current
            }
            changed = true
            return state
        }
        guard changed else {
            return
        }
        for listener in self.listeners.with({ $0 }).values {
            listener()
        }
    }

    // Listeners are called on whatever queue `update` was called from; every one of them is
    // expected to hop to the queue that owns its audio unit.
    public static func addListener(_ f: @escaping () -> Void) -> Int32 {
        var id: Int32 = 0
        let _ = self.nextListenerId.modify { value in
            id = value
            return value &+ 1
        }
        let _ = self.listeners.modify { listeners in
            var listeners = listeners
            listeners[id] = f
            return listeners
        }
        return id
    }

    public static func removeListener(_ id: Int32) {
        let _ = self.listeners.modify { listeners in
            var listeners = listeners
            listeners.removeValue(forKey: id)
            return listeners
        }
    }
}

// One music renderer's view of the equalizer: it owns the band layout on that renderer's EQ unit
// and re-applies the gains whenever the settings change.
//
// Every method that touches the audio unit runs on the renderer's own serial queue, which is what
// `dispatch` hops onto. That is also what makes teardown safe: `invalidate()` runs on that same
// queue, so a block enqueued before it still finds a live unit, and one enqueued after it finds
// `invalidated` already set and does nothing.
public final class ClearEqualizerUnit {
    private let audioUnit: AudioComponentInstance
    private let dispatch: (@escaping () -> Void) -> Void
    private let bandCount: Int

    private var listenerId: Int32?
    private var invalidated = false

    // Fails when the unit will not take the band layout, in which case the renderer is left with
    // the stock unit and the equalizer is simply absent for that track.
    //
    // Must be called before `AUGraphInitialize`: `kAUNBandEQProperty_NumberOfBands` is only
    // settable while the unit is uninitialized.
    public init?(audioUnit: AudioComponentInstance, dispatch: @escaping (@escaping () -> Void) -> Void) {
        var maxBands: UInt32 = 0
        var maxBandsSize = UInt32(MemoryLayout<UInt32>.size)
        let maxBandsStatus = AudioUnitGetProperty(audioUnit, kAUNBandEQProperty_MaxNumberOfBands, kAudioUnitScope_Global, 0, &maxBands, &maxBandsSize)

        var count = ClearEqualizer.bandCount
        if maxBandsStatus == noErr && maxBands > 0 {
            count = min(count, Int(maxBands))
        }
        guard count > 0 else {
            return nil
        }

        var numberOfBands = UInt32(count)
        guard AudioUnitSetProperty(audioUnit, kAUNBandEQProperty_NumberOfBands, kAudioUnitScope_Global, 0, &numberOfBands, UInt32(MemoryLayout<UInt32>.size)) == noErr else {
            print("ClearEqualizer: the audio unit refused \(count) bands, leaving it stock")
            return nil
        }

        self.audioUnit = audioUnit
        self.dispatch = dispatch
        self.bandCount = count

        for index in 0 ..< count {
            let band = AudioUnitParameterID(index)
            AudioUnitSetParameter(audioUnit, kAUNBandEQParam_FilterType + band, kAudioUnitScope_Global, 0, AudioUnitParameterValue(kAUNBandEQFilterType_Parametric), 0)
            AudioUnitSetParameter(audioUnit, kAUNBandEQParam_Frequency + band, kAudioUnitScope_Global, 0, ClearEqualizer.bandFrequencies[index], 0)
            // One octave: the bands are an octave apart, so this is the width at which they cross
            // over without either gapping or piling up.
            AudioUnitSetParameter(audioUnit, kAUNBandEQParam_Bandwidth + band, kAudioUnitScope_Global, 0, 1.0, 0)
        }

        self.applyState(ClearEqualizer.current())

        self.listenerId = ClearEqualizer.addListener({ [weak self] in
            dispatch {
                guard let self, !self.invalidated else {
                    return
                }
                self.applyState(ClearEqualizer.current())
            }
        })
    }

    deinit {
        if let listenerId = self.listenerId {
            ClearEqualizer.removeListener(listenerId)
        }
    }

    // Called on the renderer queue, before the graph is torn down.
    public func invalidate() {
        self.invalidated = true
        if let listenerId = self.listenerId {
            self.listenerId = nil
            ClearEqualizer.removeListener(listenerId)
        }
    }

    private func applyState(_ state: ClearEqualizer.State) {
        for index in 0 ..< self.bandCount {
            let band = AudioUnitParameterID(index)
            let gain = state.enabled ? Float(state.gain(at: index)) / 10.0 : 0.0
            // A band at 0 dB is a unity filter either way; bypassing it means the unit skips the
            // biquad altogether, which is what makes the switched-off case free.
            AudioUnitSetParameter(self.audioUnit, kAUNBandEQParam_BypassBand + band, kAudioUnitScope_Global, 0, gain == 0.0 ? 1.0 : 0.0, 0)
            AudioUnitSetParameter(self.audioUnit, kAUNBandEQParam_Gain + band, kAudioUnitScope_Global, 0, gain, 0)
        }
        let preamp = state.enabled ? Float(ClearEqualizer.clampGain(state.preamp)) / 10.0 : 0.0
        AudioUnitSetParameter(self.audioUnit, kAUNBandEQParam_GlobalGain, kAudioUnitScope_Global, 0, preamp, 0)
    }
}
