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

    /// Routes `url` to a **throwaway, isolated** browser profile - never the
    /// user's real one - and verifies via `processMarker` (expected to
    /// appear verbatim in the launched process's command line, e.g. a
    /// `--profile-directory=` or `--user-data-dir=` value unique to this
    /// test run) that a process actually started using it. Matching by
    /// command-line marker rather than bundle ID is what makes this safe:
    /// it can tell "a process for THIS specific throwaway profile appeared"
    /// apart from "the app happens to already be running under some other,
    /// unrelated (possibly the user's real) profile."
    ///
    /// This exists because the original design routed these tests through
    /// the user's actual default profile (Chrome's "Default", Opera's only
    /// real profile) - which, on every `make test-integration` run, opened
    /// real tabs in the user's live browsing session, and in Opera's case
    /// is suspected to have caused a "profile could not be opened
    /// correctly" dialog from two processes contending over the same
    /// actively-in-use profile directory.
    private func verifyIsolatedProfileLaunch(configJSON: String, url: String, processMarker: String, cleanupPath: URL) throws {
        restoreConfig = try TestSupport.backupAndReplaceRealConfig(with: Data(configJSON.utf8))
        defer { try? FileManager.default.removeItem(at: cleanupPath) }

        TestSupport.launchBuiltApp()
        #expect(TestSupport.waitUntil(timeout: 10) { TestSupport.isBuiltAppRunning() })

        TestSupport.sendURL(url)

        var pids: [Int32] = []
        let appeared = TestSupport.waitUntil(timeout: 10) {
            pids = TestSupport.pids(matchingCommandLineSubstring: processMarker)
            return !pids.isEmpty
        }
        #expect(appeared, "expected a process for the isolated profile '\(processMarker)' to appear")
        for pid in pids {
            kill(pid, SIGTERM)
        }
    }

    // MARK: Chrome

    @Test(.enabled(if: BrowserSmokeTests.builtAppExists && BrowserSmokeTests.isInstalled("chrome"),
                    "Chrome not installed or app not built"))
    func chromeProfileLaunch() throws {
        let marker = "urlbouncer-smoke-chrome-\(UUID().uuidString.prefix(8))"
        let configJSON = """
        {"profiles": {"p": {"browser": "chrome", "browserProfile": "\(marker)"}},
         "rules": [{"match": "urlbouncer-browsersmoke-chrome-profile.example", "profile": "p"}]}
        """
        // Chrome auto-creates a brand-new, empty profile for any
        // --profile-directory name it hasn't seen before - never touches
        // "Default" or any other real profile.
        let profileDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/\(marker)")
        try verifyIsolatedProfileLaunch(configJSON: configJSON,
                                         url: "https://urlbouncer-browsersmoke-chrome-profile.example",
                                         processMarker: marker, cleanupPath: profileDir)
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
    //
    // No dedicated profile-launch smoke test: Firefox's `-P <name>` (the
    // flag production code uses) requires a name already registered in the
    // shared profiles.ini, or it falls back to an interactive "Choose User
    // Profile" dialog - which is exactly what surfaced during development
    // (a prior version of this test passed a profile *directory* name
    // instead of its registered *name*, which is its own bug, but even a
    // correctly-named throwaway profile can't be created here without
    // running `firefox -CreateProfile`, which writes a new entry into the
    // user's real, shared profiles.ini. That's more than this suite is
    // willing to touch. `openInFirefox`'s exact `-P` argument construction
    // is already covered by OpenerArgumentTests; firefoxPlainLaunch below
    // covers a real, live Firefox launch end-to-end.

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
        let marker = "urlbouncer-smoke-opera-\(UUID().uuidString.prefix(8))"
        let profileDir = FileManager.default.temporaryDirectory.appendingPathComponent(marker)
        let configJSON = """
        {"profiles": {"p": {"browser": "opera", "browserProfile": "\(profileDir.path)"}},
         "rules": [{"match": "urlbouncer-browsersmoke-opera-profile.example", "profile": "p"}]}
        """
        // A brand-new --user-data-dir path Opera has never seen - never
        // touches the user's real (and possibly only) "Default" profile.
        try verifyIsolatedProfileLaunch(configJSON: configJSON,
                                         url: "https://urlbouncer-browsersmoke-opera-profile.example",
                                         processMarker: marker, cleanupPath: profileDir)
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
