import Foundation
import UIKit
import AsyncDisplayKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramUIPreferences

// Cache state of the playing track, plus the small indicator that shows it next to the track
// title in the three surfaces that never had one: the fullscreen player and both mini panels.
// (Lists of music already get a stock `SemanticStatusNode` in `ListMessageFileItemNode`.)
//
// This lives in AccountContext because those three surfaces sit in three different modules
// (TelegramUI, TelegramBaseController, MediaPlaybackHeaderPanelComponent) and AccountContext is
// the lowest one all of them already depend on. The indicator draws itself with CAShapeLayer
// rather than borrowing `RadialStatusNode`, so no module gains a new BUILD dependency for it.

public enum ClearTrackCacheState: Equatable {
    /// Not stored locally, nothing running.
    case remote
    /// Downloading; the value is 0…1, or nil while the size is still unknown.
    case fetching(Float?)
    /// Fully downloaded.
    case local
}

/// Cache state of a music file, with a queued track reported as `.fetching(nil)` — a dim arc rather
/// than nothing. The downloader only runs three fetches at a time, so most of a queued playlist is
/// still `.remote`, and showing that as "not downloaded" gives no sign the request landed at all.
public func clearTrackCacheStateQueueAware(mediaBox: MediaBox, file: TelegramMediaFile?) -> Signal<ClearTrackCacheState?, NoError> {
    guard ClearConfig.showTrackCacheStatus, let file else {
        return .single(nil)
    }
    let id = file.resource.id
    return combineLatest(
        clearTrackCacheStatusSignal(mediaBox: mediaBox, resource: file.resource),
        ClearPlaylistDownloader.shared.queuedIds
    )
    |> map { state, queued -> ClearTrackCacheState? in
        if case .remote = state, queued.contains(id) {
            return .fetching(nil)
        }
        return state
    }
    |> distinctUntilChanged
}

/// Cache state of a playlist item, or nil when the feature is off or the item isn't a plain file
/// (the toggle is read here so call sites stay one-liners).
public func clearTrackCacheState(context: AccountContext, item: SharedMediaPlaylistItem?) -> Signal<ClearTrackCacheState?, NoError> {
    return clearTrackCacheState(mediaBox: context.account.postbox.mediaBox, item: item)
}

/// Same, for call sites that hold an `Account` rather than an `AccountContext` — the fullscreen
/// player is built from `account`/`engine`, not from a context.
public func clearTrackCacheState(mediaBox: MediaBox, file: TelegramMediaFile?) -> Signal<ClearTrackCacheState?, NoError> {
    guard ClearConfig.showTrackCacheStatus, let file else {
        return .single(nil)
    }
    return clearTrackCacheStatusSignal(mediaBox: mediaBox, resource: file.resource)
}

public func clearTrackCacheState(mediaBox: MediaBox, item: SharedMediaPlaylistItem?) -> Signal<ClearTrackCacheState?, NoError> {
    guard ClearConfig.showTrackCacheStatus else {
        return .single(nil)
    }
    guard let item, let playbackData = item.playbackData else {
        return .single(nil)
    }
    // Only music carries a title to sit next to; voice and round videos are excluded on purpose.
    guard case .music = playbackData.type else {
        return .single(nil)
    }
    guard case let .telegramFile(reference, _, _) = playbackData.source else {
        return .single(nil)
    }
    return clearTrackCacheStatusSignal(mediaBox: mediaBox, resource: reference.media.resource)
}

/// The music file in a message that is worth offering an "unload" action for: it has to be music
/// and it has to actually be on disk. `completedResourcePath` answers that synchronously, which is
/// what lets the check sit inside a context-menu builder instead of turning it into a signal.
public func clearUnloadableMusicFile(context: AccountContext, media: [Media]) -> TelegramMediaFile? {
    guard ClearConfig.unloadTrackFromCache else {
        return nil
    }
    for item in media {
        guard let file = item as? TelegramMediaFile, file.isMusic else {
            continue
        }
        guard context.account.postbox.mediaBox.completedResourcePath(file.resource) != nil else {
            return nil
        }
        return file
    }
    return nil
}

/// Drop the local copy of a track, keeping the message. Same call the stock Downloads list makes
/// for a single file (`ChatListSearchContainerNode`), and deliberately not `force`: the track may
/// be the one playing, and a forced removal yanks the file out from under the player.
public func clearUnloadTrackFromCache(engine: TelegramEngine, file: TelegramMediaFile?) {
    guard let file else {
        return
    }
    let _ = engine.resources.removeCachedResources(ids: [EngineMediaResource.Id(file.resource.id)], notify: true).start()
}

private func clearTrackCacheStatusSignal(mediaBox: MediaBox, resource: MediaResource) -> Signal<ClearTrackCacheState?, NoError> {
    // `mediaBox.resourceStatus` answers `.Local` and **completes** for a cached file: MediaBox checks
    // the complete-file path first and never registers a live status context in that branch. The
    // `notify` pass of `removeCachedResources` pushes `.Remote` only to live contexts, so a completed
    // subscription had no way to learn about an unload — every surface (list rows, mini panels, the
    // player) kept showing "downloaded" until the screen was reopened. Restarting the status
    // subscription on the media box's removal event keeps the signal alive instead: a removal
    // anywhere (the unload action, cache cleanup, eviction) re-checks this one file, and the fresh
    // subscription reports `.Remote` right away.
    return mediaBox.didRemoveResources
    |> mapToSignal { _ -> Signal<MediaResourceStatus, NoError> in
        return mediaBox.resourceStatus(resource)
    }
    |> map { status -> ClearTrackCacheState? in
        switch status {
        case .Local:
            return .local
        case let .Fetching(_, progress), let .Paused(progress):
            return .fetching(progress)
        case .Remote:
            return .remote
        }
    }
    |> distinctUntilChanged
}

// `UIScreenPixel` lives in Display, which AccountContext does not depend on — plain value.
private let clearIndicatorLineWidth: CGFloat = 1.5

public final class ClearTrackCacheIndicatorNode: ASDisplayNode {
    /// What the indicator is for, because the two surfaces want opposite things.
    public enum Style {
        /// Beside a single title, in the player and the mini panels: report what is *missing*.
        /// An arrow while the track is remote, an arc while it downloads, and nothing once it is
        /// cached — a permanent mark there says nothing and keeps the title off centre.
        case status
        /// In a list of tracks: mark what is *available offline*, the way a music app does — an
        /// arrow on the cached rows, an arc on the one downloading, and nothing on the rest, so the
        /// eye picks out what is already there instead of what is not.
        case library
    }

    public static let size = CGSize(width: 14.0, height: 14.0)

    private let ringLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let glyphLayer = CAShapeLayer()

    private var state: ClearTrackCacheState?
    private var color: UIColor = .white
    // Not `style`: `ASDisplayNode` already has one, of type `ASLayoutElementStyle`.
    private var indicatorStyle: Style = .status


    override public init() {
        super.init()

        self.isUserInteractionEnabled = false
        self.isLayerBacked = true
    }

    // Sublayers are attached here, not in `init`, because `ASDisplayNode.layer` asserts off the
    // main thread and `ListView` builds its item nodes on a background queue
    // (`ListMessageItem.nodeConfiguredForParams(async:)`). The player and the mini panels construct
    // this node on main, so touching `layer` in `init` worked there and crashed the moment a list
    // row needed one — abort in `-[ASDisplayNode layer]`, on scroll, as soon as a new row was made.
    // `didLoad` is the guaranteed on-main hook.
    override public func didLoad() {
        super.didLoad()

        for sublayer in [self.ringLayer, self.progressLayer, self.glyphLayer] {
            sublayer.fillColor = nil
            sublayer.lineCap = .round
            sublayer.lineWidth = clearIndicatorLineWidth
            self.layer.addSublayer(sublayer)
        }
        // The progress arc starts at twelve o'clock; the layer is rotated rather than the path so
        // that `strokeEnd` stays a plain 0…1 value.
        self.progressLayer.transform = CATransform3DMakeRotation(-CGFloat.pi / 2.0, 0.0, 0.0, 1.0)

        // State may have arrived before the node loaded; nothing was drawn then.
        self.updateLayers()
    }

    /// Hidden when there is nothing worth marking: no state at all, a cached track in `.status`,
    /// or a remote one in `.library`.
    public func update(state: ClearTrackCacheState?, color: UIColor, style: Style = .status) {
        guard state != self.state || color != self.color || style != self.indicatorStyle else {
            return
        }
        self.state = state
        self.color = color
        self.indicatorStyle = style

        var isEmpty = state == nil
        switch (state, style) {
        case (.local, .status), (.remote, .library):
            isEmpty = true
        default:
            break
        }
        self.isHidden = isEmpty

        self.updateLayers()
    }

    override public func layout() {
        super.layout()
        self.updateLayers()
    }

    private func updateLayers() {
        let size = self.bounds.size
        guard size.width > 0.0, size.height > 0.0, let state = self.state else {
            return
        }
        let inset = clearIndicatorLineWidth / 2.0
        let circleRect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        let circlePath = UIBezierPath(ovalIn: circleRect).cgPath

        for sublayer in [self.ringLayer, self.progressLayer, self.glyphLayer] {
            sublayer.frame = CGRect(origin: .zero, size: size)
            sublayer.strokeColor = self.color.cgColor
        }
        self.progressLayer.position = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        self.progressLayer.bounds = CGRect(origin: .zero, size: size)

        switch state {
        case .local:
            self.ringLayer.path = circlePath
            self.ringLayer.opacity = 1.0
            self.progressLayer.path = nil
            // `.library` marks a cached row with the download glyph, which is what a music app
            // uses for "you have this offline"; the tick only ever shows in `.status`, where a
            // cached track hides the node anyway.
            self.glyphLayer.path = self.indicatorStyle == .library ? self.arrowPath(in: size) : self.checkPath(in: size)
        case let .fetching(progress):
            self.ringLayer.path = circlePath
            // The unfilled part of the ring stays visible but dim, so the arc reads as a share of
            // a whole rather than as a lone stroke of unknown length.
            self.ringLayer.opacity = 0.3
            self.progressLayer.path = circlePath
            self.progressLayer.strokeEnd = CGFloat(max(0.02, min(1.0, progress ?? 0.02)))
            self.glyphLayer.path = nil
        case .remote:
            self.ringLayer.path = circlePath
            self.ringLayer.opacity = 1.0
            self.progressLayer.path = nil
            self.glyphLayer.path = self.arrowPath(in: size)
        }
    }

    private func checkPath(in size: CGSize) -> CGPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: size.width * 0.28, y: size.height * 0.52))
        path.addLine(to: CGPoint(x: size.width * 0.44, y: size.height * 0.68))
        path.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.36))
        return path.cgPath
    }

    private func arrowPath(in size: CGSize) -> CGPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: size.width * 0.5, y: size.height * 0.26))
        path.addLine(to: CGPoint(x: size.width * 0.5, y: size.height * 0.7))
        path.move(to: CGPoint(x: size.width * 0.31, y: size.height * 0.51))
        path.addLine(to: CGPoint(x: size.width * 0.5, y: size.height * 0.7))
        path.addLine(to: CGPoint(x: size.width * 0.69, y: size.height * 0.51))
        return path.cgPath
    }
}

// MARK: - Downloading a whole playlist

/// Queues the chat's music around a track for download, oldest fetch first, a few at a time.
///
/// The playlist object itself is no help here: `SharedMediaPlaylist` exposes only the current item
/// and navigation, never a list — `PeerMessagesMediaPlaylist` walks the history one message at a
/// time. So the list is rebuilt the way the stock Music pane builds its own: a `.music`-tagged
/// history view around the anchor message.
///
/// The cap is not cosmetic. Every fetch joins the same `MultipartFetch` queue the app uses for
/// everything else, so an uncapped "download all" both invites a flood-wait and starves whatever
/// the user is actually looking at; `clearMaxConcurrentTrackFetches` keeps the queue short and the
/// limit keeps it finite.
private let clearMaxConcurrentTrackFetches = 3

public final class ClearPlaylistDownloader {
    public static let shared = ClearPlaylistDownloader()

    private let lock = NSLock()
    private var active: [MediaResourceId: Disposable] = [:]
    private var pending: [(MediaBox, MediaResourceReference, MediaResourceId)] = []
    // Ids sitting in `pending`. Published so a list row can say "waiting" instead of showing
    // nothing at all: with only three fetches in flight, most of a queued playlist looks untouched
    // otherwise, and there is no way to tell it was even asked for.
    private let queuedPromise = ValuePromise<Set<MediaResourceId>>(Set(), ignoreRepeated: true)

    public var queuedIds: Signal<Set<MediaResourceId>, NoError> {
        return self.queuedPromise.get()
    }

    private init() {
    }

    /// Called with the lock held.
    private func publishQueued() {
        self.queuedPromise.set(Set(self.pending.map { $0.2 }))
    }

    fileprivate func enqueue(mediaBox: MediaBox, reference: MediaResourceReference, id: MediaResourceId) {
        self.lock.lock()
        if self.active[id] != nil || self.pending.contains(where: { $0.2 == id }) {
            self.lock.unlock()
            return
        }
        self.pending.append((mediaBox, reference, id))
        self.publishQueued()
        self.lock.unlock()
        self.pump()
    }

    private func pump() {
        self.lock.lock()
        guard self.active.count < clearMaxConcurrentTrackFetches, !self.pending.isEmpty else {
            self.lock.unlock()
            return
        }
        let (mediaBox, reference, id) = self.pending.removeFirst()
        let disposable = MetaDisposable()
        self.active[id] = disposable
        self.publishQueued()
        self.lock.unlock()

        disposable.set(fetchedMediaResource(
            mediaBox: mediaBox,
            userLocation: .other,
            userContentType: .audio,
            reference: reference
        ).start(error: { [weak self] _ in
            self?.finish(id: id)
        }, completed: { [weak self] in
            self?.finish(id: id)
        }))
    }

    private func finish(id: MediaResourceId) {
        self.lock.lock()
        self.active.removeValue(forKey: id)
        self.lock.unlock()
        self.pump()
    }
}

/// How many tracks a "download the playlist" action would queue right now, or nil when the action
/// should not be offered at all (feature off, or the message isn't music).
public func clearPlaylistDownloadLimit(context: AccountContext, media: [Media]) -> Int32? {
    guard ClearConfig.downloadPlaylist else {
        return nil
    }
    guard media.contains(where: { ($0 as? TelegramMediaFile)?.isMusic == true }) else {
        return nil
    }
    return ClearConfig.playlistDownloadLimit
}

public func clearDownloadPlaylist(context: AccountContext, message: Message) {
    let limit = Int(ClearConfig.playlistDownloadLimit)
    guard limit > 0 else {
        return
    }
    // Thread-scoped playlists fall back to the whole chat's music: the anchor keeps the window
    // around the right track either way, and building a ChatReplyThreadMessage by hand here would
    // be a lot of guessing for a narrow case.
    let chatLocation: ChatLocation = .peer(id: message.id.peerId)
    let contextHolder = Atomic<ChatLocationContextHolder?>(value: nil)
    let location = context.chatLocationInput(for: chatLocation, contextHolder: contextHolder)

    let _ = (context.account.viewTracker.aroundMessageHistoryViewForLocation(
        location,
        index: .message(message.index),
        anchorIndex: .message(message.index),
        count: limit,
        clipHoles: false,
        fixedCombinedReadStates: nil,
        tag: .tag(.music)
    )
    |> take(1)
    |> deliverOnMainQueue).start(next: { view, _, _ in
        let mediaBox = context.account.postbox.mediaBox
        var queued = 0
        for entry in view.entries {
            if queued >= limit {
                break
            }
            let entryMessage = entry.message
            guard let file = entryMessage.media.compactMap({ $0 as? TelegramMediaFile }).first(where: { $0.isMusic }) else {
                continue
            }
            // Already on disk — nothing to queue, and it shouldn't eat into the limit either.
            if mediaBox.completedResourcePath(file.resource) != nil {
                continue
            }
            let reference = FileMediaReference.message(message: MessageReference(entryMessage), media: file)
            ClearPlaylistDownloader.shared.enqueue(
                mediaBox: mediaBox,
                reference: reference.resourceReference(file.resource),
                id: file.resource.id
            )
            queued += 1
        }
    })
}

/// Fetch one track, for the "download just this one" row action.
///
/// Goes through `ClearPlaylistDownloader` even though there is nothing to pace, because the queue
/// is what **holds the disposable**. The first version called `fetchedMediaResource(...).start()`
/// and dropped the result on the floor — a `Signal` is cancelled the moment nothing retains its
/// disposable, so the download was torn down in the same breath it started and the menu item
/// looked like it did nothing at all.
public func clearDownloadSingleTrack(context: AccountContext, message: Message) {
    for item in message.effectiveMedia {
        guard let file = item as? TelegramMediaFile, file.isMusic else {
            continue
        }
        guard context.account.postbox.mediaBox.completedResourcePath(file.resource) == nil else {
            return
        }
        let reference = FileMediaReference.message(message: MessageReference(message), media: file)
        ClearPlaylistDownloader.shared.enqueue(
            mediaBox: context.account.postbox.mediaBox,
            reference: reference.resourceReference(file.resource),
            id: file.resource.id
        )
        return
    }
}
