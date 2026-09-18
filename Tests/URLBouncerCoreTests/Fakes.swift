import Foundation
@testable import URLBouncerCore

struct FakeSourceApp: SourceAppDescribing {
    var bundleIdentifier: String?
    var localizedName: String?
}

final class FakeCommandRunner: CommandRunning {
    struct Invocation: Equatable {
        let executable: String
        let arguments: [String]
    }

    private(set) var launchInvocations: [Invocation] = []
    private(set) var runInvocations: [Invocation] = []

    var launchError: Error?
    var runError: Error?
    var runResult: (exitCode: Int32, stdout: String, stderr: String) = (0, "", "")

    func launch(executable: String, arguments: [String]) throws {
        launchInvocations.append(Invocation(executable: executable, arguments: arguments))
        if let launchError = launchError { throw launchError }
    }

    func run(executable: String, arguments: [String]) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        runInvocations.append(Invocation(executable: executable, arguments: arguments))
        if let runError = runError { throw runError }
        return runResult
    }
}

final class FakeAppOpener: AppOpening {
    struct Invocation: Equatable {
        let url: URL
        let applicationAt: URL
    }

    private(set) var invocations: [Invocation] = []
    var error: Error?

    func open(url: URL, applicationAt: URL) throws {
        invocations.append(Invocation(url: url, applicationAt: applicationAt))
        if let error = error { throw error }
    }
}

final class FakeAlertPresenter: AlertPresenting {
    struct Alert: Equatable {
        let title: String
        let message: String
    }

    private(set) var alerts: [Alert] = []

    func showAlert(title: String, message: String) {
        alerts.append(Alert(title: title, message: message))
    }
}

struct SimpleError: Error {}

struct FakeDefaultBrowserQuery: DefaultBrowserQuerying {
    var bundleID: String?

    func currentDefaultHTTPHandlerBundleID() -> String? { bundleID }
}
