import Foundation

// Which parts of the screen-edge effects to drop: the dimming gradient and the variable blur, at the
// top and at the bottom edge, everywhere they are drawn — chat wallpaper edges, chat list, settings,
// sheets. Read by the two places all of them go through (`EdgeEffectView.update` and
// `WallpaperEdgeEffectNodeImpl.update`).
//
// It lives in Display because that is the lowest module both already depend on, and Display cannot
// see `ClearConfig` (TelegramUIPreferences), and TelegramUIPreferences cannot see Display either. So
// the setting crosses over through `UserDefaults`, which both sides can reach: `ClearConfig.start`
// writes `defaultsKey` as four bools in `State`'s field order whenever shared data changes, and
// this reads it, caching the value and refreshing on `UserDefaults.didChangeNotification` — so an edge
// follows a toggle on its next layout without any reader touching defaults per frame. Shared data
// stays the source of truth; this is a cache of four bools, already correct at launch.
public enum ClearEdgeEffects {
    public struct State: Equatable {
        public var hideTopDimming: Bool
        public var hideTopBlur: Bool
        public var hideBottomDimming: Bool
        public var hideBottomBlur: Bool

        public init(hideTopDimming: Bool, hideTopBlur: Bool, hideBottomDimming: Bool, hideBottomBlur: Bool) {
            self.hideTopDimming = hideTopDimming
            self.hideTopBlur = hideTopBlur
            self.hideBottomDimming = hideBottomDimming
            self.hideBottomBlur = hideBottomBlur
        }

        public static let stock = State(hideTopDimming: false, hideTopBlur: false, hideBottomDimming: false, hideBottomBlur: false)

        public func hidesDimming(top: Bool) -> Bool {
            return top ? self.hideTopDimming : self.hideBottomDimming
        }

        public func hidesBlur(top: Bool) -> Bool {
            return top ? self.hideTopBlur : self.hideBottomBlur
        }
    }

    // Written by `ClearConfig.mirrorEdgeEffects` in TelegramUIPreferences — keep the two in step.
    public static let defaultsKey = "cleargram.edgeEffects"
    private static let lock = NSLock()
    private static var cached: State?
    private static var observer: NSObjectProtocol?

    public static var current: State {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil, using: { _ in
                lock.lock()
                cached = nil
                lock.unlock()
            })
        }
        let value = read()
        cached = value
        return value
    }

    private static func read() -> State {
        guard let values = UserDefaults.standard.array(forKey: defaultsKey) as? [Bool], values.count == 4 else {
            return .stock
        }
        return State(hideTopDimming: values[0], hideTopBlur: values[1], hideBottomDimming: values[2], hideBottomBlur: values[3])
    }
}
