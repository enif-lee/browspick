import Foundation

public enum URLCleaner {
    /// Common click-tracking parameters. Deliberately conservative — entries that are
    /// load-bearing on some sites (ref, ved, si) are left out.
    public static let trackingParams: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "utm_source_platform", "utm_creative_format", "utm_marketing_tactic",
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "twclid", "ttclid",
        "igshid", "mibextid", "mc_cid", "mc_eid", "wickedid", "li_fat_id",
        "hsa_acc", "hsa_cam", "hsa_grp", "hsa_ad", "hsa_src", "hsa_tgt",
        "hsa_kw", "hsa_mt", "hsa_net", "hsa_ver", "_hsenc", "_hsmi",
        "oly_anon_id", "oly_enc_id", "vero_id", "wickedid",
    ]

    public static func clean(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems, !items.isEmpty else { return url }
        let kept = items.filter { !trackingParams.contains($0.name.lowercased()) }
        comps.queryItems = kept.isEmpty ? nil : kept
        return comps.url ?? url
    }
}
