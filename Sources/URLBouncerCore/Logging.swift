import Foundation

// MARK: - Logging

private var logHandle: FileHandle?

// "Log URLs" has no scriptable equivalent from the menu (it's a plain
// NSMenuItem toggle), so integration tests seed it via env var instead of
// driving the menu through fragile UI-scripting.
public var urlLoggingEnabled = ProcessInfo.processInfo.environment["URLBOUNCER_LOG_URLS"] == "1"

public func setupLogging() {
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

public func log(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    logHandle?.write(Data(line.utf8))
}

public func logURL(_ message: String) {
    guard urlLoggingEnabled else { return }
    log(message)
}
