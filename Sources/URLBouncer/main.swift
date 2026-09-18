import AppKit
import URLBouncerCore

// MARK: - Entry point

setupLogging()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // Belt-and-suspenders; LSUIElement=true in Info.plist is the primary guard
let delegate = AppDelegate()
app.delegate = delegate
app.run()
