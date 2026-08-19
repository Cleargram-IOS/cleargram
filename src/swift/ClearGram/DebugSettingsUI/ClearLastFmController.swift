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
    case completeSignIn(String)
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
        case .signIn, .completeSignIn, .signOut, .accountFooter:
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
        case .completeSignIn: return 11
        case .signOut: return 12
        case .accountFooter: return 13
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
        case let (.completeSignIn(l), .completeSignIn(r)): return l == r
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
        case let .completeSignIn(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                args.completeSignIn()
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
    let completeSignIn: () -> Void
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

// Sign-in state worth keeping only for the length of the flow: the request token expires in
// about an hour and matters only between "Connect" and the user coming back from the browser.
// Deliberately not persisted — a token left over from a previous session is useless.
private struct ClearLastFmAuthState: Equatable {
    var pendingToken: String?
    var isBusy: Bool = false
}

public func clearLastFmController(context: AccountContext) -> ViewController {
    var presentImpl: ((ViewController) -> Void)?
    var presentNativeImpl: ((UIViewController) -> Void)?
    // Takes `explicit`: the user tapped the row (say what went wrong) versus the automatic
    // retry when the app returns to the foreground (stay quiet — they may be doing something
    // else entirely, and "not authorized yet" is the normal state while waiting).
    var attemptCompleteImpl: ((Bool) -> Void)?

    let accountManager = context.sharedContext.accountManager

    let stateValue = Atomic<ClearLastFmAuthState>(value: ClearLastFmAuthState())
    let statePromise = ValuePromise<ClearLastFmAuthState>(ClearLastFmAuthState(), ignoreRepeated: true)
    let updateState: ((ClearLastFmAuthState) -> ClearLastFmAuthState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

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
            updateState { current in
                var updated = current
                updated.isBusy = true
                return updated
            }
            ClearLastFm.requestToken(apiKey: settings.apiKey, apiSecret: settings.apiSecret) { result in
                switch result {
                case let .success(token):
                    updateState { current in
                        var updated = current
                        updated.pendingToken = token
                        updated.isBusy = false
                        return updated
                    }
                    context.sharedContext.applicationBindings.openUrl(
                        ClearLastFm.authorizationUrl(apiKey: settings.apiKey, token: token)
                    )
                case let .failure(error):
                    updateState { current in
                        var updated = current
                        updated.isBusy = false
                        return updated
                    }
                    showResult(L(
                        "Couldn't start sign-in: \(error.displayText)",
                        "Не удалось начать вход: \(error.displayText)"
                    ))
                }
            }
        },
        completeSignIn: {
            attemptCompleteImpl?(true)
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

    attemptCompleteImpl = { explicit in
        let settings = ClearLastFm.current()
        let state = stateValue.with { $0 }
        guard let token = state.pendingToken, settings.hasCredentials, !state.isBusy else {
            return
        }
        updateState { current in
            var updated = current
            updated.isBusy = true
            return updated
        }
        ClearLastFm.completeSignIn(apiKey: settings.apiKey, apiSecret: settings.apiSecret, token: token) { result in
            switch result {
            case let .success(name):
                updateState { _ in ClearLastFmAuthState() }
                showResult(L("Signed in as \(name).", "Вы вошли как \(name)."))
            case let .failure(error):
                // An expired token can never be approved, so drop it and let the row offer a
                // fresh start. "Not authorized yet" keeps the token — that is just waiting.
                updateState { current in
                    var updated = current
                    updated.isBusy = false
                    if error.isTokenExpired {
                        updated.pendingToken = nil
                    }
                    return updated
                }
                guard explicit else {
                    return
                }
                if error.isTokenNotAuthorized {
                    showResult(L(
                        "Approve access on the Last.fm page first, then come back.",
                        "Сначала подтвердите доступ на странице Last.fm, затем вернитесь."
                    ))
                } else if error.isTokenExpired {
                    showResult(L(
                        "The sign-in link expired. Tap Connect again.",
                        "Ссылка для входа устарела. Нажмите «Подключить» ещё раз."
                    ))
                } else {
                    showResult(L(
                        "Couldn't sign in: \(error.displayText)",
                        "Не удалось войти: \(error.displayText)"
                    ))
                }
            }
        }
    }

    // Coming back to the foreground is the only signal we get that the user is done on the
    // website — Last.fm's desktop flow has no callback. Folded into the state signal so the
    // subscription lives exactly as long as the screen does.
    let applicationIsActive = context.sharedContext.applicationBindings.applicationIsActive
    |> distinctUntilChanged
    |> deliverOnMainQueue
    |> beforeNext { isActive in
        if isActive {
            attemptCompleteImpl?(false)
        }
    }

    let signal = combineLatest(
        context.sharedContext.presentationData,
        clearLastFmSettingsEntry(accountManager: accountManager),
        statePromise.get(),
        applicationIsActive
    )
    |> map { presentationData, settings, state, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
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
        } else if state.pendingToken != nil {
            entries.append(.completeSignIn(state.isBusy
                ? L("Checking…", "Проверяем…")
                : L("Complete Sign-In", "Завершить вход")))
            entries.append(.accountFooter(L(
                "Approve access on the Last.fm page, then come back — this finishes by itself.",
                "Подтвердите доступ на странице Last.fm и вернитесь — вход завершится сам."
            )))
        } else {
            entries.append(.signIn(state.isBusy
                ? L("Connecting…", "Подключаем…")
                : L("Connect", "Подключить")))
            entries.append(.accountFooter(L(
                "Opens Last.fm in the browser to approve access. Your password is never entered here.",
                "Откроет Last.fm в браузере для подтверждения доступа. Пароль здесь не вводится."
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
