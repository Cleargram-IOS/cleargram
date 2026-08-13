import Foundation

// Codec + bitrate label for the music player subtitle.
//
// ALAC and AAC share the MP4/M4A container *and* the mime type, so the mime alone can never tell
// them apart — that is why plain "audio/x-m4a" used to render as "AAC" for lossless files. The
// detection ladder, best first:
//
//   1. an explicit mime (audio/x-alac, audio/flac, …)
//   2. the container's `stsd` sample-entry fourcc (`alac` vs `mp4a`), read off the local file
//   3. the bitrate heuristic — lossless is far above what AAC can reach
//   4. the file extension, for senders that ship music as application/octet-stream
//
// Step 2 is authoritative but needs the file to be fully downloaded; music streams, so step 3
// carries the first render of a track more often than not.

// MARK: - Tunables

/// Above this container bitrate an MP4/M4A track is assumed lossless rather than AAC. AAC tops out
/// around 320 kbps (VBR peaks ~400); ALAC of 16-bit/44.1 kHz stereo lands at ~500-1000 kbps and
/// hi-res 24/96 at 2000-4000.
private let clearLosslessBitrateThresholdKbps: Int = 500

/// The bitrate heuristic is only trusted for tracks this long. Embedded cover art (often 1-3 MB)
/// inflates the computed container bitrate — on a 30-second clip that alone can add 500+ kbps and
/// fake a lossless verdict.
private let clearBitrateHeuristicMinDuration: TimeInterval = 60.0

/// How many sniff results to memoize.
private let clearSniffCacheLimit = 64

// MARK: - Memo cache

// Sniffing is deterministic per local file, and the playlist rebuilds display data for the
// current/previous/next track on every change, so memoize by path.
private final class ClearAudioSniffCache {
    static let shared = ClearAudioSniffCache()
    private let lock = NSLock()
    private var order: [String] = []
    private var values: [String: String?] = [:]

    func value(for path: String) -> String?? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.values[path]
    }

    func store(_ codec: String?, for path: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.values[path] == nil {
            self.order.append(path)
            if self.order.count > clearSniffCacheLimit {
                let evicted = self.order.removeFirst()
                self.values.removeValue(forKey: evicted)
            }
        }
        self.values[path] = codec
    }
}

// MARK: - Public entry point

public func clearAudioFormatInfo(
    mimeType: String,
    fileName: String? = nil,
    size: Int64?,
    duration: TimeInterval?,
    localPath: String? = nil
) -> String? {
    let ext = fileName.flatMap { ($0 as NSString).pathExtension.lowercased() } ?? ""

    var codec = clearCodecFromMimeType(mimeType, ext: ext)

    var bitrate: Int?
    if let size = size, let duration = duration, duration > 0 {
        bitrate = Int((Double(size) * 8.0) / (duration * 1000.0))
    }

    if clearIsAmbiguousMp4Audio(mimeType: mimeType, ext: ext) {
        if let localPath = localPath, let sniffed = clearSniffContainerCodec(path: localPath) {
            codec = sniffed
        } else if let bitrate = bitrate,
                  let duration = duration,
                  duration >= clearBitrateHeuristicMinDuration,
                  bitrate > clearLosslessBitrateThresholdKbps {
            codec = "ALAC"
        }
    }

    guard let bitrate = bitrate else {
        return codec
    }
    return "\(codec) · \(bitrate) kbps"
}

// MARK: - Mime / extension mapping

private func clearCodecFromMimeType(_ mimeType: String, ext: String) -> String {
    switch mimeType.lowercased() {
    case "audio/mpeg", "audio/mp3", "audio/x-mpeg": return "MP3"
    case "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/aac", "audio/aacp", "audio/x-aac": return "AAC"
    case "audio/alac", "audio/x-alac": return "ALAC"
    case "audio/ogg", "application/ogg", "audio/vorbis": return "OGG"
    case "audio/flac", "audio/x-flac": return "FLAC"
    case "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave": return "WAV"
    case "audio/aiff", "audio/x-aiff": return "AIFF"
    case "audio/opus": return "OPUS"
    case "audio/x-ms-wma": return "WMA"
    case "audio/x-caf", "audio/caf": return "CAF"
    default:
        // Some senders ship music as application/octet-stream — lean on the extension.
        switch ext {
        case "mp3": return "MP3"
        case "m4a", "m4b", "mp4", "aac": return "AAC"
        case "alac": return "ALAC"
        case "flac": return "FLAC"
        case "wav": return "WAV"
        case "aif", "aiff": return "AIFF"
        case "ogg", "oga": return "OGG"
        case "opus": return "OPUS"
        case "ape": return "APE"
        case "wv": return "WAVPACK"
        case "caf": return "CAF"
        default: break
        }
        return mimeType
            .replacingOccurrences(of: "audio/", with: "")
            .replacingOccurrences(of: "x-", with: "")
            .uppercased()
    }
}

private func clearIsAmbiguousMp4Audio(mimeType: String, ext: String) -> Bool {
    switch mimeType.lowercased() {
    case "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/x-caf", "audio/caf":
        return true
    case "application/octet-stream", "":
        return ext == "m4a" || ext == "m4b" || ext == "mp4" || ext == "caf"
    default:
        return false
    }
}

// MARK: - Container sniffing

private func clearSniffContainerCodec(path: String) -> String? {
    if let cached = ClearAudioSniffCache.shared.value(for: path) {
        return cached
    }
    var result: String?
    if let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) {
        result = clearSniffCAF(data) ?? clearSniffISOBMFF(data)
    }
    ClearAudioSniffCache.shared.store(result, for: path)
    return result
}

private func clearU32(_ d: Data, _ offset: Int) -> UInt32? {
    guard offset >= 0, offset + 4 <= d.count else {
        return nil
    }
    let b = d.startIndex + offset
    return (UInt32(d[b]) << 24) | (UInt32(d[b + 1]) << 16) | (UInt32(d[b + 2]) << 8) | UInt32(d[b + 3])
}

private func clearU16(_ d: Data, _ offset: Int) -> UInt16? {
    guard offset >= 0, offset + 2 <= d.count else {
        return nil
    }
    let b = d.startIndex + offset
    return (UInt16(d[b]) << 8) | UInt16(d[b + 1])
}

private func clearFourCC(_ d: Data, _ offset: Int) -> String? {
    guard offset >= 0, offset + 4 <= d.count else {
        return nil
    }
    let b = d.startIndex + offset
    return String(bytes: [d[b], d[b + 1], d[b + 2], d[b + 3]], encoding: .ascii)
}

/// Enumerates the direct children of an ISO-BMFF container in [start, end), calling `body` with
/// (type, contentStart, contentEnd). Return true from `body` to stop.
private func clearEnumerateBoxes(_ d: Data, _ start: Int, _ end: Int, _ body: (String, Int, Int) -> Bool) {
    var offset = start
    while offset + 8 <= end {
        guard let rawSize = clearU32(d, offset), let type = clearFourCC(d, offset + 4) else {
            return
        }
        var boxSize = Int(rawSize)
        var headerSize = 8
        if boxSize == 1 {
            guard let hi = clearU32(d, offset + 8), let lo = clearU32(d, offset + 12) else {
                return
            }
            let large = (UInt64(hi) << 32) | UInt64(lo)
            guard large <= UInt64(Int.max) else {
                return
            }
            boxSize = Int(large)
            headerSize = 16
        } else if boxSize == 0 {
            boxSize = end - offset
        }
        guard boxSize >= headerSize, offset + boxSize <= end else {
            return
        }
        if body(type, offset + headerSize, offset + boxSize) {
            return
        }
        offset += boxSize
    }
}

private func clearChild(_ d: Data, _ start: Int, _ end: Int, _ type: String) -> Range<Int>? {
    var found: Range<Int>?
    clearEnumerateBoxes(d, start, end) { t, s, e in
        if t == type {
            found = s ..< e
            return true
        }
        return false
    }
    return found
}

private func clearSniffISOBMFF(_ d: Data) -> String? {
    // Sanity: the first top-level box of an MP4 is normally ftyp.
    guard let first = clearFourCC(d, 4),
          first == "ftyp" || first == "moov" || first == "free" || first == "mdat" || first == "skip" || first == "wide"
    else {
        return nil
    }
    guard let moov = clearChild(d, 0, d.count, "moov") else {
        return nil
    }

    var codec: String?
    // A file can hold several traks (audio + chapter/text). Take the first one whose stsd carries
    // a recognised audio sample entry.
    clearEnumerateBoxes(d, moov.lowerBound, moov.upperBound) { type, tStart, tEnd in
        guard type == "trak" else {
            return false
        }
        guard let mdia = clearChild(d, tStart, tEnd, "mdia"),
              let minf = clearChild(d, mdia.lowerBound, mdia.upperBound, "minf"),
              let stbl = clearChild(d, minf.lowerBound, minf.upperBound, "stbl"),
              let stsd = clearChild(d, stbl.lowerBound, stbl.upperBound, "stsd")
        else {
            return false
        }

        // stsd is a FullBox: version+flags(4), entry_count(4), then the sample entries.
        let entryStart = stsd.lowerBound + 8
        guard entryStart + 8 <= stsd.upperBound,
              let entrySize = clearU32(d, entryStart),
              let format = clearFourCC(d, entryStart + 4)
        else {
            return false
        }
        let entryEnd = min(stsd.upperBound, entryStart + Int(entrySize))

        switch format {
        case "alac":
            codec = clearALACDetail(d, entryStart: entryStart, entryEnd: entryEnd) ?? "ALAC"
            return true
        case "mp4a":
            codec = "AAC"
            return true
        case "fLaC":
            codec = "FLAC"
            return true
        case "Opus":
            codec = "OPUS"
            return true
        case "ac-3":
            codec = "AC3"
            return true
        case "ec-3":
            codec = "EAC3"
            return true
        case ".mp3", "mp3 ":
            codec = "MP3"
            return true
        case "lpcm", "sowt", "twos", "in24", "in32", "raw ":
            codec = "PCM"
            return true
        default:
            return false // keep scanning the other traks
        }
    }
    return codec
}

/// Reads ALAC's magic cookie (ALACSpecificConfig) so the label can say "ALAC 24-bit/96 kHz".
/// Returns nil when the cookie cannot be located, in which case the caller says plain "ALAC".
private func clearALACDetail(_ d: Data, entryStart: Int, entryEnd: Int) -> String? {
    // AudioSampleEntry: size(4) format(4) reserved(6) dataRefIndex(2)
    //                   version(2) revision(2) vendor(4) channels(2) sampleSize(2)
    //                   compressionId(2) packetSize(2) sampleRate(4)  == 36 bytes
    guard let soundVersion = clearU16(d, entryStart + 16) else {
        return nil
    }
    var childStart = entryStart + 36
    if soundVersion == 1 {
        childStart += 16
    } else if soundVersion == 2 {
        childStart += 36
    }
    guard let cookieBox = clearChild(d, childStart, entryEnd, "alac") else {
        return nil
    }
    // The inner 'alac' box is a FullBox: version+flags(4), then the 24-byte ALACSpecificConfig:
    // frameLength(4) compatibleVersion(1) bitDepth(1) pb(1) mb(1) kb(1) numChannels(1)
    // maxRun(2) maxFrameBytes(4) avgBitRate(4) sampleRate(4)
    let cfg = cookieBox.lowerBound + 4
    guard cfg + 24 <= cookieBox.upperBound else {
        return nil
    }
    let bitDepth = d[d.startIndex + cfg + 5]
    guard let sampleRate = clearU32(d, cfg + 20), sampleRate > 0 else {
        return nil
    }
    let khz = Double(sampleRate) / 1000.0
    let khzString = khz == khz.rounded() ? String(Int(khz)) : String(format: "%.1f", khz)
    return "ALAC \(bitDepth)-bit/\(khzString) kHz"
}

/// Core Audio Format (.caf) — 'caff'(4) version(2) flags(2), then chunk type(4) size(8) payload.
/// The first chunk must be 'desc': mSampleRate(Float64, 8) then mFormatID(4).
private func clearSniffCAF(_ d: Data) -> String? {
    guard clearFourCC(d, 0) == "caff" else {
        return nil
    }
    guard clearFourCC(d, 8) == "desc", let formatID = clearFourCC(d, 28) else {
        return nil
    }
    switch formatID {
    case "alac": return "ALAC"
    case "aac ": return "AAC"
    case "lpcm": return "PCM"
    case "flac": return "FLAC"
    case ".mp3": return "MP3"
    default: return nil
    }
}
