import Foundation
import SwiftSignalKit
import AccountContext
import UniversalMediaPlayer
import TelegramUIPreferences

// Scrobbles the music player to Last.fm.
//
// Fed from the one place that already knows what the music player is doing —
// `MediaManagerImpl`'s `musicMediaPlayerState` subscription, right next to the stock
// `MusicListenTracker`, which this is modelled on: same accumulate-position bookkeeping, same
// track-switch detection, different destination.
//
// Only the music player is watched, so voice messages and round videos never reach it.
//
// Last.fm's own submission rules are what decide when a track counts as played:
//   - the track must be longer than 30 seconds;
//   - it must have been played for at least half its length, or four minutes, whichever comes
//     first.
// Playtime is accumulated from the player's own position, so seeking backwards to replay a
// chorus doesn't count twice and skipping forward doesn't count at all.
//
// The scrobble is sent as soon as the threshold is crossed rather than at the end of the track:
// the app can be killed at any moment, and a scrobble that was already earned should survive it.

public final class ClearScrobbler {
    public static let shared = ClearScrobbler()

    // Last.fm: tracks shorter than this are never scrobbled.
    private static let minimumTrackDuration: Double = 30.0
    // ... and four minutes of playback is always enough, however long the track is.
    private static let maximumRequiredPlayback: Double = 240.0

    private var currentStableId: AnyHashable?
    private var artist: String = ""
    private var track: String = ""
    private var trackDuration: Double = 0.0

    // Position-based accumulation, same bookkeeping as MusicListenTracker.
    private var accumulatedDuration: Double = 0.0
    private var lastPosition: Double = 0.0
    private var lastGenerationTimestamp: Double = 0.0
    private var lastBaseRate: Double = 1.0
    private var lastSeekId: Int = 0
    private var isPlaying: Bool = false

    private var startedAtTimestamp: Int32 = 0
    private var didSendNowPlaying: Bool = false
    private var didScrobble: Bool = false

    private init() {
    }

    // Called for every music player state update, and with nil when the player closes.
    public func update(state: SharedMediaPlayerItemPlaybackStateOrLoading?, type: MediaManagerPlayerType?) {
        assert(Queue.mainQueue().isCurrent())

        guard ClearConfig.lastFmScrobbling else {
            // Turning the toggle off mid-track drops the session rather than scrobbling it.
            self.resetSession()
            return
        }
        guard let state, type == .music else {
            self.finishSession()
            return
        }
        guard case let .state(playbackState) = state else {
            return // still loading, nothing to measure yet
        }

        let stableId = playbackState.item.stableId
        if let currentStableId = self.currentStableId, currentStableId != stableId {
            self.finishSession()
        }
        if self.currentStableId == nil {
            self.startSession(item: playbackState.item, status: playbackState.status)
        }
        self.currentStableId = stableId

        self.processStatus(playbackState.status)
    }

    public func playerClosed() {
        assert(Queue.mainQueue().isCurrent())
        self.finishSession()
    }

    // MARK: - Session

    private func startSession(item: SharedMediaPlaylistItem, status: MediaPlayerStatus) {
        guard let metadata = ClearScrobbler.metadata(item.displayData) else {
            return
        }
        self.artist = metadata.artist
        self.track = metadata.track
        self.trackDuration = status.duration
        self.accumulatedDuration = 0.0
        self.lastPosition = status.timestamp
        self.lastGenerationTimestamp = status.generationTimestamp
        self.lastBaseRate = status.baseRate
        self.lastSeekId = status.seekId
        self.isPlaying = false
        self.startedAtTimestamp = Int32(Date().timeIntervalSince1970)
        self.didSendNowPlaying = false
        self.didScrobble = false
    }

    private func processStatus(_ status: MediaPlayerStatus) {
        guard !self.artist.isEmpty, !self.track.isEmpty else {
            return
        }

        let wasPlaying = self.isPlaying
        let nowPlaying: Bool
        switch status.status {
        case .playing:
            nowPlaying = true
        case let .buffering(_, whilePlaying, _, _):
            nowPlaying = whilePlaying
        case .paused:
            nowPlaying = false
        }

        // Accumulate only forward progress that the wall clock can account for — a seek or a
        // jump larger than elapsed real time is not playback.
        let seekOccurred = status.seekId != self.lastSeekId
        if wasPlaying && !seekOccurred {
            let positionDelta = status.timestamp - self.lastPosition
            let wallDelta = status.generationTimestamp - self.lastGenerationTimestamp
            let maxExpected = wallDelta * max(self.lastBaseRate, 0.5) * 1.5
            if positionDelta > 0 && (wallDelta <= 0 || positionDelta <= maxExpected) {
                self.accumulatedDuration += positionDelta
            }
        }

        self.lastPosition = status.timestamp
        self.lastGenerationTimestamp = status.generationTimestamp
        self.lastBaseRate = status.baseRate
        self.lastSeekId = status.seekId
        if status.duration > 0.0 {
            self.trackDuration = status.duration
        }
        self.isPlaying = nowPlaying

        if nowPlaying && !wasPlaying && !self.didSendNowPlaying {
            self.didSendNowPlaying = true
            if ClearConfig.lastFmNowPlaying {
                ClearLastFm.updateNowPlaying(artist: self.artist, track: self.track, duration: Int32(self.trackDuration))
            }
        }

        if nowPlaying && !self.didScrobble && self.isPlayedEnough {
            self.didScrobble = true
            self.sendScrobble()
        }
    }

    private var isPlayedEnough: Bool {
        guard self.trackDuration > ClearScrobbler.minimumTrackDuration else {
            return false
        }
        let required = min(self.trackDuration / 2.0, ClearScrobbler.maximumRequiredPlayback)
        return self.accumulatedDuration >= required
    }

    // A track that reached the threshold but wasn't submitted yet — the app went to another
    // track, or the player closed, between two status updates.
    private func finishSession() {
        if !self.didScrobble && self.isPlayedEnough && !self.artist.isEmpty && !self.track.isEmpty {
            self.didScrobble = true
            self.sendScrobble()
        }
        self.resetSession()
    }

    private func sendScrobble() {
        ClearLastFm.submit(ClearLastFmScrobble(
            artist: self.artist,
            track: self.track,
            duration: Int32(self.trackDuration),
            timestamp: self.startedAtTimestamp
        ))
    }

    private func resetSession() {
        self.currentStableId = nil
        self.artist = ""
        self.track = ""
        self.trackDuration = 0.0
        self.accumulatedDuration = 0.0
        self.lastPosition = 0.0
        self.lastGenerationTimestamp = 0.0
        self.lastBaseRate = 1.0
        self.lastSeekId = 0
        self.isPlaying = false
        self.startedAtTimestamp = 0
        self.didSendNowPlaying = false
        self.didScrobble = false
    }

    // MARK: - Metadata

    private static let fileExtensions: Set<String> = ["mp3", "m4a", "flac", "alac", "aac", "ogg", "opus", "wav", "aiff", "aif", "wma", "ape"]

    // Last.fm needs an artist and a track name. Telegram gives them straight from the file's
    // audio tags when it has them; when it doesn't, the player falls back to showing the file
    // name as the title, so the usual "Artist - Track.mp3" shape is worth unpacking. Anything
    // that still has no artist after that is not scrobbled — a wrong artist is worse in a
    // listening history than a missing play.
    static func metadata(_ displayData: SharedMediaPlaybackDisplayData?) -> (artist: String, track: String)? {
        guard let displayData, case let .music(title, performer, _, _, _, _) = displayData else {
            return nil
        }
        var trackName = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var artistName = (performer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trackName.isEmpty else {
            return nil
        }
        if artistName.isEmpty {
            trackName = strippingFileExtension(trackName)
            for separator in [" - ", " – ", " — ", " _ "] {
                if let range = trackName.range(of: separator) {
                    artistName = String(trackName[trackName.startIndex ..< range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    trackName = String(trackName[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
        }
        guard !artistName.isEmpty, !trackName.isEmpty else {
            return nil
        }
        return (artistName, trackName)
    }

    private static func strippingFileExtension(_ name: String) -> String {
        guard let dotIndex = name.lastIndex(of: ".") else {
            return name
        }
        let ext = String(name[name.index(after: dotIndex)...]).lowercased()
        guard fileExtensions.contains(ext) else {
            return name
        }
        return String(name[name.startIndex ..< dotIndex])
    }
}
