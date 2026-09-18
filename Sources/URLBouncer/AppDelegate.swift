import AppKit
import CoreServices
import Foundation
import URLBouncerCore

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

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "OK")
        _ = a.runModal()
    }
}
