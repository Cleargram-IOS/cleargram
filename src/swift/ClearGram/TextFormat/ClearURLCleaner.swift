import Foundation

// URL cleaner: strips common tracking query params and applies preview-link replacements.
// Gated by ClearConfig.stripTrackingParams / ClearConfig.replacePreviewLinks (read by callers).
// Lives in TextFormat so it can be used from chat text processing without extra deps.

public enum ClearURLCleaner {

    // Common tracking params (utm_*, fbclid, gclid, etc.).
    // Prefix entries must be unambiguous: "ref" is NOT a prefix — it would also eat
    // `referrer`, `refresh`, `refid`, which are load-bearing on some sites. It is matched
    // exactly instead, alongside the "ref_" prefix (ref_src, ref_url, …).
    private static let trackingParamPrefixes: Set<String> = [
        "utm_", "fbclid", "gclid", "dclid", "msclkid", "yclid", "twclid",
        "mc_", "mkt_", "_hs", "hsCtaTracking", "igshid", "ref_",
        "spm", "scm", "srsltid", "sms_ss", "at_campaign", "at_medium",
        "at_custom", "at_recipient", "hsa_", "vero_", "oly_", "sb_",
    ]

    private static let exactTrackingParams: Set<String> = [
        "gclid", "dclid", "msclkid", "yclid", "twclid", "igshid", "spm",
        "scm", "srsltid", "sms_ss", "hsCtaTracking", "ref",
    ]

    public static func stripTrackingParams(url: String) -> String {
        guard let comp = URLComponents(string: url) else { return url }
        // percentEncoded* on both sides: round-tripping through `queryItems` would re-encode
        // every surviving param, mangling values that were already escaped by the sender.
        guard let queryItems = comp.percentEncodedQueryItems, !queryItems.isEmpty else { return url }

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
            stripped.percentEncodedQueryItems = kept
        }
        return stripped.url?.absoluteString ?? url
    }

    // Preview-link replacements (twitter.com→fixupx.com, bsky.app→fxbsky.app, etc.)
    private struct Replacement {
        let pattern: String
        let host: String
        let replacement: String
    }

    // Patterns MUST be anchored (^…$) and match the WHOLE host. Unanchored patterns match any
    // host that merely *contains* them — `netflix.com`/`dropbox.com` contain `x.com`,
    // `notinstagram.com` contains `instagram.com` — and since the match replaces the entire
    // host below, such a URL would be silently rewritten to the frontend, handing its path
    // (which can carry a secret token) to a third party the user never chose.
    private static let replacements: [Replacement] = [
        Replacement(pattern: "^(?:www\\.)?(?:x|twitter)\\.com$", host: "fixupx.com", replacement: "fixupx.com"),
        Replacement(pattern: "^(?:www\\.)?instagram\\.com$", host: "kkclip.com", replacement: "kkclip.com"),
        Replacement(pattern: "^(?:vm|vt|www)\\.tiktok\\.com$", host: "kktiktok.com", replacement: "$0.kktiktok.com"),
        Replacement(pattern: "^(?:www\\.)?reddit\\.com$", host: "rxddit.com", replacement: "www.rxddit.com"),
        Replacement(pattern: "^(?:www\\.)?bsky\\.app$", host: "fxbsky.app", replacement: "fxbsky.app"),
        Replacement(pattern: "^(?:www\\.)?pixiv\\.net$", host: "phixiv.net", replacement: "www.phixiv.net"),
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
