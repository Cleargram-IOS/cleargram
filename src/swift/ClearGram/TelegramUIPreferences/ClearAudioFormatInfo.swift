import Foundation

public func clearAudioFormatInfo(mimeType: String, size: Int64?, duration: TimeInterval?) -> String? {
    let codec: String
    switch mimeType {
    case "audio/mpeg", "audio/mp3": codec = "MP3"
    case "audio/mp4", "audio/m4a", "audio/x-m4a": codec = "AAC"
    case "audio/ogg", "application/ogg": codec = "OGG"
    case "audio/flac", "audio/x-flac": codec = "FLAC"
    case "audio/wav", "audio/x-wav": codec = "WAV"
    case "audio/opus": codec = "OPUS"
    default: codec = mimeType.replacingOccurrences(of: "audio/", with: "").uppercased()
    }
    guard let size = size, let duration = duration, duration > 0 else {
        return codec
    }
    let bitrate = Int((Double(size) * 8.0) / (duration * 1000.0))
    return "\(codec) · \(bitrate) kbps"
}
