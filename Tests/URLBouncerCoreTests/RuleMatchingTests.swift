import Testing
@testable import URLBouncerCore

struct RuleMatchingTests {

    @Test func hostnameSubstringMatch() {
        let config = Config(rules: [Rule(match: "github.com", sourceApp: nil, profile: "work")])
        #expect(routeURL("https://github.com/user/repo", source: nil, config: config) == "work")
    }

    @Test func hostnameSubstringMatchIsUnanchored() {
        // Documents current (unanchored) behavior: "example.com" as a pattern
        // matches anywhere in the host, including as a suffix of another domain.
        let config = Config(rules: [Rule(match: "example.com", sourceApp: nil, profile: "hit")])
        #expect(routeURL("https://notexample.com/page", source: nil, config: config) == "hit")
    }

    @Test func hostnameModeIgnoresPath() {
        let config = Config(rules: [Rule(match: "github.com", sourceApp: nil, profile: "work")])
        #expect(routeURL("https://example.com/github.com", source: nil, config: config) == nil)
    }

    @Test func fullURLModeTriggeredBySlash() {
        let config = Config(rules: [
            Rule(match: "docs.google.com/presentation", sourceApp: nil, profile: "work"),
        ])
        #expect(routeURL("https://docs.google.com/presentation/d/123", source: nil, config: config) == "work")
        #expect(routeURL("https://docs.google.com/document/d/456", source: nil, config: config) == nil)
    }

    @Test func fullURLModeTriggeredByQuestionMark() {
        let config = Config(rules: [
            Rule(match: "example.com?tab=1", sourceApp: nil, profile: "work"),
        ])
        #expect(routeURL("https://example.com?tab=1&x=2", source: nil, config: config) == "work")
    }

    @Test func fullURLModeIsCaseInsensitiveButMatchesLowercasedHaystack() {
        let config = Config(rules: [
            Rule(match: "Example.com/Path", sourceApp: nil, profile: "work"),
        ])
        #expect(routeURL("https://EXAMPLE.com/PATH", source: nil, config: config) == "work")
    }

    @Test func regexMode() {
        let config = Config(rules: [
            Rule(match: "re:.*\\.edu$", sourceApp: nil, profile: "edu"),
        ])
        #expect(routeURL("https://stanford.edu", source: nil, config: config) == "edu")
        #expect(routeURL("https://stanford.edu.attacker.net", source: nil, config: config) == nil)
    }

    @Test func regexModeIsCaseInsensitive() {
        let config = Config(rules: [
            Rule(match: "re:^https://GITHUB", sourceApp: nil, profile: "hit"),
        ])
        #expect(routeURL("https://github.com", source: nil, config: config) == "hit")
    }

    @Test func regexModeTakesPriorityOverSlashHeuristic() {
        // A "re:" pattern containing "/" must still be treated as regex, not full-URL substring.
        let config = Config(rules: [
            Rule(match: "re:^https://a/b$", sourceApp: nil, profile: "hit"),
        ])
        #expect(routeURL("https://a/b", source: nil, config: config) == "hit")
        #expect(routeURL("https://a/bc", source: nil, config: config) == nil)
    }

    @Test func nilMatchMeansMatchAny() {
        let config = Config(rules: [Rule(match: nil, sourceApp: nil, profile: "catchall")])
        #expect(routeURL("https://anything.test", source: nil, config: config) == "catchall")
    }

    @Test func emptyStringMatchMeansMatchAny() {
        let config = Config(rules: [Rule(match: "", sourceApp: nil, profile: "catchall")])
        #expect(routeURL("https://anything.test", source: nil, config: config) == "catchall")
    }

    @Test func firstMatchWins() {
        let config = Config(rules: [
            Rule(match: "github.com", sourceApp: nil, profile: "first"),
            Rule(match: "github.com", sourceApp: nil, profile: "second"),
        ])
        #expect(routeURL("https://github.com", source: nil, config: config) == "first")
    }

    @Test func sourceAppFilterByBundleIdentifier() {
        let source = FakeSourceApp(bundleIdentifier: "com.tinyspeck.slackmacgap", localizedName: "Slack")
        let config = Config(rules: [Rule(match: nil, sourceApp: "tinyspeck", profile: "work")])
        #expect(routeURL("https://example.com", source: source, config: config) == "work")
    }

    @Test func sourceAppFilterByLocalizedName() {
        let source = FakeSourceApp(bundleIdentifier: "com.example.unrelated", localizedName: "Slack")
        let config = Config(rules: [Rule(match: nil, sourceApp: "Slack", profile: "work")])
        #expect(routeURL("https://example.com", source: source, config: config) == "work")
    }

    @Test func sourceAppFilterIsCaseInsensitive() {
        let source = FakeSourceApp(bundleIdentifier: nil, localizedName: "Slack")
        let config = Config(rules: [Rule(match: nil, sourceApp: "sLaCk", profile: "work")])
        #expect(routeURL("https://example.com", source: source, config: config) == "work")
    }

    @Test func sourceAppFilterWithNilSourceNeverMatches() {
        let config = Config(rules: [
            Rule(match: nil, sourceApp: "Slack", profile: "work"),
            Rule(match: nil, sourceApp: nil, profile: "fallback"),
        ])
        #expect(routeURL("https://example.com", source: nil, config: config) == "fallback")
    }

    @Test func noRuleMatchesFallsBackToDefaultProfile() {
        let config = Config(rules: [Rule(match: "github.com", sourceApp: nil, profile: "work")],
                             defaultProfile: "default")
        #expect(routeURL("https://other.test", source: nil, config: config) == "default")
    }

    @Test func emptyRuleListFallsBackToDefaultProfile() {
        let config = Config(rules: [], defaultProfile: "default")
        #expect(routeURL("https://anything.test", source: nil, config: config) == "default")
    }

    @Test func matchedRuleWithNilProfileReturnsNilNotDefault() {
        // A rule matching with profile: null means "explicitly no profile",
        // which is distinct from "no rule matched" (which falls to defaultProfile).
        let config = Config(rules: [Rule(match: "github.com", sourceApp: nil, profile: nil)],
                             defaultProfile: "default")
        #expect(routeURL("https://github.com", source: nil, config: config) == nil)
    }
}
