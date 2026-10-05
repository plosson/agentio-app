import Foundation

/// Set by e.g. a dev launcher; they override NO_COLOR, so drop them.
private let forcedColor: Set<String> = ["FORCE_COLOR", "CLICOLOR_FORCE"]

/// `base` without the user's AGENTIO_* settings, which would steer the
/// installer (AGENTIO_VERSION, AGENTIO_GITHUB_REPO…) or the CLI (an
/// AGENTIO_TOKEN puts it in remote mode and makes `login` refuse).
func isolatedEnv(_ base: [String: String]) -> [String: String] {
    var env = base.filter { !$0.key.hasPrefix("AGENTIO_") && !forcedColor.contains($0.key) }
    // Plain text: colour codes would break the lines the app reads (installer progress, CLI errors).
    env["NO_COLOR"] = "1"
    return env
}

/// Environment for the app's CLI: isolated, with its own HOME.
func cliEnv(_ loc: CliLocation, base: [String: String]) -> [String: String] {
    var env = isolatedEnv(base)
    env["HOME"] = loc.homeDir.path
    return env
}

/// Terminal escape sequences (colours, cursor moves), in case any get through.
public func stripAnsi(_ text: String) -> String {
    text.replacing(/\u{1B}\[[0-9;?]*[ -\/]*[@-~]/, with: "")
}
