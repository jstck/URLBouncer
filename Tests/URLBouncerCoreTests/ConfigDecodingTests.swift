import Foundation
import Testing
@testable import URLBouncerCore

struct ConfigDecodingTests {

    @Test func decodesReadmeCompleteExampleConfig() throws {
        let json = """
        {
          "profiles": {
            "work_chrome": {
              "browser": "chrome",
              "browserProfile": "Profile 1"
            },
            "personal_firefox": {
              "browser": "firefox",
              "browserProfile": "personal"
            },
            "docs_safari": {
              "browser": "safari"
            },
            "send_to_script": {
              "executable": "/usr/local/bin/url_handler.sh ${url}",
              "alertOnError": true
            }
          },
          "rules": [
            {"match": "github.com", "profile": "work_chrome"},
            {"match": "docs.google.com", "sourceApp": "Slack", "profile": "work_chrome"},
            {"match": "youtube.com", "profile": "personal_firefox"},
            {"match": "example.com", "profile": "docs_safari"},
            {"match": "internal.company.com", "profile": "send_to_script"}
          ],
          "defaultProfile": "personal_firefox"
        }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.rules.count == 5)
        #expect(config.defaultProfile == "personal_firefox")
        #expect(config.profiles?["work_chrome"] == .browser(name: "chrome", browserProfile: "Profile 1"))
        #expect(config.profiles?["docs_safari"] == .browser(name: "safari", browserProfile: nil))
        #expect(config.profiles?["send_to_script"] == .executable(path: "/usr/local/bin/url_handler.sh ${url}", alertOnError: true))
    }

    @Test func decodesV1ConfigWithNoProfilesKeyAtAll() throws {
        let json = """
        {
          "rules": [
            {"match": "github.com", "profile": "Profile 1"},
            {"match": "youtube.com", "profile": "Profile 2"}
          ],
          "defaultProfile": "Profile 2"
        }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.profiles == nil)
        #expect(config.rules.count == 2)
        // resolveProfile must still turn these bare names into real Chrome targets.
        #expect(config.resolveProfile(config.rules[0].profile) == .browser(name: "chrome", browserProfile: "Profile 1"))
        #expect(config.resolveProfile(config.defaultProfile) == .browser(name: "chrome", browserProfile: "Profile 2"))
    }

    @Test func decodesV1_5ConfigWithStringAliasProfilesMapThrows() {
        // The intermediate "profile aliases" format (commit bc78015) used a
        // [String: String] map. That's not valid against v2's [String:
        // ProfileTarget], so decoding the whole Config throws - this test
        // documents that known, accepted incompatibility rather than
        // silently mismatching it.
        let json = """
        {
          "profiles": {"work": "Profile 1", "personal": "Profile 2"},
          "rules": [{"match": "github.com", "profile": "work"}],
          "defaultProfile": "personal"
        }
        """
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        }
    }

    @Test func ruleDecodingWithAllFieldsOmittedExceptProfile() throws {
        let json = """
        {"profile": "default"}
        """
        let rule = try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
        #expect(rule.match == nil)
        #expect(rule.sourceApp == nil)
        #expect(rule.profile == "default")
    }
}
