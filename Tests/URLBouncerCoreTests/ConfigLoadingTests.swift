import Foundation
import Testing
@testable import URLBouncerCore

final class ConfigLoadingTests {
    let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func loadsWellFormedConfig() throws {
        let fileURL = tempDir.appendingPathComponent("config.json")
        let json = """
        {"rules": [{"match": "github.com", "profile": "work"}], "defaultProfile": "work"}
        """
        try json.write(to: fileURL, atomically: true, encoding: .utf8)

        let config = loadConfig(from: fileURL)
        #expect(config.rules.count == 1)
        #expect(config.defaultProfile == "work")
    }

    @Test func malformedJSONFallsBackToEmptyConfig() throws {
        let fileURL = tempDir.appendingPathComponent("config.json")
        try "{ this is not valid json".write(to: fileURL, atomically: true, encoding: .utf8)

        let config = loadConfig(from: fileURL)
        #expect(config.rules.isEmpty)
        #expect(config.defaultProfile == nil)
        #expect(config.profiles == nil)
    }

    @Test func missingFileGetsGeneratedFromInjectedGenerator() {
        let fileURL = tempDir.appendingPathComponent("does-not-exist.json")
        let config = loadConfig(from: fileURL, configGenerator: {
            Config(rules: [], defaultProfile: "generated", profiles: ["generated": .browser(name: "safari", browserProfile: nil)])
        })
        #expect(config.rules.isEmpty)
        #expect(config.defaultProfile == "generated")
    }

    @Test func ensureConfigWritesGeneratedConfigWhenFileMissing() throws {
        let fileURL = tempDir.appendingPathComponent("subdir/config.json")
        ensureConfig(at: fileURL, configGenerator: {
            Config(rules: [], defaultProfile: "from-generator", profiles: nil)
        })

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let config = loadConfig(from: fileURL)
        #expect(config.defaultProfile == "from-generator")
    }

    @Test func ensureConfigDoesNotOverwriteExistingFile() throws {
        let fileURL = tempDir.appendingPathComponent("config.json")
        try """
        {"rules": [], "defaultProfile": "existing"}
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        ensureConfig(at: fileURL, configGenerator: {
            Config(rules: [], defaultProfile: "from-generator", profiles: nil)
        })

        let config = loadConfig(from: fileURL)
        #expect(config.defaultProfile == "existing")
    }
}
