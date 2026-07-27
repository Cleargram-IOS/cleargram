import Foundation

// URL cleaner: strips common tracking query params and applies preview-link replacements.
// Gated by ClearConfig.stripTrackingParams / ClearConfig.replacePreviewLinks (read by callers).
// Lives in TextFormat so it can be used from chat text processing without extra deps.

public enum ClearURLCleaner {

    // Common tracking params (utm_*, fbclid, gclid, etc.)
    private static let trackingParamPrefixes: Set<String> = [
        "utm_", "fbclid", "gclid", "dclid", "msclkid", "yclid", "twclid",
        "mc_", "mkt_", "_hs", "hsCtaTracking", "igshid", "ref_", "ref",
        "spm", "scm", "srsltid", "sms_ss", "at_campaign", "at_medium",
        "at_custom", "at_recipient", "hsa_", "vero_", "oly_", "sb_",
    ]

    private static let exactTrackingParams: Set<String> = [
        "gclid", "dclid", "msclkid", "yclid", "twclid", "igshid", "spm",
        "scm", "srsltid", "sms_ss", "hsCtaTracking",
    ]

    public static func stripTrackingParams(url: String) -> String {
        guard let comp = URLComponents(string: url) else { return url }
        guard let queryItems = comp.queryItems, !queryItems.isEmpty else { return url }

        let kept = queryItems.filter { item in
            let name = item.name.lowercased()
            if exactTrackingParams.contains(name) { return false }
            for prefix in trackingParamPrefixes where name.hasPrefix(prefix) {
                return false
            }
            return true
        }
        if kept.count == queryItems.count { return url }

        var stripped = comp
        if kept.isEmpty {
            stripped.query = nil
        } else {
            stripped.queryItems = kept
        }
        return stripped.url?.absoluteString ?? url
    }

    // Preview-link replacements (twitter.com→fixupx.com, bsky.app→fxbsky.app, etc.)
    private struct Replacement {
        let pattern: String
        let host: String
        let replacement: String
    }

    private static let replacements: [Replacement] = [
        Replacement(pattern: "(?:x|twitter)\\.com", host: "fixupx.com", replacement: "fixupx.com"),
        Replacement(pattern: "(?:www\\.)?instagram\\.com", host: "kkclip.com", replacement: "kkclip.com"),
        Replacement(pattern: "(?:vm|vt|www)\\.tiktok\\.com", host: "kktiktok.com", replacement: "$0.kktiktok.com"),
        Replacement(pattern: "(?:www\\.)?reddit\\.com", host: "rxddit.com", replacement: "www.rxddit.com"),
        Replacement(pattern: "bsky\\.app", host: "fxbsky.app", replacement: "fxbsky.app"),
        Replacement(pattern: "www\\.pixiv\\.net", host: "phixiv.net", replacement: "www.phixiv.net"),
    ]

    public static func replacePreviewLink(url: String) -> String {
        guard let comp = URLComponents(string: url), let host = comp.host?.lowercased() else { return url }
        for r in replacements {
            guard let regex = try? NSRegularExpression(pattern: r.pattern, options: [.caseInsensitive]) else { continue }
            let hostRange = NSRange(host.startIndex..<host.endIndex, in: host)
            if regex.firstMatch(in: host, options: [], range: hostRange) != nil {
                var replaced = comp
                let newHost: String
                if r.replacement.contains("$0") {
                    // preserve subdomain prefix (e.g. vm.tiktok.com → vm.kktiktok.com)
                    let subdomainMatch = regex.firstMatch(in: host, options: [], range: hostRange)
                    if let subdomainRange = subdomainMatch?.range, let range = Range(subdomainRange, in: host) {
                        let matched = String(host[range])
                        newHost = r.replacement.replacingOccurrences(of: "$0", with: matched.components(separatedBy: ".").first ?? matched)
                    } else {
                        newHost = r.host
                    }
                } else {
                    newHost = r.host
                }
                replaced.host = newHost
                return replaced.url?.absoluteString ?? url
            }
        }
        return url
    }

    // Convenience: apply both stripping and replacement if enabled flags are passed.
    public static func clean(url: String, strip: Bool, replace: Bool) -> String {
        var result = url
        if replace { result = replacePreviewLink(url: result) }
        if strip { result = stripTrackingParams(url: result) }
        return result
    }
}
