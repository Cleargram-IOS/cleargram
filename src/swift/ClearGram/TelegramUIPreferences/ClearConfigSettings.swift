import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

// Centralized fork-config model. Stored under shared-data key 30
// (ApplicationSpecificSharedDataKeys.clearConfigSettings). Synced across devices via
// accountManager, survives logout, reactive via `clearConfigEntry`.
//
// Add new toggles as fields here; expose accessors on `ClearConfig` (the enum facade below).
// Default-off: every behavior change gated by `ClearConfig.<toggle>.value`.

public struct ClearConfigSettings: Codable, Equatable {
    public var hideStories: Bool
    public var hideAiFeatures: Bool
    public var doubleTapDelay: Int32
    public var animationSpeed: Float

    public static var defaultSettings: ClearConfigSettings {
        return ClearConfigSettings(
            hideStories: false,
            hideAiFeatures: false,
            doubleTapDelay: 300,
            animationSpeed: 1.0
        )
    }

    public init(
        hideStories: Bool = false,
        hideAiFeatures: Bool = false,
        doubleTapDelay: Int32 = 300,
        animationSpeed: Float = 1.0
    ) {
        self.hideStories = hideStories
        self.hideAiFeatures = hideAiFeatures
        self.doubleTapDelay = doubleTapDelay
        self.animationSpeed = animationSpeed
    }
}

public func updateClearConfigInteractively(
    accountManager: AccountManager<TelegramAccountManagerTypes>,
    _ f: @escaping (ClearConfigSettings) -> ClearConfigSettings
) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.clearConfigSettings) { entry in
            let current = entry?.get(ClearConfigSettings.self) ?? ClearConfigSettings.defaultSettings
            return SharedPreferencesEntry(f(current))
        }
    }
}

public func clearConfigEntry(
    accountManager: AccountManager<TelegramAccountManagerTypes>
) -> Signal<ClearConfigSettings, NoError> {
    return accountManager.sharedData(
        keys: [ApplicationSpecificSharedDataKeys.clearConfigSettings]
    )
    |> map { sharedData -> ClearConfigSettings in
        sharedData.entries[ApplicationSpecificSharedDataKeys.clearConfigSettings]?.get(ClearConfigSettings.self) ?? ClearConfigSettings.defaultSettings
    }
}
