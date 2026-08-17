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

// Last.fm account screen — everything credential-shaped that the Cleargram settings tree can't
// hold: the API key and shared secret, signing in, and the queue of scrobbles waiting for a
// connection. The two on/off toggles stay in Cleargram Settings ▸ Media & Stickers, next to the
// rest of the audio options.
//
// Reached from that same section. Kept separate from ClearSettingsController because its rows
// are text entry and network actions, not `WritableKeyPath`s into a settings struct.

// Same shorthand as the settings screen: English source text first, Russian second.
private func L(_ en: String, _ ru: String) -> String {
    return ClearStrings.tr(en, ru)
}

private enum ClearLastFmSection: ItemListSectionId {
    case credentials = 0
    case account = 1
    case queue = 2
}

private enum ClearLastFmEntry: ItemListNodeEntry {
    case credentialsHeader(String)
    case apiKey(String, String)
    case apiSecret(String, String)
    case credentialsFooter(String)
    case openApiPage(String)
    case signIn(String)
    case signOut(String)
    case accountFooter(String)
    case queueHeader(String)
    case sendQueue(String)
    case clearQueue(String)
    case queueFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .credentialsHeader, .apiKey, .apiSecret, .credentialsFooter, .openApiPage:
            return ClearLastFmSection.credentials.rawValue
        case .signIn, .signOut, .accountFooter:
            return ClearLastFmSection.account.rawValue
        case .queueHeader, .sendQueue, .clearQueue, .queueFooter:
            return ClearLastFmSection.queue.rawValue
        }
    }

    var stableId: Int {
        switch self {
        case .credentialsHeader: return 0
        case .apiKey: return 1
        case .apiSecret: return 2
        case .openApiPage: return 3
        case .credentialsFooter: return 4
        case .signIn: return 10
        case .signOut: return 11
        case .accountFooter: return 12
        case .queueHeader: return 20
        case .sendQueue: return 21
        case .clearQueue: return 22
        case .queueFooter: return 23
        }
    }

    static func < (lhs: ClearLastFmEntry, rhs: ClearLastFmEntry) -> Bool { lhs.stableId < rhs.stableId }

    static func == (lhs: ClearLastFmEntry, rhs: ClearLastFmEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.credentialsHeader(l), .credentialsHeader(r)): return l == r
        case let (.apiKey(lt, ll), .apiKey(rt, rl)): return lt == rt && ll == rl
        case let (.apiSecret(lt, ll), .apiSecret(rt, rl)): return lt == rt && ll == rl
        case let (.credentialsFooter(l), .credentialsFooter(r)): return l == r
        case let (.openApiPage(l), .openApiPage(r)): return l == r
        case let (.signIn(l), .signIn(r)): return l == r
        case let (.signOut(l), .signOut(r)): return l == r
        case let (.accountFooter(l), .accountFooter(r)): return l == r
        case let (.queueHeader(l), .queueHeader(r)): return l == r
        case let (.sendQueue(l), .sendQueue(r)): return l == r
        case let (.clearQueue(l), .clearQueue(r)): return l == r
        case let (.queueFooter(l), .queueFooter(r)): return l == r
        default: return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! ClearLastFmArguments
        switch self {
        case let .credentialsHeader(text), let .queueHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .credentialsFooter(text), let .accountFooter(text), let .queueFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .apiKey(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: nil, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                args.editApiKey()
            })
        case let .apiSecret(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: nil, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                args.editApiSecret()
            })
        case let .openApiPage(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                args.openApiPage()
            })
        case let .signIn(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                args.signIn()
            })
        case let .signOut(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                args.signOut()
            })
        case let .sendQueue(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                args.sendQueue()
            })
        case let .clearQueue(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                args.clearQueue()
            })
        }
    }
}

private struct ClearLastFmArguments {
    let editApiKey: () -> Void
    let editApiSecret: () -> Void
    let openApiPage: () -> Void
    let signIn: () -> Void
    let signOut: () -> Void
    let sendQueue: () -> Void
    let clearQueue: () -> Void
}

// The key is 32 hex characters — showing the head is enough to tell two accounts apart without
// putting the whole credential on screen. The secret is never shown back.
private func keyLabel(_ value: String) -> String {
    guard !value.isEmpty else {
        return L("Not set", "Не указан")
    }
    return String(value.prefix(6)) + "…"
}

private func secretLabel(_ value: String) -> String {
    return value.isEmpty ? L("Not set", "Не указан") : "••••••"
}

public func clearLastFmController(context: AccountContext) -> ViewController {
    var presentImpl: ((ViewController) -> Void)?
    var presentNativeImpl: ((UIViewController) -> Void)?

    let accountManager = context.sharedContext.accountManager

    // One shared text-entry alert for both credential rows and for sign-in: UIAlertController is
    // what the other fork screens use for this, and it comes with secure entry for free.
    func promptForValue(title: String, message: String?, placeholder: String, initial: String, isSecure: Bool, apply: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = placeholder
            textField.text = initial
            textField.isSecureTextEntry = isSecure
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: L("Save", "Сохранить"), style: .default) { _ in
            let value = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            apply(value)
        })
        alert.addAction(UIAlertAction(title: L("Cancel", "Отмена"), style: .cancel))
        presentNativeImpl?(alert)
    }

    func showResult(_ text: String) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentImpl?(textAlertController(
            context: context,
            title: nil,
            text: text,
            actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
        ))
    }

    let arguments = ClearLastFmArguments(
        editApiKey: {
            promptForValue(
                title: L("API Key", "API-ключ"),
                message: nil,
                placeholder: L("API key", "API-ключ"),
                initial: ClearLastFm.current().apiKey,
                isSecure: false,
                apply: { value in
                    let _ = updateClearLastFmSettingsInteractively(accountManager: accountManager) { current in
                        var updated = current
                        updated.apiKey = value
                        return updated
                    }.start()
                }
            )
        },
        editApiSecret: {
            promptForValue(
                title: L("Shared Secret", "Shared secret"),
                message: nil,
                placeholder: L("Shared secret", "Shared secret"),
                initial: "",
                isSecure: true,
                apply: { value in
                    guard !value.isEmpty else {
                        return
                    }
                    let _ = updateClearLastFmSettingsInteractively(accountManager: accountManager) { current in
                        var updated = current
                        updated.apiSecret = value
                        return updated
                    }.start()
                }
            )
        },
        openApiPage: {
            context.sharedContext.applicationBindings.openUrl(ClearLastFm.apiAccountUrl)
        },
        signIn: {
            let settings = ClearLastFm.current()
            guard settings.hasCredentials else {
                showResult(L(
                    "Enter your API key and shared secret first.",
                    "Сначала укажите API-ключ и shared secret."
                ))
                return
            }
            let alert = UIAlertController(
                title: L("Sign in to Last.fm", "Вход в Last.fm"),
                message: L(
                    "The password is sent once and not stored.",
                    "Пароль отправляется один раз и не сохраняется."
                ),
                preferredStyle: .alert
            )
            alert.addTextField { textField in
                textField.placeholder = L("Username", "Имя пользователя")
                textField.text = settings.username
                textField.autocapitalizationType = .none
                textField.autocorrectionType = .no
            }
            alert.addTextField { textField in
                textField.placeholder = L("Password", "Пароль")
                textField.isSecureTextEntry = true
            }
            alert.addAction(UIAlertAction(title: L("Sign In", "Войти"), style: .default) { _ in
                let username = (alert.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let password = alert.textFields?.last?.text ?? ""
                guard !username.isEmpty, !password.isEmpty else {
                    return
                }
                ClearLastFm.signIn(apiKey: settings.apiKey, apiSecret: settings.apiSecret, username: username, password: password) { result in
                    switch result {
                    case let .success(name):
                        showResult(L("Signed in as \(name).", "Вы вошли как \(name)."))
                    case let .failure(error):
                        showResult(L("Couldn't sign in: \(error.displayText)", "Не удалось войти: \(error.displayText)"))
                    }
                }
            })
            alert.addAction(UIAlertAction(title: L("Cancel", "Отмена"), style: .cancel))
            presentNativeImpl?(alert)
        },
        signOut: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            presentImpl?(textAlertController(
                context: context,
                title: nil,
                text: L(
                    "Sign out of Last.fm? The API key and shared secret are kept.",
                    "Выйти из Last.fm? API-ключ и shared secret останутся."
                ),
                actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: L("Sign Out", "Выйти"), action: {
                        ClearLastFm.signOut()
                    })
                ]
            ))
        },
        sendQueue: {
            ClearLastFm.flushPending()
        },
        clearQueue: {
            ClearLastFm.clearPending()
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        clearLastFmSettingsEntry(accountManager: accountManager)
    )
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let itemListPresentationData = ItemListPresentationData(presentationData)
        var entries: [ClearLastFmEntry] = []

        entries.append(.credentialsHeader(L("API ACCOUNT", "API-АККАУНТ")))
        entries.append(.apiKey(L("API Key", "API-ключ"), keyLabel(settings.apiKey)))
        entries.append(.apiSecret(L("Shared Secret", "Shared secret"), secretLabel(settings.apiSecret)))
        entries.append(.openApiPage(L("Get an API Account", "Получить API-аккаунт")))
        entries.append(.credentialsFooter(L(
            "Create an API account at \(ClearLastFm.apiAccountUrl) and paste both halves here.",
            "Создайте API-аккаунт на \(ClearLastFm.apiAccountUrl) и вставьте сюда обе части."
        )))

        if settings.isSignedIn {
            entries.append(.signOut(L("Sign Out", "Выйти")))
            entries.append(.accountFooter(L(
                "Signed in as \(settings.username).",
                "Выполнен вход: \(settings.username)."
            )))
        } else {
            entries.append(.signIn(L("Sign In", "Войти")))
            entries.append(.accountFooter(L(
                "The password is sent once and not stored.",
                "Пароль отправляется один раз и не сохраняется."
            )))
        }

        let pendingCount = settings.pending.count
        if pendingCount > 0 {
            entries.append(.queueHeader(L("QUEUE", "ОЧЕРЕДЬ")))
            entries.append(.sendQueue(L("Send Now", "Отправить сейчас")))
            entries.append(.clearQueue(L("Clear Queue", "Очистить очередь")))
            let tracksRu = ClearStrings.plural(pendingCount, one: "трек ждёт", few: "трека ждут", many: "треков ждут")
            entries.append(.queueFooter(L(
                "\(pendingCount) scrobble\(pendingCount == 1 ? "" : "s") waiting to be sent.",
                "\(pendingCount) \(tracksRu) отправки."
            )))
        }

        let state = ItemListControllerState(
            presentationData: itemListPresentationData,
            title: .text("Last.fm"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let nodeState = ItemListNodeState(
            presentationData: itemListPresentationData,
            entries: entries,
            style: .blocks,
            animateChanges: true
        )
        return (state, (nodeState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)

    presentImpl = { [weak controller] alert in
        controller?.present(alert, in: .window(.root))
    }
    presentNativeImpl = { [weak controller] alert in
        controller?.present(alert, animated: true)
    }

    return controller
}
