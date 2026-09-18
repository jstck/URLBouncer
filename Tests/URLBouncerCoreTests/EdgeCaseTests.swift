import Foundation
import Testing
@testable import URLBouncerCore

// Automates the non-UI parts of MANUAL_TESTING.md's regression checklist,
// plus the malformed-URL rule-loop fix (bug fix #2).
struct EdgeCaseTests {

    @Test func emptyURLDoesNotCrashAndFallsBackToDefault() {
        let config = Config(rules: [Rule(match: "github.com", sourceApp: nil, profile: "work")],
                             defaultProfile: "default")
        #expect(routeURL("", source: nil, config: config) == "default")
    }

    @Test func veryLongURLIsHandled() {
        let longPath = String(repeating: "a", count: 2000)
        let url = "https://example.com/\(longPath)"
        let config = Config(rules: [Rule(match: "example.com", sourceApp: nil, profile: "work")])
        #expect(routeURL(url, source: nil, config: config) == "work")
    }

    @Test func unicodeInURLIsHandled() {
        let url = "https://例え.jp/ページ?q=café"
        let config = Config(rules: [Rule(match: "re:café", sourceApp: nil, profile: "work")])
        #expect(routeURL(url, source: nil, config: config) == "work")
    }

    @Test func specialCharactersInFullURLMode() {
        let url = "https://example.com/path?a=1&b=2#frag"
        let config = Config(rules: [Rule(match: "example.com/path?a=1", sourceApp: nil, profile: "work")])
        #expect(routeURL(url, source: nil, config: config) == "work")
    }

    // MARK: Malformed-URL rule-loop fix (bug fix #2)

    @Test func malformedURLStillAllowsSourceAppOnlyCatchAllRule() {
        let malformed = "https://ex ample.com"  // unencoded space -> URLComponents(string:) returns nil
        #expect(URLComponents(string: malformed) == nil, "fixture must actually be unparseable")

        let source = FakeSourceApp(bundleIdentifier: nil, localizedName: "WhatsApp")
        let config = Config(rules: [Rule(match: nil, sourceApp: "WhatsApp", profile: "personal")])
        #expect(routeURL(malformed, source: source, config: config) == "personal")
    }

    @Test func malformedURLHostBasedRuleDoesNotMatch() {
        let malformed = "https://ex ample.com"
        let config = Config(rules: [Rule(match: "example.com", sourceApp: nil, profile: "work")],
                             defaultProfile: "default")
        #expect(routeURL(malformed, source: nil, config: config) == "default")
    }

    @Test func malformedURLRegexRuleCanStillMatchRawString() {
        let malformed = "https://ex ample.com"
        let config = Config(rules: [Rule(match: "re:ex ample", sourceApp: nil, profile: "hit")])
        #expect(routeURL(malformed, source: nil, config: config) == "hit")
    }

    @Test func malformedURLWithNoMatchingRuleStillFallsBackToDefault() {
        let malformed = "https://ex ample.com"
        let config = Config(rules: [Rule(match: "unrelated.com", sourceApp: nil, profile: "work")],
                             defaultProfile: "default")
        #expect(routeURL(malformed, source: nil, config: config) == "default")
    }
}
