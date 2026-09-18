import AppKit
import Foundation

// MARK: - Source app abstraction

// Lets routing logic depend on a plain protocol instead of the un-fakeable
// NSRunningApplication, so tests can supply a simple struct.
public protocol SourceAppDescribing {
    var bundleIdentifier: String? { get }
    var localizedName: String? { get }
}

extension NSRunningApplication: SourceAppDescribing {}

// MARK: - Config

public struct Rule: Codable {
    public let match: String?       // nil or "" = match any URL
    public let sourceApp: String?   // optional: case-insensitive substring of bundle ID or app name
    public let profile: String?     // nil = use default profile

    public init(match: String?, sourceApp: String?, profile: String?) {
        self.match = match
        self.sourceApp = sourceApp
        self.profile = profile
    }
}

// ProfileTarget represents what to open: a browser with optional profile, an app, or a script
public enum ProfileTarget: Codable, Equatable {
    case browser(name: String, browserProfile: String?)
    case app(name: String, appPath: String?)
    case executable(path: String, alertOnError: Bool?)

    // Custom Codable to handle the object format from JSON
    enum CodingKeys: String, CodingKey {
        case browser, browserProfile, app, appPath, executable, alertOnError
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let browser = try container.decodeIfPresent(String.self, forKey: .browser) {
            let profile = try container.decodeIfPresent(String.self, forKey: .browserProfile)
            self = .browser(name: browser, browserProfile: profile)
        } else if let app = try container.decodeIfPresent(String.self, forKey: .app) {
            let path = try container.decodeIfPresent(String.self, forKey: .appPath)
            self = .app(name: app, appPath: path)
        } else if let executable = try container.decodeIfPresent(String.self, forKey: .executable) {
            let alert = try container.decodeIfPresent(Bool.self, forKey: .alertOnError)
            self = .executable(path: executable, alertOnError: alert)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .browser, in: container, debugDescription: "Must have browser, app, or executable key")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .browser(let name, let profile):
            try container.encode(name, forKey: .browser)
            if let profile = profile {
                try container.encode(profile, forKey: .browserProfile)
            }
        case .app(let name, let path):
            try container.encode(name, forKey: .app)
            if let path = path {
                try container.encode(path, forKey: .appPath)
            }
        case .executable(let path, let alert):
            try container.encode(path, forKey: .executable)
            if let alert = alert {
                try container.encode(alert, forKey: .alertOnError)
            }
        }
    }
}

public struct Config: Codable {
    public let rules: [Rule]
    public let defaultProfile: String?  // nil = use no profile
    public let profiles: [String: ProfileTarget]?  // profile name → ProfileTarget

    // Resolve a profile name to its ProfileTarget.
    //
    // v1 configs (pre-dating the "profiles" map) used bare Chrome profile
    // directory names directly as the "profile" value, with no dictionary at
    // all. v2 introduced named aliases in `profiles`, but a name is always
    // allowed to fall through and be treated as a literal Chrome profile
    // directory when it isn't a key in that map — see commit bc78015
    // ("Rules without a matching alias continue to work as-is").
    public func resolveProfile(_ name: String?) -> ProfileTarget? {
        guard let name = name else { return nil }

        if let target = profiles?[name] {
            return target
        }

        return .browser(name: "chrome", browserProfile: name)
    }

    // Custom initializer for creating default configs
    public init(rules: [Rule] = [], defaultProfile: String? = nil, profiles: [String: ProfileTarget]? = nil) {
        self.rules = rules
        self.defaultProfile = defaultProfile
        self.profiles = profiles
    }
}
