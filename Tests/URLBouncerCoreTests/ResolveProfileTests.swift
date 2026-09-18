import Foundation
import Testing
@testable import URLBouncerCore

struct ResolveProfileTests {

    @Test func nilNameResolvesToNil() {
        let config = Config()
        #expect(config.resolveProfile(nil) == nil)
    }

    @Test func v2DictHitTakesPriority() {
        // Even though "work" could plausibly be mistaken for a literal Chrome
        // profile directory name, an explicit v2 entry must win.
        let config = Config(profiles: ["work": .browser(name: "firefox", browserProfile: "personal")])
        #expect(config.resolveProfile("work") == .browser(name: "firefox", browserProfile: "personal"))
    }

    @Test func missingProfilesDictFallsBackToChromePassthrough() {
        // v1 configs never had a "profiles" key at all; a bare name was
        // always a literal Chrome profile directory.
        let config = Config(profiles: nil)
        #expect(config.resolveProfile("Profile 1") == .browser(name: "chrome", browserProfile: "Profile 1"))
    }

    @Test func unknownNameInPresentDictFallsBackToChromePassthrough() {
        let config = Config(profiles: ["work": .browser(name: "firefox", browserProfile: "personal")])
        #expect(config.resolveProfile("Profile 2") == .browser(name: "chrome", browserProfile: "Profile 2"))
    }

    @Test func profileTargetDecodingAllFourShapes() throws {
        let json = """
        {
          "browser_only": {"browser": "safari"},
          "browser_with_profile": {"browser": "chrome", "browserProfile": "Profile 1"},
          "app_only": {"app": "Notes"},
          "app_with_path": {"app": "Finder", "appPath": "/System/Library/CoreServices/Finder.app"},
          "executable_only": {"executable": "/usr/local/bin/handler.sh"},
          "executable_with_alert": {"executable": "/usr/local/bin/handler.sh", "alertOnError": true}
        }
        """
        let decoded = try JSONDecoder().decode([String: ProfileTarget].self, from: Data(json.utf8))
        #expect(decoded["browser_only"] == .browser(name: "safari", browserProfile: nil))
        #expect(decoded["browser_with_profile"] == .browser(name: "chrome", browserProfile: "Profile 1"))
        #expect(decoded["app_only"] == .app(name: "Notes", appPath: nil))
        #expect(decoded["app_with_path"] == .app(name: "Finder", appPath: "/System/Library/CoreServices/Finder.app"))
        #expect(decoded["executable_only"] == .executable(path: "/usr/local/bin/handler.sh", alertOnError: nil))
        #expect(decoded["executable_with_alert"] == .executable(path: "/usr/local/bin/handler.sh", alertOnError: true))
    }

    @Test func profileTargetDecodingPrivateDefaultsToFalse() throws {
        let json = """
        {"browser": "chrome", "browserProfile": "Profile 1"}
        """
        let decoded = try JSONDecoder().decode(ProfileTarget.self, from: Data(json.utf8))
        #expect(decoded == .browser(name: "chrome", browserProfile: "Profile 1", isPrivate: false))
    }

    @Test func profileTargetDecodingPrivateTrue() throws {
        let json = """
        {"browser": "chrome", "browserProfile": "Profile 1", "private": true}
        """
        let decoded = try JSONDecoder().decode(ProfileTarget.self, from: Data(json.utf8))
        #expect(decoded == .browser(name: "chrome", browserProfile: "Profile 1", isPrivate: true))
    }

    @Test func profileTargetEncodingOmitsPrivateKeyWhenFalse() throws {
        let target = ProfileTarget.browser(name: "chrome", browserProfile: nil, isPrivate: false)
        let data = try JSONEncoder().encode(target)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["private"] == nil)
    }

    @Test func profileTargetEncodingIncludesPrivateKeyWhenTrue() throws {
        let target = ProfileTarget.browser(name: "chrome", browserProfile: nil, isPrivate: true)
        let data = try JSONEncoder().encode(target)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["private"] as? Bool == true)
    }

    @Test func profileTargetDecodingThrowsWithoutRecognizedKey() {
        let json = """
        {"unknownKey": "value"}
        """
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ProfileTarget.self, from: Data(json.utf8))
        }
    }
}
