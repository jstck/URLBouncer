import Foundation

public let configDir  = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/urlbouncer")
public let configFile = configDir.appendingPathComponent("config.json")

public func ensureConfig(at fileURL: URL = configFile,
                          bundledDefault: URL? = Bundle.main.url(forResource: "config", withExtension: "json")) {
    guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
    try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let bundledDefault = bundledDefault {
        try? FileManager.default.copyItem(at: bundledDefault, to: fileURL)
    }
    log("Created default config at \(fileURL.path)")
}

public func loadConfig(from fileURL: URL = configFile) -> Config {
    ensureConfig(at: fileURL)
    guard let data = try? Data(contentsOf: fileURL),
          let config = try? JSONDecoder().decode(Config.self, from: data) else {
        log("Failed to load config, using defaults")
        return Config(rules: [], defaultProfile: nil, profiles: nil)
    }
    return config
}
