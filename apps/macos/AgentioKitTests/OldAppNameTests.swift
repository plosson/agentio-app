import Foundation
import Testing
@testable import AgentioKit

private let ourID = "com.plosson.agentio-companion"

/// Makes `<name>` in `dir` an app bundle with `bundleID`, or a folder without Info.plist when nil.
private func makeApp(_ dir: TempDir, _ name: String, bundleID: String?) throws -> URL {
    let app = dir.url.appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: app.appending(path: "Contents"), withIntermediateDirectories: true)
    if let bundleID {
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": bundleID, "CFBundlePackageType": "APPL"], format: .xml, options: 0)
        try plist.write(to: app.appending(path: "Contents/Info.plist"))
    }
    return app
}

private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

/// Discards with removeItem, so the tests never fill the Trash.
private func remove(_ url: URL) throws { try FileManager.default.removeItem(at: url) }

struct OldAppNameTests {
    @Test func theOldNameIsRenamedWhenTheNewNameIsFree() throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let old = try makeApp(dir, OldAppName.oldName, bundleID: ourID)
        let new = dir.url.appending(path: OldAppName.newName, directoryHint: .isDirectory)
        #expect(OldAppName.tidy(bundle: old, bundleID: ourID, discard: remove) == .renamed(new))
        #expect(!exists(old))
        #expect(Bundle(url: new)?.bundleIdentifier == ourID)
    }

    @Test func runningAsTheOldNameReplacesAnOlderNewNameCopy() throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let old = try makeApp(dir, OldAppName.oldName, bundleID: ourID)
        let new = try makeApp(dir, OldAppName.newName, bundleID: ourID)
        try Data("stale".utf8).write(to: new.appending(path: "Contents/stale"))
        #expect(OldAppName.tidy(bundle: old, bundleID: ourID, discard: remove) == .renamed(new))
        #expect(!exists(old))
        #expect(!exists(new.appending(path: "Contents/stale")), "the running copy wins, not the one on disk")
    }

    @Test func runningAsTheNewNameRemovesTheOldCopyAndKeepsRunning() throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let old = try makeApp(dir, OldAppName.oldName, bundleID: ourID)
        let new = try makeApp(dir, OldAppName.newName, bundleID: ourID)
        #expect(OldAppName.tidy(bundle: new, bundleID: ourID, discard: remove) == .removedOther)
        #expect(!exists(old))
        #expect(exists(new))
    }

    @Test func anotherAppWithTheOldNameIsNeverRemoved() throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let other = try makeApp(dir, OldAppName.oldName, bundleID: "com.example.someone-else")
        let new = try makeApp(dir, OldAppName.newName, bundleID: ourID)
        #expect(OldAppName.tidy(bundle: new, bundleID: ourID, discard: remove) == .unchanged)
        #expect(exists(other))
    }

    @Test func anotherAppWithTheNewNameIsNeitherRemovedNorOverwritten() throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let old = try makeApp(dir, OldAppName.oldName, bundleID: ourID)
        let other = try makeApp(dir, OldAppName.newName, bundleID: "com.example.someone-else")
        #expect(OldAppName.tidy(bundle: old, bundleID: ourID, discard: remove) == .unchanged)
        #expect(exists(old))
        #expect(Bundle(url: other)?.bundleIdentifier == "com.example.someone-else")
    }

    @Test func aFolderWithoutInfoPlistIsLeftAlone() throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let notAnApp = try makeApp(dir, OldAppName.oldName, bundleID: nil)
        let new = try makeApp(dir, OldAppName.newName, bundleID: ourID)
        #expect(OldAppName.tidy(bundle: new, bundleID: ourID, discard: remove) == .unchanged)
        #expect(exists(notAnApp))
    }

    @Test func anyOtherFileNameChangesNothing() throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let old = try makeApp(dir, OldAppName.oldName, bundleID: ourID)
        let renamedByUser = try makeApp(dir, "My AgentIO.app", bundleID: ourID)
        #expect(OldAppName.tidy(bundle: renamedByUser, bundleID: ourID, discard: remove) == .unchanged)
        #expect(exists(old))
        #expect(exists(renamedByUser))
    }

    @Test func aFailedDiscardStillLetsTheRenameFailSafely() throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let old = try makeApp(dir, OldAppName.oldName, bundleID: ourID)
        let new = try makeApp(dir, OldAppName.newName, bundleID: ourID)
        let refuse: (URL) throws -> Void = { _ in throw CocoaError(.fileWriteNoPermission) }
        #expect(OldAppName.tidy(bundle: old, bundleID: ourID, discard: refuse) == .unchanged)
        #expect(exists(old), "the running copy stays where it is")
        #expect(exists(new), "the copy it could not discard is not overwritten")
    }

    @Test func aReadOnlyFolderChangesNothing() throws {
        let dir = try TempDir()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.url.path)
            dir.cleanUp()
        }
        let old = try makeApp(dir, OldAppName.oldName, bundleID: ourID)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.url.path)
        #expect(OldAppName.tidy(bundle: old, bundleID: ourID, discard: remove) == .unchanged)
        #expect(exists(old))
    }
}
