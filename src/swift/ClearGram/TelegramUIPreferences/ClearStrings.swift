import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

// Localization for fork-only UI.
//
// Stock strings are not touched: Telegram ships its own localization (bundled + server
// delivered), Russian included, and any key added locally would be overwritten by the next
// language update anyway. What this covers is the English text cleargram itself adds —
// the settings tree, the transfer sheet, the hidden-chats screen, the handful of context
// menu items and alerts wired in by patches.
//
// The current language is mirrored from shared-data into an Atomic by `start`, called from
// `ClearConfig.start` — the same trick `ClearHooks` uses. That keeps call sites static
// (`ClearStrings.tr("Open link?", "Открыть ссылку?")`) instead of threading a
// `PresentationStrings` through two hundred places, most of which are plain data tables
// with no presentation data in scope.
//
// English is the source text and the fallback: a client running in any language other than
// Russian sees exactly the strings it saw before, which is also how the surrounding stock
// UI behaves.

public enum ClearStrings {
    private static let languageCode = Atomic<String>(value: "en")

    public static func start(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        _ = (accountManager.sharedData(keys: [SharedDataKeys.localizationSettings])
        |> map { sharedData -> String in
            return sharedData.entries[SharedDataKeys.localizationSettings]?.get(LocalizationSettings.self)?.primaryComponent.languageCode ?? "en"
        }
        |> distinctUntilChanged).start(next: { code in
            _ = languageCode.swap(code)
        })
    }

    // `ru`, but also `ru-RU` and the informal `ru-raw` variants Telegram serves.
    public static var isRussian: Bool {
        return languageCode.with { $0 }.lowercased().hasPrefix("ru")
    }

    // The primitive every fork string goes through: English source, Russian translation.
    public static func tr(_ en: String, _ ru: String) -> String {
        return self.isRussian ? ru : en
    }

    // Russian needs three forms where English needs two: 1 изменение, 2 изменения, 5 изменений.
    // Negative counts can't occur here, so only the last two digits are inspected.
    public static func plural(_ count: Int, one: String, few: String, many: String) -> String {
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 14 {
            return many
        }
        switch count % 10 {
        case 1:
            return one
        case 2, 3, 4:
            return few
        default:
            return many
        }
    }

    // MARK: - Strings used from stock files
    //
    // Fork files call `tr` inline, keeping the text next to the code that shows it. Patched
    // stock files use these instead, so each patch hunk stays a one-liner and the Russian
    // text never lands in a stock file.

    public static var contextMenuShowPackOwner: String {
        return tr("Show Pack Owner", "Показать владельца набора")
    }

    // Second save entry on a round video message. Sits next to the stock "Save to Gallery",
    // which keeps the file exactly as the sender built it — corners, branding and all.
    public static var contextMenuSaveRoundVideoUnmasked: String {
        return tr("Save without Watermark", "Сохранить без водяного знака")
    }

    // Shown when the pack owner is not a peer this device knows, so there is nothing to open.
    public static func packOwnerIdCopied(_ id: Int64) -> String {
        return tr("Owner ID \(id) copied", "ID владельца \(id) скопирован")
    }

    // The country name behind Telegram's "TS" test-number code; stock has no key for it.
    public static var testCountryName: String {
        return tr("Test", "Тестовый")
    }

    public static var confirmPollRevote: String {
        return tr("Change your vote?", "Изменить голос?")
    }

    public static var confirmPollPermanentVote: String {
        return tr(
            "This poll does not allow changing your vote. Your choice will be permanent.",
            "В этом опросе нельзя переголосовать. Ваш выбор останется навсегда."
        )
    }

    public static var confirmOpenLink: String {
        return tr("Open link?", "Открыть ссылку?")
    }

    public static var biometricReasonDeleteChat: String {
        return tr("Confirm delete chat", "Подтвердите удаление чата")
    }

    public static var biometricReasonClearHistory: String {
        return tr("Confirm clear history", "Подтвердите очистку истории")
    }

    public static var biometricReasonLogout: String {
        return tr("Confirm logout", "Подтвердите выход из аккаунта")
    }
}
