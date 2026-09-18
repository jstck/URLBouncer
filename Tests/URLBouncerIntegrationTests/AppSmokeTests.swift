import Foundation
import Testing
import URLBouncerCore

// Drives the real, freshly-built URLBouncer.app end-to-end via the same
// `osascript ... open location` mechanism MANUAL_TESTING.md uses, and
// verifies outcomes primarily through a test script's own output file
// rather than log scraping or window/UI state, to keep this low-flakiness.
//
// Nested under RealAppIntegrationTests (see TestSupport.swift) so it's
// serialized against BrowserSmokeTests too, not just against itself.
extension RealAppIntegrationTests {
@Suite
final class AppSmokeTests {

    private var scratchDir: URL!
    private var restoreConfig: (() -> Void)?

    init() throws {
        scratchDir = FileManager.default.temporaryDirectory.appendingPathComponent("urlbouncer-smoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
    }

    deinit {
        TestSupport.quitBuiltApp()
        restoreConfig?()
        try? FileManager.default.removeItem(at: scratchDir)
    }

    /// A script profile that records every invocation as "url|sourceApp\n"
    /// to `outputFile`, mirroring MANUAL_TESTING.md's test_handler.sh.
    private func makeRecordingScript() throws -> (scriptPath: URL, outputFile: URL) {
        let scriptPath = scratchDir.appendingPathComponent("record.sh")
        let outputFile = scratchDir.appendingPathComponent("output.log")
        let script = """
        #!/bin/bash
        echo "$1|$2" >> "\(outputFile.path)"
        exit 0
        """
        try script.write(to: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        return (scriptPath, outputFile)
    }

    private func waitForOutputLine(at outputFile: URL, timeout: TimeInterval = 10) -> String? {
        var result: String?
        TestSupport.waitUntil(timeout: timeout) {
            guard let content = try? String(contentsOf: outputFile, encoding: .utf8),
                  !content.isEmpty else { return false }
            result = content
            return true
        }
        return result
    }

    private static var builtAppExists: Bool {
        FileManager.default.fileExists(atPath: TestSupport.builtAppURL.path)
    }

    @Test(.enabled(if: AppSmokeTests.builtAppExists, "URLBouncer.app not found - run `make bundle` first"))
    func ruleRoutesToScriptProfile() throws {
        let (scriptPath, outputFile) = try makeRecordingScript()
        let configJSON = """
        {
          "profiles": {"recorder": {"executable": "\(scriptPath.path) ${url} ${sourceApp}"}},
          "rules": [{"match": "urlbouncer-smoke-test.example", "profile": "recorder"}],
          "defaultProfile": null
        }
        """
        restoreConfig = try TestSupport.backupAndReplaceRealConfig(with: Data(configJSON.utf8))

        TestSupport.launchBuiltApp()
        #expect(TestSupport.waitUntil(timeout: 10) { TestSupport.isBuiltAppRunning() })

        TestSupport.sendURL("https://urlbouncer-smoke-test.example/path")

        let line = waitForOutputLine(at: outputFile)
        #expect(line?.contains("urlbouncer-smoke-test.example") == true)
    }

    @Test(.enabled(if: AppSmokeTests.builtAppExists, "URLBouncer.app not found - run `make bundle` first"))
    func nonMatchingURLFallsBackToDefaultProfile() throws {
        let (scriptPath, outputFile) = try makeRecordingScript()
        let configJSON = """
        {
          "profiles": {"recorder": {"executable": "\(scriptPath.path) ${url} ${sourceApp}"}},
          "rules": [{"match": "never-matches-anything.invalid", "profile": "recorder"}],
          "defaultProfile": "recorder"
        }
        """
        restoreConfig = try TestSupport.backupAndReplaceRealConfig(with: Data(configJSON.utf8))

        TestSupport.launchBuiltApp()
        #expect(TestSupport.waitUntil(timeout: 10) { TestSupport.isBuiltAppRunning() })

        TestSupport.sendURL("https://urlbouncer-default-fallback-test.example")

        let line = waitForOutputLine(at: outputFile)
        #expect(line?.contains("urlbouncer-default-fallback-test.example") == true)
    }

    @Test(.enabled(if: AppSmokeTests.builtAppExists, "URLBouncer.app not found - run `make bundle` first"))
    func v1StyleBareProfileNameRoutesThroughChromePassthrough() throws {
        // End-to-end check of bug fix #1 (v1 config backward compatibility):
        // a config with no "profiles" map at all, where "profile" is a bare
        // string, must not silently drop the URL. We can't assert a real
        // Chrome profile opened without visibly launching Chrome, so this
        // asserts the router's decision via the log instead - this is also
        // the one test in this file that actually opens a real Chrome
        // window, since that's the real end state of the v1 passthrough.
        let configJSON = """
        {
          "rules": [{"match": "urlbouncer-v1-smoke-test.example", "profile": "Profile 1"}],
          "defaultProfile": null
        }
        """
        restoreConfig = try TestSupport.backupAndReplaceRealConfig(with: Data(configJSON.utf8))

        let logFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/URLBouncer/urlbouncer.log")
        let startOffset = (try? FileHandle(forReadingFrom: logFile))?.seekToEndOfFile() ?? 0

        TestSupport.launchBuiltApp(environment: ["URLBOUNCER_LOG_URLS": "1"])
        #expect(TestSupport.waitUntil(timeout: 10) { TestSupport.isBuiltAppRunning() })

        TestSupport.sendURL("https://urlbouncer-v1-smoke-test.example")

        let foundLogLine = TestSupport.waitUntil(timeout: 10) {
            guard let handle = try? FileHandle(forReadingFrom: logFile) else { return false }
            defer { try? handle.close() }
            try? handle.seek(toOffset: startOffset)
            guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return false }
            return text.contains("Opened https://urlbouncer-v1-smoke-test.example in Chrome")
        }
        #expect(foundLogLine)
    }
}
}
