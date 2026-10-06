import AgentioKit
import AppKit
@preconcurrency import SwiftTerm
import SwiftUI

/// Adding one profile in a terminal, over the hub page.
struct TerminalSheet: View {
    @Bindable var flow: TerminalFlow
    let close: () -> Void
    /// The command once started. The terminal stays after it ends, so the user can read its last lines.
    @State private var command: TerminalCommand?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add \(flow.displayName)").font(Theme.title)
            if let command {
                EmbeddedTerminal(command: command, onStart: { flow.attach(stop: $0) }, onExit: { flow.exited($0) })
                    .id(flow.id)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
            }
            content
        }
        .font(Theme.body)
        .padding(24)
        .frame(width: 720, alignment: .leading)
        .onChange(of: flow.step, initial: true) { _, step in
            if case .running(let started) = step, command == nil { command = started }
        }
    }

    @ViewBuilder private var content: some View {
        switch flow.step {
        case .ready:
            Explanation("agentio asks its questions in a terminal here. Use the arrow keys to choose and Return to confirm.")
            Toggle("Read-only: agents can read, not change anything", isOn: $flow.readOnly)
            buttons(primary: ("Start", flow.start), cancel: "Cancel")
        case .running:
            buttons(primary: nil, cancel: "Cancel")
        case .succeeded:
            Label("\(flow.displayName) added", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.text)
            buttons(primary: ("Done", close), cancel: nil)
        case .ended(let code):
            Text(code.map { "agentio stopped with code \($0)." } ?? "agentio was stopped.").foregroundStyle(Theme.danger)
            buttons(primary: nil, cancel: "Close")
        case .failed(let text):
            Text(text).foregroundStyle(Theme.danger).textSelection(.enabled)
            buttons(primary: nil, cancel: "Close")
        }
    }

    // No .cancelAction shortcut: Esc belongs to the terminal, whose prompts use it.
    private func buttons(primary: (title: String, action: () -> Void)?, cancel: String?) -> some View {
        HStack {
            Spacer()
            if let cancel { Button(cancel, action: close).buttonStyle(SecondaryButtonStyle()) }
            if let primary {
                Button(primary.title, action: primary.action).buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// SwiftTerm's terminal running one command, started once. Removing the view stops the command.
/// (Not named TerminalView: that is SwiftTerm's own class.)
private struct EmbeddedTerminal: NSViewRepresentable {
    let command: TerminalCommand
    /// Gets the way to stop the command, once it runs.
    let onStart: @MainActor (@escaping @MainActor () -> Void) -> Void
    let onExit: @MainActor (Int32?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onExit: onExit) }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.startProcess(executable: command.executable.path, args: command.arguments,
                          environment: command.environment.map { "\($0.key)=\($0.value)" }, execName: "agentio")
        onStart { [weak view] in if let view { Self.stop(view) } }
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {}

    /// The flow stops the process when the sheet closes; this is the backstop if SwiftUI removes the view first.
    static func dismantleNSView(_ view: LocalProcessTerminalView, coordinator: Coordinator) {
        stop(view)
    }

    /// `terminate()` signals the process id even after it ended, so only while it runs.
    private static func stop(_ view: LocalProcessTerminalView) {
        if view.process.running { view.process.terminate() }
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let onExit: @MainActor (Int32?) -> Void
        init(onExit: @escaping @MainActor (Int32?) -> Void) { self.onExit = onExit }

        /// SwiftTerm passes a raw wait status, possibly read too early; `reapedExitCode` decodes the real one.
        func processTerminated(source: TerminalView, exitCode: Int32?) {
            let pid = (source as? LocalProcessTerminalView)?.process.shellPid ?? 0
            let code = reapedExitCode(pid: pid, reported: exitCode ?? 0)
            let onExit = onExit
            Task { @MainActor in onExit(code) }
        }
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}
