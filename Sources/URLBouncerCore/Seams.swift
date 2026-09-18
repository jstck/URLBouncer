import AppKit
import Foundation

// MARK: - Process-launching seam
//
// Wraps Process() so opener argument construction can be unit-tested
// without spawning real processes.

public protocol CommandRunning {
    func launch(executable: String, arguments: [String]) throws
    func run(executable: String, arguments: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String)
}

public struct RealCommandRunner: CommandRunning {
    public init() {}

    public func launch(executable: String, arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        try task.run()
    }

    public func run(executable: String, arguments: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        try task.run()
        task.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        return (
            task.terminationStatus,
            String(data: outputData, encoding: .utf8) ?? "",
            String(data: errorData, encoding: .utf8) ?? ""
        )
    }
}

// MARK: - App-by-path seam
//
// Wraps NSWorkspace.shared.open(...withApplicationAt:...) for the same reason.

public protocol AppOpening {
    func open(url: URL, applicationAt: URL) throws
}

public struct RealAppOpener: AppOpening {
    public init() {}

    public func open(url: URL, applicationAt: URL) throws {
        NSWorkspace.shared.open([url], withApplicationAt: applicationAt, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - Alert seam
//
// NSAlert().runModal() blocks forever in a headless test run, so every
// opener error path needs this seam to be testable at all.

public protocol AlertPresenting {
    func showAlert(title: String, message: String)
}

public struct RealAlertPresenter: AlertPresenting {
    public init() {}

    public func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "OK")
        _ = a.runModal()
    }
}
