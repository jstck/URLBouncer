import AppKit
import Foundation

// MARK: - Fresh-install config generation
//
// On first run (no ~/.config/urlbouncer/config.json yet), URLBouncer used
// to seed the file from a bundled example config. That's confusing as a
// *starting* state - it has fake rules referencing profiles that don't
// exist on the machine. Instead, a fresh config has no rules at all (every
// URL falls straight through to a "default" profile), so behavior is
// unchanged from not having URLBouncer installed at all, and lists any
// browser profiles found in the profiles map as a starting point.

public protocol DefaultBrowserQuerying {
    /// The bundle identifier of whatever's currently registered to handle
    /// http:// URLs, or nil if that can't be determined.
    func currentDefaultHTTPHandlerBundleID() -> String?
}

public struct RealDefaultBrowserQuery: DefaultBrowserQuerying {
    public init() {}

    public func currentDefaultHTTPHandlerBundleID() -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "http://example.com")!) else {
            return nil
        }
        return Bundle(url: appURL)?.bundleIdentifier
    }
}

public let urlBouncerBundleIdentifier = "com.local.urlbouncer"

public struct KnownBrowser {
    public let bundleID: String
    public let name: String
    public let appPath: String
}

/// Chrome, Firefox, Opera, then Safari - both the order used to recognize
/// an already-set default browser, and (since Safari is always present)
/// the fallback order when no other signal is available.
public let knownBrowsersInFallbackOrder: [KnownBrowser] = [
    KnownBrowser(bundleID: "com.google.Chrome", name: "chrome", appPath: "/Applications/Google Chrome.app"),
    KnownBrowser(bundleID: "org.mozilla.firefox", name: "firefox", appPath: "/Applications/Firefox.app"),
    KnownBrowser(bundleID: "com.operasoftware.Opera", name: "opera", appPath: "/Applications/Opera.app"),
    KnownBrowser(bundleID: "com.apple.Safari", name: "safari", appPath: "/Applications/Safari.app"),
]

/// The ProfileTarget for the generated config's "default" profile: whatever
/// browser was already the system default before URLBouncer touched
/// anything, so a fresh config changes nothing about where links land.
///
/// If the registered default is already URLBouncer itself (e.g. its config
/// was deleted after already being set as default) or couldn't be
/// determined at all, falls back to the first installed browser in
/// `knownBrowsers`' order.
public func detectDefaultProfileTarget(
    currentDefaultBundleID: String?,
    urlBouncerBundleID: String = urlBouncerBundleIdentifier,
    knownBrowsers: [KnownBrowser] = knownBrowsersInFallbackOrder,
    isInstalled: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> ProfileTarget {
    if let currentDefaultBundleID, currentDefaultBundleID != urlBouncerBundleID {
        if let known = knownBrowsers.first(where: { $0.bundleID == currentDefaultBundleID }) {
            return .browser(name: known.name, browserProfile: nil)
        }
        // Some other, unsupported app is already the default - respect it
        // via a generic app launch rather than silently overriding it.
        return .app(name: currentDefaultBundleID, appPath: nil)
    }

    for candidate in knownBrowsers where isInstalled(candidate.appPath) {
        return .browser(name: candidate.name, browserProfile: nil)
    }
    // Unreachable in practice - Safari (the last entry) is always present
    // on macOS - but a defined fallback beats a crash if that ever changes.
    return .browser(name: "safari", browserProfile: nil)
}

/// Named profile entries for any browser that has more than a single,
/// undifferentiated default profile - i.e. something actually worth
/// referencing by name in a rule. A browser with zero or exactly one
/// profile contributes nothing here.
public func detectAdditionalBrowserProfiles(
    chromeProfiles: [ChromeProfile] = listChromeProfiles(),
    firefoxProfiles: [FirefoxProfile] = listFirefoxProfiles(),
    operaProfiles: [OperaProfile] = listOperaProfiles()
) -> [String: ProfileTarget] {
    var result: [String: ProfileTarget] = [:]

    func addUnique(_ base: String, _ target: ProfileTarget) {
        var key = base
        var suffix = 2
        while result[key] != nil {
            key = "\(base)_\(suffix)"
            suffix += 1
        }
        result[key] = target
    }

    func sanitized(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: " ", with: "_")
    }

    if chromeProfiles.count > 1 {
        for profile in chromeProfiles {
            addUnique("chrome_\(sanitized(profile.name))", .browser(name: "chrome", browserProfile: profile.dir))
        }
    }

    if firefoxProfiles.count > 1 {
        for profile in firefoxProfiles {
            addUnique("firefox_\(sanitized(profile.name))", .browser(name: "firefox", browserProfile: profile.name))
        }
    }

    if operaProfiles.count > 1 {
        for profile in operaProfiles {
            addUnique("opera_\(sanitized(profile.name))", .browser(name: "opera", browserProfile: profile.path))
        }
    }

    return result
}

public func generateFreshConfig(
    query: DefaultBrowserQuerying = RealDefaultBrowserQuery(),
    urlBouncerBundleID: String = urlBouncerBundleIdentifier,
    knownBrowsers: [KnownBrowser] = knownBrowsersInFallbackOrder,
    isInstalled: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
    chromeProfiles: [ChromeProfile] = listChromeProfiles(),
    firefoxProfiles: [FirefoxProfile] = listFirefoxProfiles(),
    operaProfiles: [OperaProfile] = listOperaProfiles()
) -> Config {
    var profiles = detectAdditionalBrowserProfiles(
        chromeProfiles: chromeProfiles, firefoxProfiles: firefoxProfiles, operaProfiles: operaProfiles
    )
    profiles["default"] = detectDefaultProfileTarget(
        currentDefaultBundleID: query.currentDefaultHTTPHandlerBundleID(),
        urlBouncerBundleID: urlBouncerBundleID,
        knownBrowsers: knownBrowsers,
        isInstalled: isInstalled
    )
    return Config(rules: [], defaultProfile: "default", profiles: profiles)
}
