import Foundation

// MARK: - URL Dispatcher

public func openURL(_ url: String,
                     target: ProfileTarget?,
                     source: SourceAppDescribing?,
                     runner: CommandRunning = RealCommandRunner(),
                     appOpener: AppOpening = RealAppOpener(),
                     alertPresenter: AlertPresenting = RealAlertPresenter()) {
    guard let target = target else {
        // No profile found - log and don't open
        logURL("No target profile found for \(url)")
        return
    }

    switch target {
    case .browser(let name, let profile, let isPrivate):
        openInBrowser(url: url, browserName: name, profile: profile, isPrivate: isPrivate, runner: runner, appOpener: appOpener, alertPresenter: alertPresenter)
    case .app(let name, let path):
        openInApp(url: url, appName: name, appPath: path, runner: runner, appOpener: appOpener, alertPresenter: alertPresenter)
    case .executable(let path, let alertOnError):
        executeScript(url: url, sourceApp: source?.localizedName, scriptPath: path, alertOnError: alertOnError ?? false, runner: runner, alertPresenter: alertPresenter)
    }
}

// MARK: - Browser Launchers

public func openInBrowser(url: String,
                           browserName: String,
                           profile: String?,
                           isPrivate: Bool = false,
                           runner: CommandRunning = RealCommandRunner(),
                           appOpener: AppOpening = RealAppOpener(),
                           alertPresenter: AlertPresenting = RealAlertPresenter()) {
    let lowerBrowser = browserName.lowercased()

    switch lowerBrowser {
    case "chrome":
        openInChrome(url: url, profile: profile, isPrivate: isPrivate, runner: runner, alertPresenter: alertPresenter)
    case "firefox":
        openInFirefox(url: url, profile: profile, isPrivate: isPrivate, runner: runner, alertPresenter: alertPresenter)
    case "safari":
        // Safari has no CLI mechanism for private windows, same as profiles - silently ignored.
        openInSafari(url: url, runner: runner, alertPresenter: alertPresenter)
    case "opera":
        openInOpera(url: url, profile: profile, isPrivate: isPrivate, runner: runner, alertPresenter: alertPresenter)
    default:
        // Try as generic app
        openInApp(url: url, appName: browserName, appPath: nil, runner: runner, appOpener: appOpener, alertPresenter: alertPresenter)
    }
}

public func openInChrome(url: String,
                          profile: String?,
                          isPrivate: Bool = false,
                          runner: CommandRunning = RealCommandRunner(),
                          alertPresenter: AlertPresenting = RealAlertPresenter()) {
    // -n forces a new process so --profile-directory/--incognito actually
    // get delivered (see openInOpera below for the full explanation);
    // without either flag there's nothing to force-deliver, so a plain
    // launch hands off to whatever's already running unchanged.
    var chromeArgs: [String] = []
    if let profile = profile { chromeArgs.append("--profile-directory=\(profile)") }
    if isPrivate { chromeArgs.append("--incognito") }

    let arguments: [String]
    if chromeArgs.isEmpty {
        arguments = ["-a", "Google Chrome", url]
    } else {
        arguments = ["-na", "Google Chrome", "--args"] + chromeArgs + [url]
    }
    logURL("Opened \(url) in Chrome" + (profile.map { " profile '\($0)'" } ?? " (no profile)") + (isPrivate ? " [incognito]" : ""))
    do {
        try runner.launch(executable: "/usr/bin/open", arguments: arguments)
    } catch {
        let errorMsg = "Failed to open Chrome: \(error)"
        log(errorMsg)
        logURL("ERROR: \(errorMsg)")
        alertPresenter.showAlert(title: "Error Opening Browser", message: errorMsg)
    }
}

public func openInFirefox(url: String,
                           profile: String?,
                           isPrivate: Bool = false,
                           runner: CommandRunning = RealCommandRunner(),
                           alertPresenter: AlertPresenting = RealAlertPresenter()) {
    // -private-window takes the URL itself as its argument (replacing the
    // plain trailing URL) rather than being a separate flag; Firefox's own
    // remoting forwards it to an already-running instance correctly, so no
    // extra "force a new process" trick is needed here (unlike Chrome/Opera).
    var arguments: [String] = []
    if let profile = profile { arguments += ["-P", profile] }
    arguments += isPrivate ? ["-private-window", url] : [url]
    logURL("Opened \(url) in Firefox" + (profile.map { " profile '\($0)'" } ?? " (no profile)") + (isPrivate ? " [private window]" : ""))

    do {
        try runner.launch(executable: "/Applications/Firefox.app/Contents/MacOS/firefox", arguments: arguments)
    } catch {
        let errorMsg = "Failed to open Firefox: \(error)"
        log(errorMsg)
        logURL("ERROR: \(errorMsg)")
        alertPresenter.showAlert(title: "Error Opening Browser", message: errorMsg)
    }
}

public func openInSafari(url: String,
                          runner: CommandRunning = RealCommandRunner(),
                          alertPresenter: AlertPresenting = RealAlertPresenter()) {
    guard URL(string: url) != nil else {
        let errorMsg = "Invalid URL: \(url)"
        log(errorMsg)
        alertPresenter.showAlert(title: "Error", message: errorMsg)
        return
    }

    do {
        try runner.launch(executable: "/usr/bin/open", arguments: ["-a", "Safari", url])
        logURL("Opened \(url) in Safari")
    } catch {
        let errorMsg = "Failed to open Safari: \(error)"
        log(errorMsg)
        logURL("ERROR: \(errorMsg)")
        alertPresenter.showAlert(title: "Error Opening Browser", message: errorMsg)
    }
}

public func openInOpera(url: String,
                         profile: String?,
                         isPrivate: Bool = false,
                         runner: CommandRunning = RealCommandRunner(),
                         alertPresenter: AlertPresenting = RealAlertPresenter()) {
    // Opera uses --user-data-dir for profiles and --incognito for private
    // windows. -na forces `open` to spawn a new process carrying these
    // along; without it, if Opera is already running, macOS just
    // re-activates that process and silently drops both (and the URL
    // never opens at all) - same reasoning as Chrome above.
    var operaArgs: [String] = []
    if let profile = profile { operaArgs.append("--user-data-dir=\(profile)") }
    if isPrivate { operaArgs.append("--incognito") }

    let arguments: [String]
    if operaArgs.isEmpty {
        arguments = ["-a", "Opera", url]
    } else {
        arguments = ["-na", "Opera", "--args"] + operaArgs + [url]
    }
    logURL("Opened \(url) in Opera" + (profile.map { " profile '\($0)'" } ?? " (no profile)") + (isPrivate ? " [incognito]" : ""))

    do {
        try runner.launch(executable: "/usr/bin/open", arguments: arguments)
    } catch {
        let errorMsg = "Failed to open Opera: \(error)"
        log(errorMsg)
        logURL("ERROR: \(errorMsg)")
        alertPresenter.showAlert(title: "Error Opening Browser", message: errorMsg)
    }
}

// MARK: - Generic App Launcher

public func openInApp(url: String,
                       appName: String,
                       appPath: String?,
                       runner: CommandRunning = RealCommandRunner(),
                       appOpener: AppOpening = RealAppOpener(),
                       alertPresenter: AlertPresenting = RealAlertPresenter()) {
    do {
        if let appPath = appPath {
            // Use specific app path
            let fullURL = URL(fileURLWithPath: appPath)
            guard let nsURL = URL(string: url) else {
                throw NSError(domain: "Invalid URL", code: -1)
            }
            try appOpener.open(url: nsURL, applicationAt: fullURL)
            logURL("Opened \(url) with app at '\(appPath)'")
        } else {
            // Use app name lookup via 'open' command
            guard URL(string: url) != nil else {
                throw NSError(domain: "Invalid URL", code: -1)
            }
            try runner.launch(executable: "/usr/bin/open", arguments: ["-a", appName, url])
            logURL("Opened \(url) with '\(appName)'")
        }
    } catch {
        let errorMsg = "Failed to open \(appName): \(error)"
        log(errorMsg)
        logURL("ERROR: \(errorMsg)")
        alertPresenter.showAlert(title: "Error Opening Application", message: errorMsg)
    }
}

// MARK: - Script Executor

public func executeScript(url: String,
                           sourceApp: String?,
                           scriptPath: String,
                           alertOnError: Bool,
                           runner: CommandRunning = RealCommandRunner(),
                           alertPresenter: AlertPresenting = RealAlertPresenter()) {
    // Substitute placeholders
    let sanitizedURL = url.replacingOccurrences(of: "'", with: "'\\''")
    let sanitizedSourceApp = (sourceApp ?? "").replacingOccurrences(of: "'", with: "'\\''")

    let command = scriptPath
        .replacingOccurrences(of: "${url}", with: "'\(sanitizedURL)'")
        .replacingOccurrences(of: "${sourceApp}", with: "'\(sanitizedSourceApp)'")

    do {
        let (exitCode, output, error) = try runner.run(executable: "/bin/bash", arguments: ["-c", command])

        let logMsg = "Script '\(scriptPath)' executed (exit code: \(exitCode))\nOutput: \(output.prefix(200))"
        log(logMsg)

        if exitCode != 0 {
            if alertOnError {
                alertPresenter.showAlert(title: "Script Error", message: "Script '\(scriptPath)' failed with exit code \(exitCode)")
            }
            log("Script error output: \(error.prefix(500))")
        }

        logURL("Executed script: \(scriptPath)")
    } catch {
        let errorMsg = "Failed to execute script: \(error)"
        log(errorMsg)
        if alertOnError {
            alertPresenter.showAlert(title: "Script Error", message: errorMsg)
        }
    }
}
