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
    let profile: String?     // nil = open in Chrome without specifying a profile
}

struct Config: Codable {
    let rules: [Rule]
    let defaultProfile: String?  // nil = open without specifying a profile
    let profiles: [String: String]?  // alias → Chrome profile directory name

    func resolveProfile(_ name: String?) -> String? {
        guard let name else { return nil }
        return profiles?[name] ?? name
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

// MARK: - Chrome

func openInChrome(url: String, profile: String?) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    if let profile {
        task.arguments = ["-na", "Google Chrome", "--args", "--profile-directory=\(profile)", url]
        logURL("Opened \(url) in Chrome profile '\(profile)'")
    } else {
        task.arguments = ["-na", "Google Chrome", url]
        logURL("Opened \(url) in Chrome (no profile)")
    }
    do {
        try task.run()
    } catch {
        logURL("ERROR: could not open \(url): \(error)")
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
        // Read the actual sender from the current Apple Event (more reliable than previousFrontmostApp
        // for programmatic file opens where the sending app never becomes frontmost)
        let senderPID = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        let source = senderPID.flatMap { NSRunningApplication(processIdentifier: $0) } ?? previousFrontmostApp
        logURL("File open request: \(filename) — from: \(source?.localizedName ?? "unknown") [\(source?.bundleIdentifier ?? "?")]")
        let config  = loadConfig()
        let profile = routeURL(fileURL, source: source, config: config)
        openInChrome(url: fileURL, profile: config.resolveProfile(profile))
        return true
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: kDirectObject)?.stringValue else {
            log("GetURL event: missing URL")
            return
        }
        let source = previousFrontmostApp
        logURL("Received: \(urlString) — from: \(source?.localizedName ?? "unknown") [\(source?.bundleIdentifier ?? "?")]")
        let config   = loadConfig()
        let profile  = routeURL(urlString, source: source, config: config)
        let resolved = config.resolveProfile(profile)
        openInChrome(url: urlString, profile: resolved)
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
        menu.addItem(menuItem("Chrome Profiles", action: #selector(showProfiles)))
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
        alert(title: "Config Reloaded",
              message: "\(config.rules.count) rule(s)\nDefault profile: \(config.defaultProfile ?? "(none)")")
    }

    @objc func showProfiles() {
        let profiles = listChromeProfiles()
        guard !profiles.isEmpty else {
            alert(title: "Chrome Profiles", message: "No profiles found.")
            return
        }
        let lines = profiles.map { p in
            p.email.isEmpty ? "\(p.dir)  →  \(p.name)" : "\(p.dir)  →  \(p.name)  (\(p.email))"
        }
        alert(title: "Chrome Profiles", message: lines.joined(separator: "\n"))
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

    private func alert(title: String, message: String) {
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
