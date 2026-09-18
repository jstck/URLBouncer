import Foundation

public struct ChromeProfile {
    public let dir: String
    public let name: String
    public let email: String

    public init(dir: String, name: String, email: String) {
        self.dir = dir
        self.name = name
        self.email = email
    }
}

public struct FirefoxProfile {
    public let dir: String
    public let name: String

    public init(dir: String, name: String) {
        self.dir = dir
        self.name = name
    }
}

public struct OperaProfile {
    public let path: String
    public let name: String

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

public let defaultChromeProfilesDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Google/Chrome")

public let defaultFirefoxProfilesDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Firefox/Profiles")

public let defaultFirefoxProfilesIniPath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Firefox/profiles.ini")

public let defaultOperaProfilesDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Opera/Profiles")

public func listChromeProfiles(baseDir: URL = defaultChromeProfilesDir) -> [ChromeProfile] {
    guard let entries = try? FileManager.default.contentsOfDirectory(
        at: baseDir, includingPropertiesForKeys: nil
    ) else { return [] }

    return entries
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .compactMap { entry in
            let prefs = entry.appendingPathComponent("Preferences")
            guard let data = try? Data(contentsOf: prefs),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            let account = (json["account_info"] as? [[String: Any]])?.first
            let profile = json["profile"] as? [String: Any]
            let name  = account?["full_name"]  as? String
                     ?? account?["given_name"] as? String
                     ?? profile?["name"]       as? String
                     ?? entry.lastPathComponent
            let email = account?["email"] as? String ?? ""
            return ChromeProfile(dir: entry.lastPathComponent, name: name, email: email)
        }
}

// Firefox stores human-readable profile names in profiles.ini (next to the
// Profiles/ directory), keyed by each [ProfileN] section's Path=. Falls back
// to the directory name when the ini is missing/unreadable or has no
// matching section for a given profile directory.
func parseFirefoxProfilesIni(at path: URL) -> [String: String] {
    guard let content = try? String(contentsOf: path, encoding: .utf8) else { return [:] }

    var result: [String: String] = [:]
    var currentName: String?
    var currentPath: String?

    func flush() {
        if let path = currentPath, let name = currentName {
            let pathSuffix = URL(fileURLWithPath: path).lastPathComponent
            result[pathSuffix] = name
        }
        currentName = nil
        currentPath = nil
    }

    for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(rawLine).trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("[") {
            flush()
        } else if let eq = line.firstIndex(of: "=") {
            let key = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if key == "Name" { currentName = value }
            if key == "Path" { currentPath = value }
        }
    }
    flush()

    return result
}

public func listFirefoxProfiles(baseDir: URL = defaultFirefoxProfilesDir,
                                 profilesIniPath: URL = defaultFirefoxProfilesIniPath) -> [FirefoxProfile] {
    let fileManager = FileManager.default

    guard let entries = try? fileManager.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) else {
        return []
    }

    let nameByPathSuffix = parseFirefoxProfilesIni(at: profilesIniPath)

    return entries
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .compactMap { entry in
            guard entry.hasDirectoryPath else { return nil }
            let name = nameByPathSuffix[entry.lastPathComponent] ?? entry.lastPathComponent
            return FirefoxProfile(dir: entry.lastPathComponent, name: name)
        }
}

public func listOperaProfiles(baseDir: URL = defaultOperaProfilesDir) -> [OperaProfile] {
    let fileManager = FileManager.default

    guard let entries = try? fileManager.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil) else {
        return []
    }

    return entries
        .filter { $0.hasDirectoryPath }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { entry in
            OperaProfile(path: entry.path, name: entry.lastPathComponent)
        }
}
