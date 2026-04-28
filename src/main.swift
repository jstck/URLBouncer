import AppKit
import Foundation
import CoreServices

// MARK: - Apple Event constants ('GURL' / '----')

private let kGetURLEventClass = UInt32(0x4755524c)
private let kGetURLEventID    = UInt32(0x4755524c)
private let kDirectObject     = UInt32(0x2d2d2d2d)

// MARK: - Config

struct Rule: Codable {
    let match: String?       // nil or "" = match any URL
    let sourceApp: String?   // optional: case-insensitive substring of bundle ID or app name
    let profile: String?     // nil = use default profile
}

// ProfileTarget represents what to open: a browser with optional profile, an app, or a script
enum ProfileTarget: Codable {
    case browser(name: String, browserProfile: String?)
    case app(name: String, appPath: String?)
    case executable(path: String, alertOnError: Bool?)

    // Custom Codable to handle the object format from JSON
    enum CodingKeys: String, CodingKey {
        case browser, browserProfile, app, appPath, executable, alertOnError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let browser = try container.decodeIfPresent(String.self, forKey: .browser) {
            let profile = try container.decodeIfPresent(String.self, forKey: .browserProfile)
            self = .browser(name: browser, browserProfile: profile)
        } else if let app = try container.decodeIfPresent(String.self, forKey: .app) {
            let path = try container.decodeIfPresent(String.self, forKey: .appPath)
            self = .app(name: app, appPath: path)
        } else if let executable = try container.decodeIfPresent(String.self, forKey: .executable) {
            let alert = try container.decodeIfPresent(Bool.self, forKey: .alertOnError)
            self = .executable(path: executable, alertOnError: alert)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .browser, in: container, debugDescription: "Must have browser, app, or executable key")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .browser(let name, let profile):
            try container.encode(name, forKey: .browser)
            if let profile = profile {
                try container.encode(profile, forKey: .browserProfile)
            }
        case .app(let name, let path):
            try container.encode(name, forKey: .app)
            if let path = path {
                try container.encode(path, forKey: .appPath)
            }
        case .executable(let path, let alert):
            try container.encode(path, forKey: .executable)
            if let alert = alert {
                try container.encode(alert, forKey: .alertOnError)
            }
        }
    }
}

struct Config: Codable {
    let rules: [Rule]
    let defaultProfile: String?  // nil = use no profile
    let profiles: [String: ProfileTarget]?  // profile name → ProfileTarget

    // Resolve a profile name to its ProfileTarget (v2 format)
    // Handles backwards compatibility with v1 format (profiles were strings)
    func resolveProfile(_ name: String?) -> ProfileTarget? {
        guard let name = name else { return nil }
        
        // If we have the v2 format, look it up directly
        if let target = profiles?[name] {
            return target
        }
        
        // Otherwise return nil (no profile found)
        return nil
    }
    
    // Custom initializer for creating default configs
    init(rules: [Rule] = [], defaultProfile: String? = nil, profiles: [String: ProfileTarget]? = nil) {
        self.rules = rules
        self.defaultProfile = defaultProfile
        self.profiles = profiles
    }
}

let configDir  = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/urlbouncer")
let configFile = configDir.appendingPathComponent("config.json")

func ensureConfig() {
    guard !FileManager.default.fileExists(atPath: configFile.path) else { return }
    try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
    if let bundleDefault = Bundle.main.url(forResource: "config", withExtension: "json") {
        try? FileManager.default.copyItem(at: bundleDefault, to: configFile)
    }
    log("Created default config at \(configFile.path)")
}

func loadConfig() -> Config {
    ensureConfig()
    guard let data = try? Data(contentsOf: configFile),
          let config = try? JSONDecoder().decode(Config.self, from: data) else {
        log("Failed to load config, using defaults")
        return Config(rules: [], defaultProfile: nil, profiles: nil)
    }
    return config
}

// MARK: - Router

func routeURL(_ urlString: String, source: NSRunningApplication?, config: Config) -> String? {
    guard let components = URLComponents(string: urlString) else {
        return config.defaultProfile
    }
    let host    = (components.host ?? "").lowercased()
    let fullURL = urlString.lowercased()

    for rule in config.rules {
        let urlMatched: Bool
        if let pattern = rule.match, !pattern.isEmpty {
            if pattern.hasPrefix("re:") {
                let regex = String(pattern.dropFirst(3))
                urlMatched = urlString.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
            } else if pattern.contains("/") || pattern.contains("?") {
                urlMatched = fullURL.contains(pattern.lowercased())
            } else {
                urlMatched = host.contains(pattern.lowercased())
            }
        } else {
            urlMatched = true  // nil or "" = match any URL
        }
        guard urlMatched else { continue }

        if let filter = rule.sourceApp {
            let bundleID = (source?.bundleIdentifier ?? "").lowercased()
            let appName  = (source?.localizedName   ?? "").lowercased()
            let f = filter.lowercased()
            guard bundleID.contains(f) || appName.contains(f) else { continue }
        }

        let pattern = rule.match ?? "*"
        let dest = rule.profile ?? "(no profile)"
        logURL("Rule '\(pattern)'\(rule.sourceApp.map { " (from '\($0)')" } ?? "") matched \(urlString) → \(dest)")
        return rule.profile
    }
    let dest = config.defaultProfile ?? "(no profile)"
    logURL("No rule matched \(urlString) → \(dest) (default)")
    return config.defaultProfile
}

// MARK: - Alert Helper (needs to be available for openers)

func showAlert(title: String, message: String) {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = title
    a.informativeText = message
    a.addButton(withTitle: "OK")
    _ = a.runModal()
}

// MARK: - URL Dispatcher

func openURL(_ url: String, target: ProfileTarget?, source: NSRunningApplication?) {
    guard let target = target else {
        // No profile found - log and don't open
        logURL("No target profile found for \(url)")
        return
    }
    
    switch target {
    case .browser(let name, let profile):
        openInBrowser(url: url, browserName: name, profile: profile)
    case .app(let name, let path):
        openInApp(url: url, appName: name, appPath: path)
    case .executable(let path, let alertOnError):
        executeScript(url: url, sourceApp: source?.localizedName, scriptPath: path, alertOnError: alertOnError ?? false)
    }
}

// MARK: - Browser Launchers

func openInBrowser(url: String, browserName: String, profile: String?) {
    let lowerBrowser = browserName.lowercased()
    
    switch lowerBrowser {
    case "chrome":
        openInChrome(url: url, profile: profile)
    case "firefox":
        openInFirefox(url: url, profile: profile)
    case "safari":
        openInSafari(url: url)
    case "opera":
        openInOpera(url: url, profile: profile)
    default:
        // Try as generic app
        openInApp(url: url, appName: browserName, appPath: nil)
    }
}

func openInChrome(url: String, profile: String?) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    if let profile = profile {
        task.arguments = ["-na", "Google Chrome", "--args", "--profile-directory=\(profile)", url]
        logURL("Opened \(url) in Chrome profile '\(profile)'")
    } else {
        task.arguments = ["-na", "Google Chrome", url]
        logURL("Opened \(url) in Chrome (no profile)")
    }
    do {
        try task.run()
    } catch {
        let errorMsg = "Failed to open Chrome: \(error)"
        log(errorMsg)
        logURL("ERROR: \(errorMsg)")
        showAlert(title: "Error Opening Browser", message: errorMsg)
    }
}

func openInFirefox(url: String, profile: String?) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/Applications/Firefox.app/Contents/MacOS/firefox")
    
    if let profile = profile {
        task.arguments = ["-P", profile, url]
        logURL("Opened \(url) in Firefox profile '\(profile)'")
    } else {
        task.arguments = [url]
        logURL("Opened \(url) in Firefox (no profile)")
    }
    
    do {
        try task.run()
    } catch {
        let errorMsg = "Failed to open Firefox: \(error)"
        log(errorMsg)
        logURL("ERROR: \(errorMsg)")
        showAlert(title: "Error Opening Browser", message: errorMsg)
    }
}

func openInSafari(url: String) {
    guard let nsURL = URL(string: url) else {
        let errorMsg = "Invalid URL: \(url)"
        log(errorMsg)
        showAlert(title: "Error", message: errorMsg)
        return
    }
    
    do {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Safari", url]
        try task.run()
        logURL("Opened \(url) in Safari")
    } catch {
        let errorMsg = "Failed to open Safari: \(error)"
        log(errorMsg)
        logURL("ERROR: \(errorMsg)")
        showAlert(title: "Error Opening Browser", message: errorMsg)
    }
}

func openInOpera(url: String, profile: String?) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    
    if let profile = profile {
        // Opera uses --user-data-dir for profiles
        task.arguments = ["-a", "Opera", "--args", "--user-data-dir=\(profile)", url]
        logURL("Opened \(url) in Opera profile '\(profile)'")
    } else {
        task.arguments = ["-a", "Opera", url]
        logURL("Opened \(url) in Opera (no profile)")
    }
    
    do {
        try task.run()
    } catch {
        let errorMsg = "Failed to open Opera: \(error)"
        log(errorMsg)
        logURL("ERROR: \(errorMsg)")
        showAlert(title: "Error Opening Browser", message: errorMsg)
    }
}

// MARK: - Generic App Launcher

func openInApp(url: String, appName: String, appPath: String?) {
    do {
        if let appPath = appPath {
            // Use specific app path
            let fullURL = URL(fileURLWithPath: appPath)
            guard let nsURL = URL(string: url) else {
                throw NSError(domain: "Invalid URL", code: -1)
            }
            try NSWorkspace.shared.open([nsURL], withApplicationAt: fullURL, configuration: NSWorkspace.OpenConfiguration())
            logURL("Opened \(url) with app at '\(appPath)'")
        } else {
            // Use app name lookup via 'open' command
            guard let _ = URL(string: url) else {
                throw NSError(domain: "Invalid URL", code: -1)
            }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-a", appName, url]
            try task.run()
            logURL("Opened \(url) with '\(appName)'")
        }
    } catch {
        let errorMsg = "Failed to open \(appName): \(error)"
        log(errorMsg)
        logURL("ERROR: \(errorMsg)")
        showAlert(title: "Error Opening Application", message: errorMsg)
    }
}

// MARK: - Script Executor

func executeScript(url: String, sourceApp: String?, scriptPath: String, alertOnError: Bool) {
    // Substitute placeholders
    let sanitizedURL = url.replacingOccurrences(of: "'", with: "'\\''")
    let sanitizedSourceApp = (sourceApp ?? "").replacingOccurrences(of: "'", with: "'\\''")
    
    let command = scriptPath
        .replacingOccurrences(of: "${url}", with: "'\(sanitizedURL)'")
        .replacingOccurrences(of: "${sourceApp}", with: "'\(sanitizedSourceApp)'")
    
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/bash")
    task.arguments = ["-c", command]
    
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    task.standardOutput = outputPipe
    task.standardError = errorPipe
    
    do {
        try task.run()
        task.waitUntilExit()
        
        let exitCode = Int(task.terminationStatus)
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""
        
        let logMsg = "Script '\(scriptPath)' executed (exit code: \(exitCode))\nOutput: \(output.prefix(200))"
        log(logMsg)
        
        if exitCode != 0 {
            if alertOnError {
                showAlert(title: "Script Error", message: "Script '\(scriptPath)' failed with exit code \(exitCode)")
            }
            log("Script error output: \(error.prefix(500))")
        }
        
        logURL("Executed script: \(scriptPath)")
    } catch {
        let errorMsg = "Failed to execute script: \(error)"
        log(errorMsg)
        if alertOnError {
            showAlert(title: "Script Error", message: errorMsg)
        }
    }
}

struct ChromeProfile {
    let dir: String
    let name: String
    let email: String
}

func listChromeProfiles() -> [ChromeProfile] {
    let base = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Google/Chrome")
    guard let entries = try? FileManager.default.contentsOfDirectory(
        at: base, includingPropertiesForKeys: nil
    ) else { return [] }

    return entries
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .compactMap { entry in
            let prefs = entry.appendingPathComponent("Preferences")
            guard let data = try? Data(contentsOf: prefs),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            let account = (json["account_info"] as? [[String: Any]])?.first
            let profile = json["profile"] as? [String: Any]
            let name  = account?["full_name"]  as? String
                     ?? account?["given_name"] as? String
                     ?? profile?["name"]       as? String
                     ?? entry.lastPathComponent
            let email = account?["email"] as? String ?? ""
            return ChromeProfile(dir: entry.lastPathComponent, name: name, email: email)
        }
}

struct FirefoxProfile {
    let dir: String
    let name: String
}

struct OperaProfile {
    let path: String
    let name: String
}

func listFirefoxProfiles() -> [FirefoxProfile] {
    let fileManager = FileManager.default
    let profilesDir = fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Firefox/Profiles")
    
    guard let entries = try? fileManager.contentsOfDirectory(at: profilesDir, includingPropertiesForKeys: nil) else {
        return []
    }
    
    return entries
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .compactMap { entry in
            guard entry.hasDirectoryPath else { return nil }
            
            // Try to read profile name from prefs.js or profiles.ini
            let prefsFile = entry.appendingPathComponent("prefs.js")
            let name: String
            
            if let _ = try? String(contentsOf: prefsFile, encoding: .utf8) {
                // For now, just use the directory name; Firefox profile names are complex
                name = entry.lastPathComponent
            } else {
                name = entry.lastPathComponent
            }
            
            return FirefoxProfile(dir: entry.lastPathComponent, name: name)
        }
}

func listOperaProfiles() -> [OperaProfile] {
    let fileManager = FileManager.default
    let profilesDir = fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Opera/Profiles")
    
    guard let entries = try? fileManager.contentsOfDirectory(at: profilesDir, includingPropertiesForKeys: nil) else {
        return []
    }
    
    return entries
        .filter { $0.hasDirectoryPath }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { entry in
            let path = entry.path
            let name = entry.lastPathComponent
            return OperaProfile(path: path, name: name)
        }
}

// MARK: - Logging

private var logHandle: FileHandle?
var urlLoggingEnabled = false

func setupLogging() {
    let logDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/URLBouncer")
    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    let logPath = logDir.appendingPathComponent("urlbouncer.log")
    if !FileManager.default.fileExists(atPath: logPath.path) {
        FileManager.default.createFile(atPath: logPath.path, contents: nil)
    }
    logHandle = try? FileHandle(forWritingTo: logPath)
    logHandle?.seekToEndOfFile()
}

func log(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    logHandle?.write(Data(line.utf8))
}

func logURL(_ message: String) {
    guard urlLoggingEnabled else { return }
    log(message)
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var urlLogItem: NSMenuItem!
    private var previousFrontmostApp: NSRunningApplication?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Must register before the run loop starts so cold-launch URLs are not missed
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: kGetURLEventClass,
            andEventID: kGetURLEventID
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        log("URLBouncer started")

        // Track the last frontmost app for source-based routing.
        // NSWorkspace notifications fire regardless of LSUIElement status,
        // unlike applicationWillBecomeActive which never fires for agent apps.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self?.previousFrontmostApp = app
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let fileURL = URL(fileURLWithPath: filename).absoluteString
        let senderPID = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        let source = senderPID.flatMap { NSRunningApplication(processIdentifier: $0) } ?? previousFrontmostApp
        logURL("File open request: \(filename) — from: \(source?.localizedName ?? "unknown") [\(source?.bundleIdentifier ?? "?")]")
        let config = loadConfig()
        let profileName = routeURL(fileURL, source: source, config: config)
        let target = config.resolveProfile(profileName) ?? config.resolveProfile(config.defaultProfile)
        openURL(fileURL, target: target, source: source)
        return true
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: kDirectObject)?.stringValue else {
            log("GetURL event: missing URL")
            return
        }
        let source = previousFrontmostApp
        logURL("Received: \(urlString) — from: \(source?.localizedName ?? "unknown") [\(source?.bundleIdentifier ?? "?")]")
        let config = loadConfig()
        let profileName = routeURL(urlString, source: source, config: config)
        let target = config.resolveProfile(profileName) ?? config.resolveProfile(config.defaultProfile)
        openURL(urlString, target: target, source: source)
    }

    // MARK: Menu bar

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(named: "menuicon") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "[↗]"
            }
        }

        let menu = NSMenu()
        menu.addItem(menuItem("Set as Default Browser", action: #selector(setAsDefaultBrowser)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Open Config",    action: #selector(openConfig)))
        menu.addItem(menuItem("Reload Config",  action: #selector(reloadConfig)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Manage Profiles", action: #selector(showProfiles)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Show Log",       action: #selector(showLog)))
        urlLogItem = menuItem("Log URLs",       action: #selector(toggleURLLogging))
        menu.addItem(urlLogItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit URLBouncer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: Menu actions

    @objc func setAsDefaultBrowser() {
        guard let id = Bundle.main.bundleIdentifier as CFString? else { return }
        LSSetDefaultHandlerForURLScheme("http" as CFString, id)
        LSSetDefaultHandlerForURLScheme("https" as CFString, id)
        log("Requested default browser registration")
    }

    @objc func openConfig() {
        ensureConfig()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-t", configFile.path]
        try? task.run()
    }

    @objc func reloadConfig() {
        let config = loadConfig()
        showAlert(title: "Config Reloaded",
              message: "\(config.rules.count) rule(s)\nDefault profile: \(config.defaultProfile ?? "(none)")")
    }

    @objc func showProfiles() {
        let chromeProfiles = listChromeProfiles()
        let firefoxProfiles = listFirefoxProfiles()
        let operaProfiles = listOperaProfiles()
        
        var allProfiles: [(browser: String, profiles: String)] = []
        
        // Chrome section
        if !chromeProfiles.isEmpty {
            let lines = chromeProfiles.map { p in
                let email = p.email.isEmpty ? "" : "  (\(p.email))"
                return "  \(p.dir)\t\(p.name)\(email)"
            }
            allProfiles.append(("Chrome", lines.joined(separator: "\n")))
        }
        
        // Firefox section
        if !firefoxProfiles.isEmpty {
            let lines = firefoxProfiles.map { p in
                "  \(p.dir)\t\(p.name)"
            }
            allProfiles.append(("Firefox", lines.joined(separator: "\n")))
        }
        
        // Opera section
        if !operaProfiles.isEmpty {
            let lines = operaProfiles.map { p in
                "  \(p.path)\t\(p.name)"
            }
            allProfiles.append(("Opera", lines.joined(separator: "\n")))
        }
        
        guard !allProfiles.isEmpty else {
            showAlert(title: "Manage Profiles", message: "No browser profiles found.")
            return
        }
        
        // Build display text
        var displayText = ""
        for (i, (browser, profiles)) in allProfiles.enumerated() {
            displayText += browser + " Profiles:\n"
            displayText += profiles + "\n"
            if i < allProfiles.count - 1 {
                displayText += "\n"
            }
        }
        
        // Generate profiles block JSON
        var profilesBlock = "{\n"
        
        if !chromeProfiles.isEmpty {
            let chromeLines = chromeProfiles.enumerated().map { i, p in
                let suffix = i < chromeProfiles.count - 1 ? "," : ""
                return "  \"\(p.name.lowercased())\": { \"browser\": \"chrome\", \"browserProfile\": \"\(p.dir)\" }\(suffix)"
            }
            profilesBlock += chromeLines.joined(separator: "\n") + "\n"
        }
        
        if !firefoxProfiles.isEmpty {
            if !chromeProfiles.isEmpty {
                profilesBlock += "\n"
            }
            let firefoxLines = firefoxProfiles.enumerated().map { i, p in
                let hasMore = i < firefoxProfiles.count - 1 || !operaProfiles.isEmpty
                let suffix = hasMore ? "," : ""
                return "  \"\(p.name.lowercased())\": { \"browser\": \"firefox\", \"browserProfile\": \"\(p.dir)\" }\(suffix)"
            }
            profilesBlock += firefoxLines.joined(separator: "\n") + "\n"
        }
        
        if !operaProfiles.isEmpty {
            if !chromeProfiles.isEmpty || !firefoxProfiles.isEmpty {
                profilesBlock += "\n"
            }
            let operaLines = operaProfiles.enumerated().map { i, p in
                let suffix = i < operaProfiles.count - 1 ? "," : ""
                return "  \"\(p.name.lowercased())\": { \"browser\": \"opera\", \"browserProfile\": \"\(p.path)\" }\(suffix)"
            }
            profilesBlock += operaLines.joined(separator: "\n") + "\n"
        }
        
        profilesBlock += "}"
        
        // Create alert with custom view
        let alert = NSAlert()
        alert.messageText = "Manage Profiles"
        alert.informativeText = "Here are your installed browser profiles. Click \"Copy Profiles Block\" to copy a ready-to-use JSON block to your clipboard."
        
        // Create scrollable text view
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        textView.string = displayText
        textView.isEditable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        
        let scrollView = NSScrollView(frame: textView.bounds)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        
        alert.accessoryView = scrollView
        alert.addButton(withTitle: "Copy Profiles Block")
        alert.addButton(withTitle: "OK")
        
        let result = alert.runModal()
        
        if result == NSApplication.ModalResponse.alertFirstButtonReturn {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(profilesBlock, forType: .string)
            showAlert(title: "Copied!", message: "Profiles block copied to clipboard.")
        }
    }

    @objc func toggleURLLogging() {
        urlLoggingEnabled.toggle()
        urlLogItem.state = urlLoggingEnabled ? .on : .off
        log(urlLoggingEnabled ? "URL logging enabled" : "URL logging disabled")
    }

    @objc func showLog() {
        let logFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/URLBouncer/urlbouncer.log")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Console", logFile.path]
        try? task.run()
    }

    private func alertDelegate(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.runModal()
        if let prev = previousFrontmostApp {
            NSApp.yieldActivation(to: prev)
        }
    }
}

// MARK: - Entry point

setupLogging()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // Belt-and-suspenders; LSUIElement=true in Info.plist is the primary guard
let delegate = AppDelegate()
app.delegate = delegate
app.run()
