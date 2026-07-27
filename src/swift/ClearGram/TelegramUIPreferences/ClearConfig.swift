import Foundation
import SwiftSignalKit
import TelegramCore

// Facade over ClearConfigSettings. Call sites use `ClearConfig.hideStories.value` etc.
// The current snapshot is cached in memory and refreshed from shared-data via
// `ClearConfig.start(accountManager:)`. Default-off — every toggle reads as stock when
// uninitialized.

public enum ClearConfig {
    private static let cache = Atomic<ClearConfigSettings>(value: ClearConfigSettings.defaultSettings)

    public static func start(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        // keep the in-memory cache in sync with shared-data
        _ = clearConfigEntry(accountManager: accountManager).start(next: { value in
            _ = cache.swap(value)
        })
    }

    public static func current() -> ClearConfigSettings {
        return cache.with { $0 }
    }

    public static func update(
        accountManager: AccountManager<TelegramAccountManagerTypes>,
        _ f: @escaping (ClearConfigSettings) -> ClearConfigSettings
    ) -> Signal<Void, NoError> {
        return updateClearConfigInteractively(accountManager: accountManager, f)
    }

    // individual toggles — add as ClearConfigSettings grows
    public static var hideStories: Bool { current().hideStories }
    public static var hideAiFeatures: Bool { current().hideAiFeatures }
    public static var doubleTapDelay: Int32 { current().doubleTapDelay }
    public static var animationSpeed: Float { current().animationSpeed }
}
