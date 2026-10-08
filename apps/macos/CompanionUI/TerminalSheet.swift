import AgentioKit
import AppKit
@preconcurrency import SwiftTerm
import SwiftUI

/// Adding a profile, or signing one in again, in a terminal over the hub page.
struct TerminalSheet: View {
    @Bindable var flow: TerminalFlow
    let close: () -> Void
    /// The command once started. The terminal stays after it ends, so the user can read its last lines.
    @State private var command: TerminalCommand?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(flow.profile.map { "Sign In to \(flow.displayName) Again: \($0)" } ?? "Add \(flow.displayName)").font(Theme.title)
            if let command {
                EmbeddedTerminal(command: command, dark: colorScheme == .dark,
                                 onStart: { flow.attach(stop: $0) }, onExit: { flow.exited($0) })
                    .id(flow.id)
                    .padding(14)
                    .frame(height: 360)
                    .background(Theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(Theme.border))
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
            Text("agentio asks its questions in a terminal here. Use the arrow keys to choose and Return to confirm.")
                .foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Read-only: agents can read, not change anything", isOn: $flow.readOnly)
            buttons(primary: ("Start", flow.start), cancel: "Cancel")
        case .running:
            buttons(primary: nil, cancel: "Cancel")
        case .succeeded:
            Label(flow.profile == nil ? "\(flow.displayName) added" : "Signed in again", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.text)
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
    /// Dark mode: the terminal takes its colours from the sheet's, which SwiftTerm cannot follow by itself.
    let dark: Bool
    /// Gets the way to stop the command, once it runs.
    let onStart: @MainActor (@escaping @MainActor () -> Void) -> Void
    let onExit: @MainActor (Int32?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onExit: onExit) }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        style(view)
        view.startProcess(executable: command.executable.path, args: command.arguments,
                          environment: command.environment.map { "\($0.key)=\($0.value)" }, execName: "agentio")
        onStart { [weak view] in if let view { Self.stop(view) } }
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) { style(view) }

    /// The sheet's colours (Theme.bg, Theme.text), and a palette that reads well on them.
    private func style(_ view: LocalProcessTerminalView) {
        view.nativeBackgroundColor = Theme.resolved(Theme.bg, dark: dark)
        view.nativeForegroundColor = Theme.resolved(Theme.text, dark: dark)
        view.caretColor = Theme.resolved(Theme.textSecondary, dark: dark)
        view.selectedTextBackgroundColor = .selectedTextBackgroundColor
        view.installColors((dark ? Self.darkPalette : Self.lightPalette).map { rgb in
            SwiftTerm.Color(red: UInt16((rgb >> 16) & 0xFF) * 257, green: UInt16((rgb >> 8) & 0xFF) * 257,
                            blue: UInt16(rgb & 0xFF) * 257)
        })
    }

    /// The 16 ANSI colours: black, red, green, yellow, blue, magenta, cyan, white, then their bright forms.
    private static let lightPalette: [UInt32] = [
        0x1D1D1F, 0xC4302B, 0x1E8E3E, 0x9A6700, 0x0B63CE, 0x8E44AD, 0x00838F, 0x6E6E73,
        0x6E6E73, 0xDC2626, 0x16A34A, 0xB45309, 0x2563EB, 0x9333EA, 0x0891B2, 0x1D1D1F,
    ]
    private static let darkPalette: [UInt32] = [
        0x8E8E93, 0xF87171, 0x4ADE80, 0xFACC15, 0x60A5FA, 0xC084FC, 0x22D3EE, 0xD1D1D6,
        0xA1A1A6, 0xFCA5A5, 0x86EFAC, 0xFDE047, 0x93C5FD, 0xD8B4FE, 0x67E8F9, 0xF5F5F7,
    ]

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
            // Nothing more to type: no blinking caret under the last line.
            source.getTerminal().hideCursor()
            let onExit = onExit
            Task { @MainActor in onExit(code) }
        }
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}
