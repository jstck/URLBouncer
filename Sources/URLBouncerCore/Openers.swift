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
    case .browser(let name, let profile):
        openInBrowser(url: url, browserName: name, profile: profile, runner: runner, appOpener: appOpener, alertPresenter: alertPresenter)
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
                           runner: CommandRunning = RealCommandRunner(),
                           appOpener: AppOpening = RealAppOpener(),
                           alertPresenter: AlertPresenting = RealAlertPresenter()) {
    let lowerBrowser = browserName.lowercased()

    switch lowerBrowser {
    case "chrome":
        openInChrome(url: url, profile: profile, runner: runner, alertPresenter: alertPresenter)
    case "firefox":
        openInFirefox(url: url, profile: profile, runner: runner, alertPresenter: alertPresenter)
    case "safari":
        openInSafari(url: url, runner: runner, alertPresenter: alertPresenter)
    case "opera":
        openInOpera(url: url, profile: profile, runner: runner, alertPresenter: alertPresenter)
    default:
        // Try as generic app
        openInApp(url: url, appName: browserName, appPath: nil, runner: runner, appOpener: appOpener, alertPresenter: alertPresenter)
    }
}

public func openInChrome(url: String,
                          profile: String?,
                          runner: CommandRunning = RealCommandRunner(),
                          alertPresenter: AlertPresenting = RealAlertPresenter()) {
    let arguments: [String]
    if let profile = profile {
        arguments = ["-na", "Google Chrome", "--args", "--profile-directory=\(profile)", url]
        logURL("Opened \(url) in Chrome profile '\(profile)'")
    } else {
        arguments = ["-na", "Google Chrome", url]
        logURL("Opened \(url) in Chrome (no profile)")
    }
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
                           runner: CommandRunning = RealCommandRunner(),
                           alertPresenter: AlertPresenting = RealAlertPresenter()) {
    let arguments: [String]
    if let profile = profile {
        arguments = ["-P", profile, url]
        logURL("Opened \(url) in Firefox profile '\(profile)'")
    } else {
        arguments = [url]
        logURL("Opened \(url) in Firefox (no profile)")
    }

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
                         runner: CommandRunning = RealCommandRunner(),
                         alertPresenter: AlertPresenting = RealAlertPresenter()) {
    let arguments: [String]
    if let profile = profile {
        // Opera uses --user-data-dir for profiles
        arguments = ["-a", "Opera", "--args", "--user-data-dir=\(profile)", url]
        logURL("Opened \(url) in Opera profile '\(profile)'")
    } else {
        arguments = ["-a", "Opera", url]
        logURL("Opened \(url) in Opera (no profile)")
    }

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
