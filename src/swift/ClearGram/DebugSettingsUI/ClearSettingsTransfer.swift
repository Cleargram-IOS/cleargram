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
import UndoUI

// Export / import of the Cleargram settings only — stock Telegram settings are never touched.
//
// Container: UTF-8 JSON with a magic string, in a `.cleargram` file.
//
//   { "format": "cleargram-settings", "version": 1, "app": "Cleargram 12.0.1 (2705)",
//     "exportedAt": 1786000000, "settings": { "hideStories": true, "chatListLines": 2 } }
//
// `settings` carries ONLY the keys whose value differs from the defaults. That is what makes
// merge-vs-replace meaningful: "present in the file" means "the exporter deliberately changed it".
//
// The whole diff/merge engine works on `[String: Any]` obtained by round-tripping the struct
// through JSON, so no hand-maintained field table has to track ClearConfigSettings as it grows.
//
// Deliberately NOT exported: hidden chats and hidden messages (separate shared-data keys 31/32,
// and they carry peer ids), and the two stock ExperimentalUISettings toggles the Cleargram screen
// surfaces (Fake Glass / Force Clear Glass). ClearConfigSettings itself is only Bools and Int32s —
// no credentials, no peer ids, nothing account-specific.

// Same shorthand as the settings screen: English source text first, Russian second.
private func L(_ en: String, _ ru: String) -> String {
    return ClearStrings.tr(en, ru)
}

public struct ClearSettingsPayload {
    public let version: Int
    public let appVersion: String?
    public let exportedAt: Int?
    // Non-default values, already filtered down to known keys.
    public let values: [String: Any]
}

public enum ClearImportMode {
    case merge   // apply the file's keys on top of what's currently set
    case replace // reset everything to defaults first, then apply the file's keys
}

public struct ClearSettingsChange {
    public let key: String
    public let title: String
    public let fromText: String
    public let toText: String
}

public enum ClearSettingsTransfer {
    public static let fileExtension = "cleargram"
    public static let mimeType = "application/json"
    static let formatMagic = "cleargram-settings"
    static let formatVersion = 1
    static let maxFileSize = 256 * 1024

    static func defaultFileName() -> String {
        return "Cleargram-Settings.\(fileExtension)"
    }

    // MARK: - Dictionary bridge

    static func dictionary(_ settings: ClearConfigSettings) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(settings),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    static func settings(_ dict: [String: Any]) -> ClearConfigSettings? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
            return nil
        }
        return try? JSONDecoder().decode(ClearConfigSettings.self, from: data)
    }

    static var knownKeys: Set<String> {
        return Set(dictionary(ClearConfigSettings.defaultSettings).keys)
    }

    // JSONSerialization hands back NSNumber for both Bool and Int32; a given key has a fixed type,
    // so comparing as NSNumber is safe.
    static func sameValue(_ lhs: Any?, _ rhs: Any?) -> Bool {
        if let l = lhs as? NSNumber, let r = rhs as? NSNumber {
            return l == r
        }
        if let l = lhs as? [String], let r = rhs as? [String] {
            return l == r
        }
        // The equalizer's per-band gains. JSONSerialization hands an [Int32] back as [NSNumber],
        // which neither branch above catches — without this every export would report a flat
        // equalizer as changed, and every import would drop the band gains on the floor.
        if let l = lhs as? [NSNumber], let r = rhs as? [NSNumber] {
            return l == r
        }
        return lhs == nil && rhs == nil
    }

    // MARK: - Encode / decode / apply

    public static func encode(_ settings: ClearConfigSettings) -> Data? {
        let current = dictionary(settings)
        let defaults = dictionary(ClearConfigSettings.defaultSettings)
        var changed: [String: Any] = [:]
        for (key, value) in current where !sameValue(value, defaults[key]) {
            changed[key] = value
        }
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let container: [String: Any] = [
            "format": formatMagic,
            "version": formatVersion,
            "app": "Cleargram \(short) (\(build))",
            "exportedAt": Int(Date().timeIntervalSince1970),
            "settings": changed
        ]
        return try? JSONSerialization.data(withJSONObject: container, options: [.prettyPrinted, .sortedKeys])
    }

    public static func decode(_ data: Data) -> ClearSettingsPayload? {
        guard data.count <= maxFileSize else {
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard (object["format"] as? String) == formatMagic else {
            return nil
        }
        guard let version = (object["version"] as? NSNumber)?.intValue, version <= formatVersion else {
            return nil
        }
        guard let raw = object["settings"] as? [String: Any] else {
            return nil
        }

        let known = knownKeys
        var values: [String: Any] = [:]
        for (key, value) in raw where known.contains(key) {
            if value is NSNumber || value is [String] || value is [NSNumber] {
                values[key] = value
            }
        }
        // The real type check: a hand-edited `"hideStories": 5` must be rejected, not coerced.
        var probe = dictionary(ClearConfigSettings.defaultSettings)
        for (key, value) in values {
            probe[key] = value
        }
        guard settings(probe) != nil else {
            return nil
        }

        return ClearSettingsPayload(
            version: version,
            appVersion: object["app"] as? String,
            exportedAt: (object["exportedAt"] as? NSNumber)?.intValue,
            values: values
        )
    }

    public static func apply(payload: ClearSettingsPayload, mode: ClearImportMode, to current: ClearConfigSettings) -> ClearConfigSettings? {
        var result: [String: Any]
        switch mode {
        case .merge:
            result = dictionary(current)
        case .replace:
            result = dictionary(ClearConfigSettings.defaultSettings)
        }
        for (key, value) in payload.values {
            result[key] = value
        }
        return settings(result)
    }

    // MARK: - Human-readable diff

    // `hideChatListPromoNotices` -> "Hide Chat List Promo Notices". Derived rather than mapped to
    // the settings tree on purpose: a new toggle then needs no second registration to show up here.
    static func humanize(_ key: String) -> String {
        var result = ""
        for character in key {
            if character.isUppercase && !result.isEmpty {
                result.append(" ")
            }
            result.append(character)
        }
        return result.prefix(1).uppercased() + result.dropFirst()
    }

    static func describe(_ value: Any?, key: String? = nil) -> String {
        guard let value else {
            return "—"
        }
        // Equalizer gains are stored in tenths of a decibel, which is not something to show a
        // reader as a bare list of integers.
        if key == "equalizerGains", let list = value as? [NSNumber] {
            let text = list.map({ ClearEqualizer.formatGain(Int32(truncating: $0), withUnit: false) }).joined(separator: " ")
            return text.isEmpty ? L("Flat", "Ровно") : text
        }
        if key == "equalizerPreamp", let number = value as? NSNumber {
            return ClearEqualizer.formatGain(Int32(truncating: number), withUnit: true)
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? L("On", "Вкл.") : L("Off", "Выкл.")
            }
            return "\(number.intValue)"
        }
        if let list = value as? [String] {
            return list.isEmpty ? "—" : list.joined(separator: ", ")
        }
        if let list = value as? [NSNumber] {
            return list.isEmpty ? "—" : list.map({ "\($0.intValue)" }).joined(separator: ", ")
        }
        return "\(value)"
    }

    /// What this payload would actually change, relative to `current` under `mode`.
    public static func changes(payload: ClearSettingsPayload, mode: ClearImportMode, current: ClearConfigSettings) -> [ClearSettingsChange] {
        let before = dictionary(current)
        var after: [String: Any]
        switch mode {
        case .merge:
            after = before
        case .replace:
            after = dictionary(ClearConfigSettings.defaultSettings)
        }
        for (key, value) in payload.values {
            after[key] = value
        }

        var result: [ClearSettingsChange] = []
        for key in after.keys.sorted() where !sameValue(before[key], after[key]) {
            result.append(ClearSettingsChange(
                key: key,
                title: humanize(key),
                fromText: describe(before[key], key: key),
                toText: describe(after[key], key: key)
            ))
        }
        return result
    }
}

// MARK: - Export

extension ClearSettingsTransfer {
    /// Action sheet: send the settings file to a chat, or hand it to the system share sheet
    /// (which covers Save to Files, AirDrop, and everything else).
    public static func presentExport(
        context: AccountContext,
        present: @escaping (ViewController, Any?) -> Void,
        push: @escaping (ViewController) -> Void,
        presentNative: @escaping (UIViewController) -> Void
    ) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        guard let data = encode(ClearConfig.current()) else {
            present(textAlertController(context: context, title: nil, text: L("Couldn't build the settings file.", "Не удалось собрать файл настроек."), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
            return
        }

        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetButtonItem] = []

        if context.sharedContext.applicationBindings.isMainApp {
            items.append(ActionSheetButtonItem(title: L("Send to Chat", "Отправить в чат"), color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()

                let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.onlyWriteable, .excludeDisabled]))
                controller.peerSelected = { [weak controller] peer, _ in
                    let peerId = peer.id
                    controller?.dismiss()

                    let id = Int64.random(in: Int64.min ... Int64.max)
                    let fileResource = LocalFileMediaResource(fileId: id, size: Int64(data.count), isSecretRelated: false)
                    context.engine.resources.storeResourceData(id: EngineMediaResource.Id(fileResource.id), data: data)

                    let file = TelegramMediaFile(
                        fileId: EngineMedia.Id(namespace: Namespaces.Media.LocalFile, id: id),
                        partialReference: nil,
                        resource: fileResource,
                        previewRepresentations: [],
                        videoThumbnails: [],
                        immediateThumbnailData: nil,
                        mimeType: mimeType,
                        size: Int64(data.count),
                        attributes: [.FileName(fileName: defaultFileName())],
                        alternativeRepresentations: []
                    )
                    let message: EnqueueMessage = .message(text: "", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: file), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                    let _ = enqueueMessages(account: context.account, peerId: peerId, messages: [message]).start()
                }
                push(controller)
            }))
        }

        items.append(ActionSheetButtonItem(title: L("Save to Files / Share", "Сохранить в «Файлы» или поделиться"), color: .accent, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()

            let tempFile = EngineTempBox.shared.tempFile(fileName: defaultFileName())
            guard (try? data.write(to: URL(fileURLWithPath: tempFile.path))) != nil else {
                EngineTempBox.shared.dispose(tempFile)
                return
            }
            let activityController = UIActivityViewController(activityItems: [URL(fileURLWithPath: tempFile.path)], applicationActivities: nil)
            activityController.completionWithItemsHandler = { _, _, _, _ in
                EngineTempBox.shared.dispose(tempFile)
            }
            presentNative(activityController)
        }))

        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        present(actionSheet, nil)
    }
}

// MARK: - Import

private enum ClearImportEntry: ItemListNodeEntry {
    case modeHeader
    case modeMerge(Bool)
    case modeReplace(Bool)
    case modeFooter(String)
    case changesHeader(String)
    case change(index: Int, title: String, value: String)
    case changesFooter(String)
    case apply(String)

    var section: ItemListSectionId {
        switch self {
        case .modeHeader, .modeMerge, .modeReplace, .modeFooter:
            return 0
        case .changesHeader, .change, .changesFooter:
            return 1
        case .apply:
            return 2
        }
    }

    var stableId: Int {
        switch self {
        case .modeHeader: return 0
        case .modeMerge: return 1
        case .modeReplace: return 2
        case .modeFooter: return 3
        case .changesHeader: return 1000
        case let .change(index, _, _): return 1001 + index
        case .changesFooter: return 900000
        case .apply: return 1000000
        }
    }

    static func < (lhs: ClearImportEntry, rhs: ClearImportEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    static func == (lhs: ClearImportEntry, rhs: ClearImportEntry) -> Bool {
        switch (lhs, rhs) {
        case (.modeHeader, .modeHeader):
            return true
        case let (.modeMerge(l), .modeMerge(r)):
            return l == r
        case let (.modeReplace(l), .modeReplace(r)):
            return l == r
        case let (.modeFooter(l), .modeFooter(r)):
            return l == r
        case let (.changesHeader(l), .changesHeader(r)):
            return l == r
        case let (.change(li, lt, lv), .change(ri, rt, rv)):
            return li == ri && lt == rt && lv == rv
        case let (.changesFooter(l), .changesFooter(r)):
            return l == r
        case let (.apply(l), .apply(r)):
            return l == r
        default:
            return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! ClearImportArguments
        switch self {
        case .modeHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: L("HOW TO APPLY", "КАК ПРИМЕНИТЬ"), sectionId: self.section)
        case let .modeMerge(selected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: L("Add on Top", "Поверх текущих"), style: .right, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                args.setMode(.merge)
            })
        case let .modeReplace(selected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: L("Replace Everything", "Заменить полностью"), style: .right, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                args.setMode(.replace)
            })
        case let .modeFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .changesHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .change(_, title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, labelStyle: .multilineDetailText, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .changesFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .apply(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .center, sectionId: self.section, style: .blocks, action: {
                args.apply()
            })
        }
    }
}

private final class ClearImportArguments {
    let setMode: (ClearImportMode) -> Void
    let apply: () -> Void

    init(setMode: @escaping (ClearImportMode) -> Void, apply: @escaping () -> Void) {
        self.setMode = setMode
        self.apply = apply
    }
}

extension ClearSettingsTransfer {
    /// The import screen: which mode, and exactly which options would change.
    public static func importController(context: AccountContext, payload: ClearSettingsPayload, isModal: Bool) -> ViewController {
        let modeValue = ValuePromise<ClearImportMode>(.merge, ignoreRepeated: true)
        let modeState = Atomic<ClearImportMode>(value: .merge)

        var dismissImpl: (() -> Void)?
        var presentImpl: ((ViewController) -> Void)?

        let arguments = ClearImportArguments(
            setMode: { mode in
                let _ = modeState.swap(mode)
                modeValue.set(mode)
            },
            apply: {
                let mode = modeState.with { $0 }
                let accountManager = context.sharedContext.accountManager
                let _ = ClearConfig.update(accountManager: accountManager) { current in
                    return ClearSettingsTransfer.apply(payload: payload, mode: mode, to: current) ?? current
                }.start()

                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                dismissImpl?()
                presentImpl?(UndoOverlayController(
                    presentationData: presentationData,
                    content: .info(
                        title: nil,
                        text: L("Settings imported. Restart to apply everything.", "Настройки импортированы. Перезапустите приложение, чтобы применить всё."),
                        timeout: nil,
                        customUndoText: L("Restart Now", "Перезапустить")
                    ),
                    elevatedLayout: false,
                    action: { action in
                        if action == .undo {
                            exit(0)
                        }
                        return true
                    }
                ))
            }
        )

        let signal = combineLatest(
            context.sharedContext.presentationData,
            modeValue.get(),
            clearConfigEntry(accountManager: context.sharedContext.accountManager)
        )
        |> map { presentationData, mode, current -> (ItemListControllerState, (ItemListNodeState, Any)) in
            let itemListPresentationData = ItemListPresentationData(presentationData)
            let changeList = ClearSettingsTransfer.changes(payload: payload, mode: mode, current: current)

            var entries: [ClearImportEntry] = []
            entries.append(.modeHeader)
            entries.append(.modeMerge(mode == .merge))
            entries.append(.modeReplace(mode == .replace))
            switch mode {
            case .merge:
                entries.append(.modeFooter(L(
                    "Only the options listed below are touched; anything the file doesn't mention keeps its current value.",
                    "Затрагиваются только перечисленные ниже параметры; всё, чего в файле нет, сохраняет текущее значение."
                )))
            case .replace:
                entries.append(.modeFooter(L(
                    "Everything Cleargram controls is reset to default first, then the file is applied.",
                    "Сначала всё, чем управляет Cleargram, сбрасывается к умолчанию, затем применяется файл."
                )))
            }

            if changeList.isEmpty {
                entries.append(.changesHeader(L("CHANGES", "ИЗМЕНЕНИЯ")))
                entries.append(.changesFooter(L(
                    "Nothing would change — these settings already match yours.",
                    "Ничего не изменится — эти настройки уже совпадают с вашими."
                )))
            } else {
                let count = changeList.count
                entries.append(.changesHeader(L(
                    "\(count) CHANGE\(count == 1 ? "" : "S")",
                    "\(count) \(ClearStrings.plural(count, one: "ИЗМЕНЕНИЕ", few: "ИЗМЕНЕНИЯ", many: "ИЗМЕНЕНИЙ"))"
                )))
                for (index, change) in changeList.enumerated() {
                    entries.append(.change(index: index, title: change.title, value: "\(change.fromText) → \(change.toText)"))
                }
                var footer = L(
                    "Telegram's own settings are not part of a Cleargram settings file.",
                    "Собственные настройки Telegram в файл настроек Cleargram не входят."
                )
                if let appVersion = payload.appVersion {
                    footer = L("Exported from \(appVersion).\n\n", "Экспортировано из \(appVersion).\n\n") + footer
                }
                entries.append(.changesFooter(footer))
                entries.append(.apply(mode == .replace
                    ? L("Replace My Settings", "Заменить мои настройки")
                    : L(
                        "Import \(count) Setting\(count == 1 ? "" : "s")",
                        "Импортировать \(count) \(ClearStrings.plural(count, one: "параметр", few: "параметра", many: "параметров"))"
                    )
                ))
            }

            let state = ItemListControllerState(
                presentationData: itemListPresentationData,
                title: .text(L("Import Settings", "Импорт настроек")),
                leftNavigationButton: isModal ? ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: {
                    dismissImpl?()
                }) : nil,
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
        dismissImpl = { [weak controller] in
            guard let controller else {
                return
            }
            if isModal {
                controller.dismiss()
            } else {
                let _ = (controller.navigationController as? NavigationController)?.popViewController(animated: true)
            }
        }
        presentImpl = { [weak controller] c in
            controller?.present(c, in: .window(.root))
        }
        return controller
    }

    /// Entry point used by both the Files-app picker and the chat-message tap.
    /// `push` is preferred — a pushed `ItemListController` animates in and gets a back button.
    /// `present` is the fallback for callers with no navigation stack.
    public static func presentImport(
        context: AccountContext,
        data: Data,
        present: @escaping (ViewController, Any?) -> Void,
        push: ((ViewController) -> Void)? = nil
    ) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        guard let payload = decode(data) else {
            present(textAlertController(context: context, title: L("Not a Cleargram settings file", "Это не файл настроек Cleargram"), text: L("This file isn't a Cleargram settings export, or it's damaged.", "Этот файл не является экспортом настроек Cleargram или повреждён."), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), nil)
            return
        }
        if let push {
            push(importController(context: context, payload: payload, isModal: false))
        } else {
            present(importController(context: context, payload: payload, isModal: true), nil)
        }
    }

    /// Files-app picker for an import.
    public static func presentImportPicker(
        context: AccountContext,
        present: @escaping (ViewController, Any?) -> Void,
        presentNative: @escaping (UIViewController) -> Void,
        push: ((ViewController) -> Void)? = nil
    ) {
        let delegate = ClearDocumentPickerDelegate { url in
            guard let url else {
                return
            }
            let shouldStopAccess = url.startAccessingSecurityScopedResource()
            let data = try? Data(contentsOf: url)
            if shouldStopAccess {
                url.stopAccessingSecurityScopedResource()
            }
            guard let data else {
                return
            }
            presentImport(context: context, data: data, present: present, push: push)
        }
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .data], asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: ["public.json", "public.data"], in: .import)
        }
        picker.delegate = delegate
        // The delegate is unowned by UIKit — keep it alive for the lifetime of the picker.
        objc_setAssociatedObject(picker, &clearDocumentPickerDelegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        presentNative(picker)
    }
}

private var clearDocumentPickerDelegateKey: UInt8 = 0

private final class ClearDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
        super.init()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.completion(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.completion(nil)
    }
}

// MARK: - Chat message interception

extension ClearSettingsTransfer {
    /// Does this file look like a Cleargram settings export?
    public static func isSettingsFile(fileName: String?) -> Bool {
        guard let fileName else {
            return false
        }
        return (fileName as NSString).pathExtension.lowercased() == fileExtension
    }

    /// Called from the stock document-tap path. Loads the already-downloaded file and shows the
    /// import screen; returns false when the resource isn't local yet, so stock handles the tap.
    public static func handleSettingsFile(
        context: AccountContext,
        file: TelegramMediaFile,
        present: @escaping (ViewController, Any?) -> Void,
        push: ((ViewController) -> Void)? = nil
    ) -> Bool {
        guard isSettingsFile(fileName: file.fileName) else {
            return false
        }
        guard Int(file.size ?? 0) <= maxFileSize else {
            return false
        }
        guard let path = context.engine.resources.completedResourcePath(id: EngineMediaResource(file.resource).id) else {
            return false
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), decode(data) != nil else {
            return false
        }
        presentImport(context: context, data: data, present: present, push: push)
        return true
    }
}
