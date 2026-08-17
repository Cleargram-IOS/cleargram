import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramUIPreferences
import AccountContext
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import Speech

// Language picker for on-device transcription.
//
// Upstream recognizes in `Locale.current` and nothing else, so with the phone in English a
// Russian voice message comes back as word salad. Speech has no language identification to
// fall back on, so "detect the language" is really "recognize in each candidate and keep the
// best one" — which is what `clearTranscribeAudio` does with the list picked here.
//
// Hence a multi-select rather than a single choice, capped at `ClearConfig.maxTranscriptionLocales`:
// every extra language is another full pass over the audio, paid on every voice message.
// Nothing picked = the system language, i.e. stock behaviour.
//
// The list is whatever `SFSpeechRecognizer` reports as supported on this device. Whether a
// language can actually run offline is a separate matter — iOS downloads recognition data per
// language, so the footer points at where that is managed.

// Same shorthand as the settings screen: English source text first, Russian second.
private func L(_ en: String, _ ru: String) -> String {
    return ClearStrings.tr(en, ru)
}

// "ru-RU" → "Русский (Россия)". Named in its own language, the way system language lists do it,
// so the row is readable whatever the app language is.
//
// `Locale.current.identifier` can carry ICU keywords the recognizer knows nothing about — a
// phone set to English with the region on Russia reports `en_US@rg=ruzzzz` (UTS #35 regional
// override: date, time and unit formats from RU, language untouched). `supportedLocales()`
// never returns anything like it, so everything past the keyword marker is dropped before the
// name is looked up.
func clearTranscriptionLanguageName(_ identifier: String) -> String {
    var base = identifier
    if let keywordIndex = base.firstIndex(of: "@") {
        base = String(base[base.startIndex ..< keywordIndex])
    }
    let locale = Locale(identifier: base)
    guard let name = locale.localizedString(forIdentifier: base), !name.isEmpty else {
        return base
    }
    return name.prefix(1).uppercased() + name.dropFirst()
}

// What the row in Cleargram Settings shows on its right-hand side.
func clearTranscriptionLanguageLabel(_ identifiers: [String]) -> String {
    let picked = identifiers.filter { !$0.isEmpty }
    guard !picked.isEmpty else {
        return L("System", "Системный")
    }
    if picked.count == 1 {
        return clearTranscriptionLanguageName(picked[0])
    }
    // Two names would not fit next to the title on a narrow screen; the count is the useful part.
    return L("\(picked.count) languages", "Языков: \(picked.count)")
}

private struct ClearTranscriptionLanguage {
    let identifier: String
    let title: String
    let subtitle: String?
}

private func clearTranscriptionLanguageList() -> [ClearTranscriptionLanguage] {
    return SFSpeechRecognizer.supportedLocales()
        .map { locale -> ClearTranscriptionLanguage in
            return ClearTranscriptionLanguage(
                identifier: locale.identifier,
                title: clearTranscriptionLanguageName(locale.identifier),
                subtitle: locale.identifier
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
}

private enum ClearTranscriptionLanguageSection: ItemListSectionId {
    case system = 0
    case languages = 1
}

private enum ClearTranscriptionLanguageEntry: ItemListNodeEntry {
    case systemLanguage(title: String, subtitle: String, checked: Bool)
    case systemFooter(String)
    case languagesHeader(String)
    case language(index: Int, identifier: String, title: String, subtitle: String?, checked: Bool)
    case languagesFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .systemLanguage, .systemFooter:
            return ClearTranscriptionLanguageSection.system.rawValue
        case .languagesHeader, .language, .languagesFooter:
            return ClearTranscriptionLanguageSection.languages.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .systemLanguage:
            return 0
        case .systemFooter:
            return 1
        case .languagesHeader:
            return 2
        case let .language(index, _, _, _, _):
            return 10 + index
        case .languagesFooter:
            return Int.max
        }
    }

    static func < (lhs: ClearTranscriptionLanguageEntry, rhs: ClearTranscriptionLanguageEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    static func == (lhs: ClearTranscriptionLanguageEntry, rhs: ClearTranscriptionLanguageEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.systemLanguage(lt, ls, lc), .systemLanguage(rt, rs, rc)):
            return lt == rt && ls == rs && lc == rc
        case let (.systemFooter(l), .systemFooter(r)):
            return l == r
        case let (.languagesHeader(l), .languagesHeader(r)):
            return l == r
        case let (.language(li, lid, lt, ls, lc), .language(ri, rid, rt, rs, rc)):
            return li == ri && lid == rid && lt == rt && ls == rs && lc == rc
        case let (.languagesFooter(l), .languagesFooter(r)):
            return l == r
        default:
            return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! ClearTranscriptionLanguageArguments
        switch self {
        case let .systemLanguage(title, subtitle, checked):
            return ItemListCheckboxItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                subtitle: subtitle,
                style: .right,
                checked: checked,
                zeroSeparatorInsets: false,
                sectionId: self.section,
                action: {
                    args.useSystemLanguage()
                }
            )
        case let .language(_, identifier, title, subtitle, checked):
            return ItemListCheckboxItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                subtitle: subtitle,
                style: .right,
                checked: checked,
                zeroSeparatorInsets: false,
                sectionId: self.section,
                action: {
                    args.toggle(identifier)
                }
            )
        case let .languagesHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .systemFooter(text), let .languagesFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private struct ClearTranscriptionLanguageArguments {
    let toggle: (String) -> Void
    let useSystemLanguage: () -> Void
}

func clearTranscriptionLanguageController(context: AccountContext) -> ViewController {
    let languages = clearTranscriptionLanguageList()
    let accountManager = context.sharedContext.accountManager

    var presentImpl: ((ViewController) -> Void)?

    let arguments = ClearTranscriptionLanguageArguments(
        toggle: { identifier in
            // Selection order is priority order: it decides which language wins when the
            // recognizers come back equally (un)confident, so an added language goes last.
            let current = ClearConfig.transcriptionLocales.filter { !$0.isEmpty }
            if !current.contains(identifier), current.count >= ClearConfig.maxTranscriptionLocales {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                presentImpl?(textAlertController(
                    context: context,
                    title: nil,
                    text: L(
                        "Up to \(ClearConfig.maxTranscriptionLocales) languages. Each one is another pass over the audio.",
                        "Не больше \(ClearConfig.maxTranscriptionLocales) языков. Каждый — ещё один проход по записи."
                    ),
                    actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                ))
                return
            }
            let _ = ClearConfig.update(accountManager: accountManager) { settings in
                var updated = settings
                var locales = settings.transcriptionLocales.filter { !$0.isEmpty }
                if let index = locales.firstIndex(of: identifier) {
                    locales.remove(at: index)
                } else {
                    locales.append(identifier)
                }
                updated.transcriptionLocales = locales
                return updated
            }.start()
        },
        useSystemLanguage: {
            let _ = ClearConfig.update(accountManager: accountManager) { settings in
                var updated = settings
                updated.transcriptionLocales = []
                return updated
            }.start()
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        clearConfigEntry(accountManager: accountManager)
    )
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let itemListPresentationData = ItemListPresentationData(presentationData)
        let picked = settings.transcriptionLocales.filter { !$0.isEmpty }
        var entries: [ClearTranscriptionLanguageEntry] = []

        entries.append(.systemLanguage(
            title: L("System Language", "Язык системы"),
            subtitle: clearTranscriptionLanguageName(Locale.current.identifier),
            checked: picked.isEmpty
        ))
        entries.append(.systemFooter(L(
            "Pick one or more languages below and each voice message is recognized in all of them, keeping the result that came out best.",
            "Выберите один или несколько языков ниже — каждое голосовое будет распознано на всех, а оставлен лучший результат."
        )))

        entries.append(.languagesHeader(L("LANGUAGES", "ЯЗЫКИ")))
        for (index, language) in languages.enumerated() {
            entries.append(.language(
                index: index,
                identifier: language.identifier,
                title: language.title,
                subtitle: language.subtitle,
                checked: picked.contains(language.identifier)
            ))
        }
        entries.append(.languagesFooter(L(
            "iOS only recognizes languages it has dictation data for — Settings ▸ General ▸ Keyboard ▸ Dictation Languages.",
            "iOS распознаёт только языки, для которых скачаны данные диктовки — «Настройки ▸ Основные ▸ Клавиатура ▸ Языки диктовки»."
        )))

        let state = ItemListControllerState(
            presentationData: itemListPresentationData,
            title: .text(L("Transcription Language", "Язык расшифровки")),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let nodeState = ItemListNodeState(
            presentationData: itemListPresentationData,
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        return (state, (nodeState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)

    presentImpl = { [weak controller] alert in
        controller?.present(alert, in: .window(.root))
    }

    return controller
}
