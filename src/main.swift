import AppKit
import Foundation
import CoreServices

// MARK: - Apple Event constants ('GURL' / '----')

private let kGetURLEventClass = UInt32(0x4755524c)
private let kGetURLEventID    = UInt32(0x4755524c)
private let kDirectObject     = UInt32(0x2d2d2d2d)

// MARK: - Config

struct Rule: Codable {
    let match: String
    let profile: String
}

struct Config: Codable {
    let rules: [Rule]
    let defaultProfile: String
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
        return Config(rules: [], defaultProfile: "Default")
    }
    return config
}

// MARK: - Router

func routeURL(_ urlString: String, config: Config) -> String {
    guard let components = URLComponents(string: urlString) else {
        return config.defaultProfile
    }
    let host    = (components.host ?? "").lowercased()
    let fullURL = urlString.lowercased()

    for rule in config.rules {
        let pattern = rule.match
        let matched: Bool
        if pattern.hasPrefix("re:") {
            let regex = String(pattern.dropFirst(3))
            matched = urlString.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
        } else if pattern.contains("/") || pattern.contains("?") {
            matched = fullURL.contains(pattern.lowercased())
        } else {
            matched = host.contains(pattern.lowercased())
        }
        if matched {
            log("Rule '\(pattern)' matched \(urlString) → \(rule.profile)")
            return rule.profile
        }
    }
    log("No rule matched \(urlString) → \(config.defaultProfile) (default)")
    return config.defaultProfile
}

// MARK: - Chrome

func openInChrome(url: String, profile: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = ["-na", "Google Chrome", "--args", "--profile-directory=\(profile)", url]
    do {
        try task.run()
        log("Opened \(url) in Chrome profile '\(profile)'")
    } catch {
        log("ERROR: could not open \(url) in profile '\(profile)': \(error)")
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

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!

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
    }

    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: kDirectObject)?.stringValue else {
            log("GetURL event: missing URL")
            return
        }
        log("Received: \(urlString)")
        let config  = loadConfig()
        let profile = routeURL(urlString, config: config)
        openInChrome(url: urlString, profile: profile)
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
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit URLBouncer", action: #selector(NSApplication.terminate(_:))))
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
              message: "\(config.rules.count) rule(s)\nDefault profile: \(config.defaultProfile)")
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
    }
}

// MARK: - Entry point

setupLogging()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // No Dock icon, no Cmd+Tab, but visible in browser picker
let delegate = AppDelegate()
app.delegate = delegate
app.run()
