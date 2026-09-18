import Foundation
import Testing
@testable import URLBouncerCore

struct FreshConfigGenerationTests {

    // MARK: detectDefaultProfileTarget

    @Test func recognizedCurrentDefaultBrowserIsUsedDirectly() {
        let target = detectDefaultProfileTarget(
            currentDefaultBundleID: "org.mozilla.firefox",
            urlBouncerBundleID: "com.local.urlbouncer",
            isInstalled: { _ in true }
        )
        #expect(target == .browser(name: "firefox", browserProfile: nil))
    }

    @Test func currentDefaultAlreadyBeingURLBouncerFallsBackToFirstInstalled() {
        let target = detectDefaultProfileTarget(
            currentDefaultBundleID: "com.local.urlbouncer",
            urlBouncerBundleID: "com.local.urlbouncer",
            knownBrowsers: [
                KnownBrowser(bundleID: "a", name: "chrome", appPath: "/A"),
                KnownBrowser(bundleID: "b", name: "firefox", appPath: "/B"),
            ],
            isInstalled: { $0 == "/B" }
        )
        #expect(target == .browser(name: "firefox", browserProfile: nil))
    }

    @Test func nilCurrentDefaultFallsBackToFirstInstalled() {
        let target = detectDefaultProfileTarget(
            currentDefaultBundleID: nil,
            urlBouncerBundleID: "com.local.urlbouncer",
            knownBrowsers: [KnownBrowser(bundleID: "a", name: "opera", appPath: "/A")],
            isInstalled: { _ in true }
        )
        #expect(target == .browser(name: "opera", browserProfile: nil))
    }

    @Test func fallbackRespectsKnownBrowserOrder() {
        let target = detectDefaultProfileTarget(
            currentDefaultBundleID: "com.local.urlbouncer",
            urlBouncerBundleID: "com.local.urlbouncer",
            knownBrowsers: [
                KnownBrowser(bundleID: "a", name: "chrome", appPath: "/Chrome"),
                KnownBrowser(bundleID: "b", name: "firefox", appPath: "/Firefox"),
                KnownBrowser(bundleID: "c", name: "opera", appPath: "/Opera"),
            ],
            // Both Firefox and Opera are "installed"; Chrome (checked first) wins.
            isInstalled: { $0 == "/Firefox" || $0 == "/Opera" }
        )
        #expect(target == .browser(name: "firefox", browserProfile: nil))
    }

    @Test func unrecognizedCurrentDefaultUsesGenericAppTarget() {
        let target = detectDefaultProfileTarget(
            currentDefaultBundleID: "com.brave.Browser",
            urlBouncerBundleID: "com.local.urlbouncer",
            isInstalled: { _ in true }
        )
        #expect(target == .app(name: "com.brave.Browser", appPath: nil))
    }

    @Test func fallsBackToSafariWhenNothingElseIsInstalled() {
        let target = detectDefaultProfileTarget(
            currentDefaultBundleID: nil,
            urlBouncerBundleID: "com.local.urlbouncer",
            isInstalled: { _ in false }
        )
        #expect(target == .browser(name: "safari", browserProfile: nil))
    }

    // MARK: detectAdditionalBrowserProfiles

    @Test func browserWithZeroOrOneProfileContributesNothing() {
        let result = detectAdditionalBrowserProfiles(
            chromeProfiles: [ChromeProfile(dir: "Default", name: "Default", email: "")],
            firefoxProfiles: [],
            operaProfiles: []
        )
        #expect(result.isEmpty)
    }

    @Test func multipleChromeProfilesAreListedByDirName() {
        let result = detectAdditionalBrowserProfiles(
            chromeProfiles: [
                ChromeProfile(dir: "Profile 1", name: "Work", email: ""),
                ChromeProfile(dir: "Profile 2", name: "Personal", email: ""),
            ],
            firefoxProfiles: [],
            operaProfiles: []
        )
        #expect(result["chrome_work"] == .browser(name: "chrome", browserProfile: "Profile 1"))
        #expect(result["chrome_personal"] == .browser(name: "chrome", browserProfile: "Profile 2"))
        #expect(result.count == 2)
    }

    @Test func multipleFirefoxProfilesUseProfileNameNotDirName() {
        let result = detectAdditionalBrowserProfiles(
            chromeProfiles: [],
            firefoxProfiles: [
                FirefoxProfile(dir: "abc123.default", name: "default"),
                FirefoxProfile(dir: "xyz789.work", name: "work"),
            ],
            operaProfiles: []
        )
        #expect(result["firefox_default"] == .browser(name: "firefox", browserProfile: "default"))
        #expect(result["firefox_work"] == .browser(name: "firefox", browserProfile: "work"))
    }

    @Test func multipleOperaProfilesUseFullPath() {
        let result = detectAdditionalBrowserProfiles(
            chromeProfiles: [],
            firefoxProfiles: [],
            operaProfiles: [
                OperaProfile(path: "/path/to/Default", name: "Default"),
                OperaProfile(path: "/path/to/Gaming", name: "Gaming"),
            ]
        )
        #expect(result["opera_default"] == .browser(name: "opera", browserProfile: "/path/to/Default"))
        #expect(result["opera_gaming"] == .browser(name: "opera", browserProfile: "/path/to/Gaming"))
    }

    @Test func duplicateProfileNamesGetUniqueSuffixes() {
        let result = detectAdditionalBrowserProfiles(
            chromeProfiles: [
                ChromeProfile(dir: "Profile 1", name: "Work", email: ""),
                ChromeProfile(dir: "Profile 2", name: "Work", email: ""),
            ],
            firefoxProfiles: [],
            operaProfiles: []
        )
        #expect(result["chrome_work"] == .browser(name: "chrome", browserProfile: "Profile 1"))
        #expect(result["chrome_work_2"] == .browser(name: "chrome", browserProfile: "Profile 2"))
    }

    @Test func multipleBrowsersWithMultipleProfilesAllAppearTogether() {
        let result = detectAdditionalBrowserProfiles(
            chromeProfiles: [
                ChromeProfile(dir: "Profile 1", name: "Work", email: ""),
                ChromeProfile(dir: "Profile 2", name: "Personal", email: ""),
            ],
            firefoxProfiles: [
                FirefoxProfile(dir: "abc.default", name: "default"),
                FirefoxProfile(dir: "xyz.work", name: "work"),
            ],
            operaProfiles: []
        )
        #expect(result.count == 4)
    }

    // MARK: generateFreshConfig

    @Test func generatesEmptyRulesAndDefaultProfilePointingAtDetectedBrowser() {
        let config = generateFreshConfig(
            query: FakeDefaultBrowserQuery(bundleID: "org.mozilla.firefox"),
            chromeProfiles: [],
            firefoxProfiles: [],
            operaProfiles: []
        )
        #expect(config.rules.isEmpty)
        #expect(config.defaultProfile == "default")
        #expect(config.profiles?["default"] == .browser(name: "firefox", browserProfile: nil))
        #expect(config.profiles?.count == 1)
    }

    @Test func generatedConfigIncludesAdditionalDetectedProfiles() {
        let config = generateFreshConfig(
            query: FakeDefaultBrowserQuery(bundleID: "com.apple.Safari"),
            chromeProfiles: [
                ChromeProfile(dir: "Profile 1", name: "Work", email: ""),
                ChromeProfile(dir: "Profile 2", name: "Personal", email: ""),
            ],
            firefoxProfiles: [],
            operaProfiles: []
        )
        #expect(config.profiles?["default"] == .browser(name: "safari", browserProfile: nil))
        #expect(config.profiles?["chrome_work"] == .browser(name: "chrome", browserProfile: "Profile 1"))
        #expect(config.profiles?["chrome_personal"] == .browser(name: "chrome", browserProfile: "Profile 2"))
        #expect(config.profiles?.count == 3)
    }
}
