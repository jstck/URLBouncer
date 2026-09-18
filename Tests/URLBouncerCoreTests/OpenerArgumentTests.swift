import Foundation
import Testing
@testable import URLBouncerCore

struct OpenerArgumentTests {

    // MARK: Chrome

    @Test func chromeWithProfile() {
        let runner = FakeCommandRunner()
        openInChrome(url: "https://github.com", profile: "Profile 1", runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/usr/bin/open", arguments: ["-na", "Google Chrome", "--args", "--profile-directory=Profile 1", "https://github.com"]),
        ])
    }

    @Test func chromeWithoutProfile() {
        let runner = FakeCommandRunner()
        openInChrome(url: "https://github.com", profile: nil, runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/usr/bin/open", arguments: ["-a", "Google Chrome", "https://github.com"]),
        ])
    }

    @Test func chromePrivateWithoutProfile() {
        let runner = FakeCommandRunner()
        openInChrome(url: "https://github.com", profile: nil, isPrivate: true, runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/usr/bin/open", arguments: ["-na", "Google Chrome", "--args", "--incognito", "https://github.com"]),
        ])
    }

    @Test func chromePrivateWithProfile() {
        let runner = FakeCommandRunner()
        openInChrome(url: "https://github.com", profile: "Profile 1", isPrivate: true, runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/usr/bin/open", arguments: ["-na", "Google Chrome", "--args", "--profile-directory=Profile 1", "--incognito", "https://github.com"]),
        ])
    }

    @Test func chromeLaunchFailureShowsAlertAndDoesNotThrowUpward() {
        let runner = FakeCommandRunner()
        runner.launchError = SimpleError()
        let alerts = FakeAlertPresenter()
        openInChrome(url: "https://github.com", profile: nil, runner: runner, alertPresenter: alerts)
        #expect(alerts.alerts.count == 1)
        #expect(alerts.alerts[0].title == "Error Opening Browser")
    }

    // MARK: Firefox

    @Test func firefoxWithProfile() {
        let runner = FakeCommandRunner()
        openInFirefox(url: "https://youtube.com", profile: "personal", runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/Applications/Firefox.app/Contents/MacOS/firefox", arguments: ["-P", "personal", "https://youtube.com"]),
        ])
    }

    @Test func firefoxWithoutProfile() {
        let runner = FakeCommandRunner()
        openInFirefox(url: "https://youtube.com", profile: nil, runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/Applications/Firefox.app/Contents/MacOS/firefox", arguments: ["https://youtube.com"]),
        ])
    }

    @Test func firefoxPrivateWindowWithoutProfile() {
        let runner = FakeCommandRunner()
        openInFirefox(url: "https://youtube.com", profile: nil, isPrivate: true, runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/Applications/Firefox.app/Contents/MacOS/firefox", arguments: ["-private-window", "https://youtube.com"]),
        ])
    }

    @Test func firefoxPrivateWindowWithProfile() {
        let runner = FakeCommandRunner()
        openInFirefox(url: "https://youtube.com", profile: "personal", isPrivate: true, runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/Applications/Firefox.app/Contents/MacOS/firefox", arguments: ["-P", "personal", "-private-window", "https://youtube.com"]),
        ])
    }

    // MARK: Safari

    @Test func safariProfileIsIgnored() {
        let runner = FakeCommandRunner()
        openInSafari(url: "https://example.com", runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/usr/bin/open", arguments: ["-a", "Safari", "https://example.com"]),
        ])
    }

    @Test func safariInvalidURLShowsAlertWithoutLaunching() {
        let runner = FakeCommandRunner()
        let alerts = FakeAlertPresenter()
        openInSafari(url: "", runner: runner, alertPresenter: alerts)
        #expect(runner.launchInvocations.isEmpty)
        #expect(alerts.alerts.count == 1)
    }

    // MARK: Opera

    @Test func operaWithProfileUsesUserDataDir() {
        let runner = FakeCommandRunner()
        openInOpera(url: "https://example.com", profile: "/path/to/profile", runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/usr/bin/open", arguments: ["-na", "Opera", "--args", "--user-data-dir=/path/to/profile", "https://example.com"]),
        ])
    }

    @Test func operaWithoutProfile() {
        let runner = FakeCommandRunner()
        openInOpera(url: "https://example.com", profile: nil, runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/usr/bin/open", arguments: ["-a", "Opera", "https://example.com"]),
        ])
    }

    @Test func operaPrivateWithoutProfile() {
        let runner = FakeCommandRunner()
        openInOpera(url: "https://example.com", profile: nil, isPrivate: true, runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/usr/bin/open", arguments: ["-na", "Opera", "--args", "--incognito", "https://example.com"]),
        ])
    }

    @Test func operaPrivateWithProfile() {
        let runner = FakeCommandRunner()
        openInOpera(url: "https://example.com", profile: "/path/to/profile", isPrivate: true, runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/usr/bin/open", arguments: ["-na", "Opera", "--args", "--user-data-dir=/path/to/profile", "--incognito", "https://example.com"]),
        ])
    }

    // MARK: Dispatch (isPrivate passed through, ignored by Safari)

    @Test func openInBrowserPassesIsPrivateThroughToChrome() {
        let runner = FakeCommandRunner()
        openInBrowser(url: "https://example.com", browserName: "chrome", profile: nil, isPrivate: true, runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/usr/bin/open", arguments: ["-na", "Google Chrome", "--args", "--incognito", "https://example.com"]),
        ])
    }

    @Test func openInBrowserIgnoresIsPrivateForSafari() {
        let runner = FakeCommandRunner()
        openInBrowser(url: "https://example.com", browserName: "safari", profile: nil, isPrivate: true, runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/usr/bin/open", arguments: ["-a", "Safari", "https://example.com"]),
        ])
    }

    // MARK: Generic app

    @Test func appByNameLaunchesViaOpen() {
        let runner = FakeCommandRunner()
        openInApp(url: "https://example.com", appName: "Notes", appPath: nil, runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/usr/bin/open", arguments: ["-a", "Notes", "https://example.com"]),
        ])
    }

    @Test func appByPathUsesAppOpener() {
        let appOpener = FakeAppOpener()
        openInApp(url: "https://example.com", appName: "Finder", appPath: "/System/Library/CoreServices/Finder.app",
                  appOpener: appOpener, alertPresenter: FakeAlertPresenter())
        #expect(appOpener.invocations == [
            .init(url: URL(string: "https://example.com")!, applicationAt: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")),
        ])
    }

    @Test func appByPathFailureShowsAlert() {
        let appOpener = FakeAppOpener()
        appOpener.error = SimpleError()
        let alerts = FakeAlertPresenter()
        openInApp(url: "https://example.com", appName: "Finder", appPath: "/System/Library/CoreServices/Finder.app",
                  appOpener: appOpener, alertPresenter: alerts)
        #expect(alerts.alerts.count == 1)
        #expect(alerts.alerts[0].title == "Error Opening Application")
    }

    // MARK: Dispatch (openInBrowser / openURL)

    @Test func unknownBrowserNameFallsBackToGenericApp() {
        let runner = FakeCommandRunner()
        openInBrowser(url: "https://example.com", browserName: "Brave", profile: nil, runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.launchInvocations == [
            .init(executable: "/usr/bin/open", arguments: ["-a", "Brave", "https://example.com"]),
        ])
    }

    @Test func openURLWithNilTargetLogsAndDoesNothing() {
        let runner = FakeCommandRunner()
        openURL("https://example.com", target: nil, source: nil, runner: runner)
        #expect(runner.launchInvocations.isEmpty)
    }

    // MARK: executeScript

    @Test func executeScriptSubstitutesUrlAndSourceApp() {
        let runner = FakeCommandRunner()
        executeScript(url: "https://example.com", sourceApp: "Slack",
                       scriptPath: "/usr/local/bin/handler.sh ${url} ${sourceApp}",
                       alertOnError: false, runner: runner, alertPresenter: FakeAlertPresenter())
        #expect(runner.runInvocations == [
            .init(executable: "/bin/bash", arguments: ["-c", "/usr/local/bin/handler.sh 'https://example.com' 'Slack'"]),
        ])
    }

    @Test func executeScriptEscapesSingleQuotesInSubstitutedValues() {
        let runner = FakeCommandRunner()
        executeScript(url: "https://example.com/?q=o'brien", sourceApp: "App'; rm -rf ~ #",
                       scriptPath: "/usr/local/bin/handler.sh ${url} ${sourceApp}",
                       alertOnError: false, runner: runner, alertPresenter: FakeAlertPresenter())
        let command = runner.runInvocations[0].arguments[1]
        // Every substituted value must stay inside its own single-quoted
        // segment; a bare "'" must never appear unescaped in the command.
        #expect(command == "/usr/local/bin/handler.sh 'https://example.com/?q=o'\\''brien' 'App'\\''; rm -rf ~ #'")
    }

    @Test func executeScriptAlertOnErrorTrueShowsAlertOnNonZeroExit() {
        let runner = FakeCommandRunner()
        runner.runResult = (1, "", "boom")
        let alerts = FakeAlertPresenter()
        executeScript(url: "https://example.com", sourceApp: nil, scriptPath: "/bin/false",
                       alertOnError: true, runner: runner, alertPresenter: alerts)
        #expect(alerts.alerts.count == 1)
        #expect(alerts.alerts[0].title == "Script Error")
    }

    @Test func executeScriptAlertOnErrorFalseDoesNotShowAlertOnNonZeroExit() {
        let runner = FakeCommandRunner()
        runner.runResult = (1, "", "boom")
        let alerts = FakeAlertPresenter()
        executeScript(url: "https://example.com", sourceApp: nil, scriptPath: "/bin/false",
                       alertOnError: false, runner: runner, alertPresenter: alerts)
        #expect(alerts.alerts.isEmpty)
    }

    @Test func executeScriptZeroExitNeverAlertsEvenWithAlertOnErrorTrue() {
        let runner = FakeCommandRunner()
        runner.runResult = (0, "ok", "")
        let alerts = FakeAlertPresenter()
        executeScript(url: "https://example.com", sourceApp: nil, scriptPath: "/bin/true",
                       alertOnError: true, runner: runner, alertPresenter: alerts)
        #expect(alerts.alerts.isEmpty)
    }

    @Test func executeScriptLaunchFailureAlertsWhenAlertOnErrorTrue() {
        let runner = FakeCommandRunner()
        runner.runError = SimpleError()
        let alerts = FakeAlertPresenter()
        executeScript(url: "https://example.com", sourceApp: nil, scriptPath: "/does/not/exist.sh",
                       alertOnError: true, runner: runner, alertPresenter: alerts)
        #expect(alerts.alerts.count == 1)
        #expect(alerts.alerts[0].title == "Script Error")
    }
}
