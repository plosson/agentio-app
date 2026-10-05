import Foundation
@testable import AgentioKit

/// A fresh temporary folder, removed by the caller with `cleanUp()`.
struct TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "agentio-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: url) }

    func write(_ name: String, _ text: String, executable: Bool = false) throws -> URL {
        let file = url.appending(path: name, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        return file
    }

    func read(_ name: String) -> String? {
        try? String(contentsOf: url.appending(path: name, directoryHint: .notDirectory), encoding: .utf8)
    }
}

let sh = URL(filePath: "/bin/sh")
let plainEnv = ["PATH": "/usr/bin:/bin"]
