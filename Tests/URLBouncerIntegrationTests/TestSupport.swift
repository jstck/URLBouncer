import AppKit
import Foundation
import Testing
import URLBouncerCore

// Every test in this target either mutates the real ~/.config/urlbouncer/
// config.json or inspects/launches real running applications. Both
// AppSmokeTests and BrowserSmokeTests nest under this single serialized
// suite (via `extension RealAppIntegrationTests { @Suite final class ... }`)
// so they never run concurrently with each other - a per-suite .serialized
// on each independently does NOT prevent the two suites from racing one
// another, which is what caused a real config-file corruption incident
// during development of this suite.
@Suite(.serialized)
struct RealAppIntegrationTests {}

enum TestSupport {

    static let repoRoot: URL = {
        // Tests/URLBouncerIntegrationTests/TestSupport.swift -> repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    static let builtAppURL = repoRoot.appendingPathComponent("URLBouncer.app")

    struct InstalledBrowser {
        let name: String
        let appPath: String
        let supportsProfiles: Bool
    }

    static func installedBrowsers() -> [InstalledBrowser] {
        let candidates = [
            InstalledBrowser(name: "chrome", appPath: "/Applications/Google Chrome.app", supportsProfiles: true),
            InstalledBrowser(name: "firefox", appPath: "/Applications/Firefox.app", supportsProfiles: true),
            InstalledBrowser(name: "opera", appPath: "/Applications/Opera.app", supportsProfiles: true),
            InstalledBrowser(name: "safari", appPath: "/Applications/Safari.app", supportsProfiles: false),
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.appPath) }
    }

    /// Backs up the real config file (if present), writes `data` in its place,
    /// and returns a closure that restores the original state exactly.
    /// Every caller MUST invoke the returned closure, even on failure.
    static func backupAndReplaceRealConfig(with data: Data) throws -> () -> Void {
        let fileManager = FileManager.default
        let backupURL = configFile.appendingPathExtension("integration-test-backup")

        let hadExistingFile = fileManager.fileExists(atPath: configFile.path)
        if hadExistingFile {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: configFile, to: backupURL)
        }

        try fileManager.createDirectory(at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: configFile)

        return {
            if hadExistingFile {
                try? fileManager.removeItem(at: configFile)
                try? fileManager.copyItem(at: backupURL, to: configFile)
                try? fileManager.removeItem(at: backupURL)
            } else {
                try? fileManager.removeItem(at: configFile)
            }
        }
    }

    @discardableResult
    static func waitUntil(timeout: TimeInterval = 5, pollInterval: TimeInterval = 0.1, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
        return condition()
    }

    static func sendURL(_ urlString: String) {
        let script = "tell application \"URLBouncer\" to open location \"\(urlString)\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        try? task.run()
        task.waitUntilExit()
    }

    static func launchBuiltApp(environment: [String: String] = [:]) {
        let configuration = NSWorkspace.OpenConfiguration()
        if !environment.isEmpty {
            configuration.environment = environment
        }
        NSWorkspace.shared.openApplication(at: builtAppURL, configuration: configuration)
    }

    static let bundleIdentifier = "com.local.urlbouncer"

    static func quitBuiltApp() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
            app.terminate()
        }
        // Block until the process is actually gone: NSWorkspace.openApplication
        // re-activates an already-running instance (ignoring any new
        // `environment`) rather than launching fresh, so the next test's
        // launch must never race an in-flight termination from this one.
        waitUntil(timeout: 5) { !isBuiltAppRunning() }
    }

    static func isBuiltAppRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }
}
