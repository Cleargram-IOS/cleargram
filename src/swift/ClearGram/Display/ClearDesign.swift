import Foundation

// One switch for "render the pre-Liquid-Glass design".
//
// Two different things have to be turned off to get the old look, and only one of them is ours:
//
//   1. **UIKit's own chrome** — bars, sheets, switches, alerts — adopts Liquid Glass simply because
//      the app is built against the iOS 26 SDK. No app code decides that; the only opt-out is the
//      `UIDesignRequiresCompatibility` key in Info.plist (`misc__legacy-design`), which is a
//      build-time, app-wide choice and which Apple removes in the next major release.
//   2. **Telegram's own glass drawing** — its components branch on `#available(iOS 26.0, *)`, i.e.
//      on the OS version, which the plist key does not change. Left alone they would keep painting
//      glass on top of a legacy system, which looks worse than either option on its own.
//
// This flag is (2): every such branch also asks `!ClearDesign.useLegacy`, so the pre-26 path the
// app still carries (its deployment target is iOS 13) is taken instead. It lives in Display
// because that is the lowest module all of those components already depend on.
//
// Written once at startup from `ClearConfig.legacyDesign`, before any view exists, and never again —
// several of the branches it guards run inside `init` or `layerClass`, so changing it later would
// only produce a half-converted screen. The settings row therefore asks for a relaunch.
public enum ClearDesign {
    private static let legacyDesignKey = "cleargram.legacyDesign"

    // Resolved once, synchronously, the first time anything reads it — which is the whole point.
    //
    // The setting itself lives in shared data like every other `ClearConfig` toggle, but shared
    // data is only readable through a signal that delivers on the account manager's queue. The
    // first version of this set the flag from that signal in `AppDelegate`, with a comment
    // claiming it ran "before any view exists"; it does not. `deliverOnMainQueue` hops queues, so
    // the assignment lands a runloop turn later, by which time `SwitchNodeView.layerClass` and
    // friends have already been read and the UI is half-converted — or, as observed on device,
    // not converted at all.
    //
    // So the launch-time value comes from `UserDefaults`, which is readable synchronously before
    // anything exists. Shared data stays the source of truth; this is a one-bool cache of it,
    // written by `mirrorForNextLaunch` whenever the setting changes, and read on the next launch.
    // That is also why the settings row says a relaunch is required.
    public static let useLegacy: Bool = UserDefaults.standard.bool(forKey: legacyDesignKey)

    /// Records the setting for the *next* launch. Changing it has no effect on the running app.
    ///
    /// **Parked.** Verified broken on device twice — once before the synchronous-read fix and once
    /// after, so the race was real but not the whole story. Until that is understood the feature
    /// must not activate at all: accounts that switched the toggle on still have
    /// `legacyDesign = true` in shared data, and the settings section is commented out entirely, so
    /// they have no way to switch it back off. So this ignores the stored value and writes `false`.
    /// Restore the commented line and the real row in `ClearSettingsController` together.
    public static func mirrorForNextLaunch(_ value: Bool) {
        let _ = value
        UserDefaults.standard.set(false, forKey: legacyDesignKey)
        // UserDefaults.standard.set(value, forKey: legacyDesignKey)
    }

    // Whether UIKit itself is currently drawing the old design, i.e. whether `misc__legacy-design`
    // is in the build. Not the same question as `useLegacy`, and not interchangeable with it:
    // a few of the branches above do not draw anything, they size and position a control UIKit
    // draws — `UISwitch` is 63x28 under Liquid Glass and 51x31 before it. Those have to follow the
    // plist key, not the toggle, or the default-off build lays out a glass-sized slot for a switch
    // UIKit renders legacy.
    //
    // Read from the bundle rather than mirrored from the patch, so that popping `misc__legacy-design`
    // needs no second edit here.
    public static let systemIsLegacy: Bool = {
        return Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility") as? Bool ?? false
    }()
}
