import AppKit
import Foundation
import Testing
import URLBouncerCore

// Exercises whatever browsers are actually installed on this Mac: a
// profile-launch smoke test for each installed browser whose opener
// supports profiles (Chrome/Firefox/Opera), and a plain-launch smoke test
// for every installed browser including Safari (which never supports
// profile selection via CLI). Browsers not installed are skipped, not
// failed.
//
// Nested under RealAppIntegrationTests (see TestSupport.swift) so it's
// serialized against AppSmokeTests too, not just against itself.
extension RealAppIntegrationTests {
@Suite
final class BrowserSmokeTests {

    private var restoreConfig: (() -> Void)?

    deinit {
        TestSupport.quitBuiltApp()
        restoreConfig?()
    }

    private static var builtAppExists: Bool {
        FileManager.default.fileExists(atPath: TestSupport.builtAppURL.path)
    }

    private static func isInstalled(_ name: String) -> Bool {
        TestSupport.installedBrowsers().contains { $0.name == name }
    }

    /// Launches the real app, routes `url` to a browser profile via the real
    /// config, then verifies the browser actually launched.
    ///
    /// If the browser wasn't already running, a brand-new NSRunningApplication
    /// appearing is a strong, unambiguous signal of a real launch - and since
    /// it's demonstrably a process this test started, it's safe to terminate
    /// afterward. If the browser *was* already running (the common case for
    /// the user's daily-driver Chrome), a new window in that same process is
    /// indistinguishable from "brought to front" without fragile window-list/
    /// Accessibility APIs - so this deliberately downgrades to the weakest
    /// available signal (the launch call didn't crash the app) and performs
    /// no cleanup, to avoid ever closing the user's real browser session.
    private func verifyRealLaunch(bundleIdentifier: String, configJSON: String, url: String) throws {
        restoreConfig = try TestSupport.backupAndReplaceRealConfig(with: Data(configJSON.utf8))

        let wasRunningBefore = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty

        TestSupport.launchBuiltApp()
        #expect(TestSupport.waitUntil(timeout: 10) { TestSupport.isBuiltAppRunning() })

        TestSupport.sendURL(url)

        if wasRunningBefore {
            print("NOTE: \(bundleIdentifier) was already running before this test - using weaker liveness check only, no cleanup performed")
            let stillRunning = TestSupport.waitUntil(timeout: 5) {
                !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
            }
            #expect(stillRunning)
        } else {
            var launchedApp: NSRunningApplication?
            let appeared = TestSupport.waitUntil(timeout: 10) {
                launchedApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
                return launchedApp != nil
            }
            #expect(appeared)
            launchedApp?.terminate()
        }
    }

    // MARK: Chrome

    @Test(.enabled(if: BrowserSmokeTests.builtAppExists && BrowserSmokeTests.isInstalled("chrome"),
                    "Chrome not installed or app not built"))
    func chromeProfileLaunch() throws {
        let configJSON = """
        {"profiles": {"p": {"browser": "chrome", "browserProfile": "Default"}},
         "rules": [{"match": "urlbouncer-browsersmoke-chrome-profile.example", "profile": "p"}]}
        """
        try verifyRealLaunch(bundleIdentifier: "com.google.Chrome", configJSON: configJSON,
                              url: "https://urlbouncer-browsersmoke-chrome-profile.example")
    }

    @Test(.enabled(if: BrowserSmokeTests.builtAppExists && BrowserSmokeTests.isInstalled("chrome"),
                    "Chrome not installed or app not built"))
    func chromePlainLaunch() throws {
        let configJSON = """
        {"profiles": {"p": {"browser": "chrome"}},
         "rules": [{"match": "urlbouncer-browsersmoke-chrome-plain.example", "profile": "p"}]}
        """
        try verifyRealLaunch(bundleIdentifier: "com.google.Chrome", configJSON: configJSON,
                              url: "https://urlbouncer-browsersmoke-chrome-plain.example")
    }

    // MARK: Firefox

    @Test(.enabled(if: BrowserSmokeTests.builtAppExists && BrowserSmokeTests.isInstalled("firefox"),
                    "Firefox not installed or app not built"))
    func firefoxProfileLaunch() throws {
        let profiles = listFirefoxProfiles()
        let profileArg = profiles.first?.dir ?? "default"
        let configJSON = """
        {"profiles": {"p": {"browser": "firefox", "browserProfile": "\(profileArg)"}},
         "rules": [{"match": "urlbouncer-browsersmoke-firefox-profile.example", "profile": "p"}]}
        """
        try verifyRealLaunch(bundleIdentifier: "org.mozilla.firefox", configJSON: configJSON,
                              url: "https://urlbouncer-browsersmoke-firefox-profile.example")
    }

    @Test(.enabled(if: BrowserSmokeTests.builtAppExists && BrowserSmokeTests.isInstalled("firefox"),
                    "Firefox not installed or app not built"))
    func firefoxPlainLaunch() throws {
        let configJSON = """
        {"profiles": {"p": {"browser": "firefox"}},
         "rules": [{"match": "urlbouncer-browsersmoke-firefox-plain.example", "profile": "p"}]}
        """
        try verifyRealLaunch(bundleIdentifier: "org.mozilla.firefox", configJSON: configJSON,
                              url: "https://urlbouncer-browsersmoke-firefox-plain.example")
    }

    // MARK: Opera

    @Test(.enabled(if: BrowserSmokeTests.builtAppExists && BrowserSmokeTests.isInstalled("opera"),
                    "Opera not installed or app not built"))
    func operaProfileLaunch() throws {
        let profiles = listOperaProfiles()
        let profileArg = profiles.first?.path ?? ""
        let configJSON = """
        {"profiles": {"p": {"browser": "opera", "browserProfile": "\(profileArg)"}},
         "rules": [{"match": "urlbouncer-browsersmoke-opera-profile.example", "profile": "p"}]}
        """
        try verifyRealLaunch(bundleIdentifier: "com.operasoftware.Opera", configJSON: configJSON,
                              url: "https://urlbouncer-browsersmoke-opera-profile.example")
    }

    @Test(.enabled(if: BrowserSmokeTests.builtAppExists && BrowserSmokeTests.isInstalled("opera"),
                    "Opera not installed or app not built"))
    func operaPlainLaunch() throws {
        let configJSON = """
        {"profiles": {"p": {"browser": "opera"}},
         "rules": [{"match": "urlbouncer-browsersmoke-opera-plain.example", "profile": "p"}]}
        """
        try verifyRealLaunch(bundleIdentifier: "com.operasoftware.Opera", configJSON: configJSON,
                              url: "https://urlbouncer-browsersmoke-opera-plain.example")
    }

    // MARK: Safari (plain launch only - profile selection is not supported)

    @Test(.enabled(if: BrowserSmokeTests.builtAppExists && BrowserSmokeTests.isInstalled("safari"),
                    "Safari not installed or app not built"))
    func safariPlainLaunch() throws {
        let configJSON = """
        {"profiles": {"p": {"browser": "safari"}},
         "rules": [{"match": "urlbouncer-browsersmoke-safari-plain.example", "profile": "p"}]}
        """
        try verifyRealLaunch(bundleIdentifier: "com.apple.Safari", configJSON: configJSON,
                              url: "https://urlbouncer-browsersmoke-safari-plain.example")
    }
}
}
