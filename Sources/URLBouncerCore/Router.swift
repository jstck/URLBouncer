import Foundation

// MARK: - Router

public func routeURL(_ urlString: String, source: SourceAppDescribing?, config: Config) -> String? {
    // A URL that URLComponents can't parse (e.g. an unencoded space) used to
    // short-circuit straight to defaultProfile, skipping every rule -
    // including sourceApp-only catch-all rules that don't need a valid URL
    // at all. Instead, fall back to an empty host and keep evaluating rules
    // normally against the raw string.
    let components = URLComponents(string: urlString)
    let host    = (components?.host ?? "").lowercased()
    let fullURL = urlString.lowercased()

    for rule in config.rules {
        let urlMatched: Bool
        if let pattern = rule.match, !pattern.isEmpty {
            if pattern.hasPrefix("re:") {
                let regex = String(pattern.dropFirst(3))
                urlMatched = urlString.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
            } else if pattern.contains("/") || pattern.contains("?") {
                urlMatched = fullURL.contains(pattern.lowercased())
            } else {
                urlMatched = host.contains(pattern.lowercased())
            }
        } else {
            urlMatched = true  // nil or "" = match any URL
        }
        guard urlMatched else { continue }

        if let filter = rule.sourceApp {
            let bundleID = (source?.bundleIdentifier ?? "").lowercased()
            let appName  = (source?.localizedName   ?? "").lowercased()
            let f = filter.lowercased()
            guard bundleID.contains(f) || appName.contains(f) else { continue }
        }

        let pattern = rule.match ?? "*"
        let dest = rule.profile ?? "(no profile)"
        logURL("Rule '\(pattern)'\(rule.sourceApp.map { " (from '\($0)')" } ?? "") matched \(urlString) → \(dest)")
        return rule.profile
    }
    let dest = config.defaultProfile ?? "(no profile)"
    logURL("No rule matched \(urlString) → \(dest) (default)")
    return config.defaultProfile
}
