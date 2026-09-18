import Foundation
import Testing
@testable import URLBouncerCore

final class ProfileDiscoveryTests {
    let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: Chrome

    @Test func chromeProfilesExtractNameAndEmailFromValidPreferences() throws {
        let profileDir = tempDir.appendingPathComponent("Profile 1")
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let prefs: [String: Any] = [
            "account_info": [["full_name": "Jane Doe", "email": "jane@example.com"]],
        ]
        try JSONSerialization.data(withJSONObject: prefs).write(to: profileDir.appendingPathComponent("Preferences"))

        let profiles = listChromeProfiles(baseDir: tempDir)
        #expect(profiles.count == 1)
        #expect(profiles[0].dir == "Profile 1")
        #expect(profiles[0].name == "Jane Doe")
        #expect(profiles[0].email == "jane@example.com")
    }

    @Test func chromeProfileWithMissingPreferencesIsSkipped() throws {
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("Profile 1"), withIntermediateDirectories: true)
        let profiles = listChromeProfiles(baseDir: tempDir)
        #expect(profiles.isEmpty)
    }

    @Test func chromeProfilesAreSortedByDirName() throws {
        for name in ["Profile 3", "Default", "Profile 1"] {
            let dir = tempDir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let prefs: [String: Any] = ["profile": ["name": name]]
            try JSONSerialization.data(withJSONObject: prefs).write(to: dir.appendingPathComponent("Preferences"))
        }
        let profiles = listChromeProfiles(baseDir: tempDir)
        #expect(profiles.map(\.dir) == ["Default", "Profile 1", "Profile 3"])
    }

    @Test func listChromeProfilesReturnsEmptyForMissingBaseDir() {
        let profiles = listChromeProfiles(baseDir: tempDir.appendingPathComponent("does-not-exist"))
        #expect(profiles.isEmpty)
    }

    // MARK: Firefox

    @Test func firefoxProfileNameComesFromMatchingIniSection() throws {
        let profilesDir = tempDir.appendingPathComponent("Profiles")
        let profileDir = profilesDir.appendingPathComponent("abc123.default")
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        let ini = """
        [Profile0]
        Name=default
        IsRelative=1
        Path=Profiles/abc123.default
        Default=1
        """
        let iniPath = tempDir.appendingPathComponent("profiles.ini")
        try ini.write(to: iniPath, atomically: true, encoding: .utf8)

        let profiles = listFirefoxProfiles(baseDir: profilesDir, profilesIniPath: iniPath)
        #expect(profiles.count == 1)
        #expect(profiles[0].dir == "abc123.default")
        #expect(profiles[0].name == "default")
    }

    @Test func firefoxProfileWithNoMatchingIniSectionFallsBackToDirName() throws {
        // Mirrors a real-world case: a manually-created profile directory
        // with no corresponding profiles.ini entry.
        let profilesDir = tempDir.appendingPathComponent("Profiles")
        let profileDir = profilesDir.appendingPathComponent("NCyoQbB6.Profile 1")
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        let ini = """
        [Profile0]
        Name=default
        Path=Profiles/some-other-profile
        """
        let iniPath = tempDir.appendingPathComponent("profiles.ini")
        try ini.write(to: iniPath, atomically: true, encoding: .utf8)

        let profiles = listFirefoxProfiles(baseDir: profilesDir, profilesIniPath: iniPath)
        #expect(profiles.count == 1)
        #expect(profiles[0].name == "NCyoQbB6.Profile 1")
    }

    @Test func firefoxProfilesWithMissingIniFallBackToDirNames() throws {
        let profilesDir = tempDir.appendingPathComponent("Profiles")
        let profileDir = profilesDir.appendingPathComponent("default")
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        let profiles = listFirefoxProfiles(baseDir: profilesDir, profilesIniPath: tempDir.appendingPathComponent("no-such-ini"))
        #expect(profiles.count == 1)
        #expect(profiles[0].name == "default")
    }

    @Test func firefoxProfilesFiltersOutNonDirectoryEntries() throws {
        let profilesDir = tempDir.appendingPathComponent("Profiles")
        try FileManager.default.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        try Data().write(to: profilesDir.appendingPathComponent("stray-file.txt"))
        let profileDir = profilesDir.appendingPathComponent("default")
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)

        let profiles = listFirefoxProfiles(baseDir: profilesDir, profilesIniPath: tempDir.appendingPathComponent("no-such-ini"))
        #expect(profiles.map(\.dir) == ["default"])
    }

    // MARK: Opera

    @Test func operaProfilesListedSortedWithFullPath() throws {
        for name in ["work", "personal"] {
            try FileManager.default.createDirectory(at: tempDir.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let profiles = listOperaProfiles(baseDir: tempDir)
        #expect(profiles.map(\.name) == ["personal", "work"])
        // Compare resolved paths: FileManager's directory enumeration can
        // return a canonicalized path (e.g. /private/var/... instead of
        // /var/...) that differs textually from the unresolved tempDir.
        let expectedPath = tempDir.appendingPathComponent("personal").resolvingSymlinksInPath().path
        #expect(URL(fileURLWithPath: profiles[0].path).resolvingSymlinksInPath().path == expectedPath)
    }

    @Test func operaProfilesFiltersNonDirectories() throws {
        try Data().write(to: tempDir.appendingPathComponent("stray.txt"))
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("work"), withIntermediateDirectories: true)
        let profiles = listOperaProfiles(baseDir: tempDir)
        #expect(profiles.map(\.name) == ["work"])
    }
}
