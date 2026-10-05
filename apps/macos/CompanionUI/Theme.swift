import AppKit
import SwiftUI

/// The design system's tokens (docs/design/tokens.css) for SwiftUI. Do not
/// add colours here that tokens.css does not define.
enum Theme {
    static let bg = dynamic(light: 0xF5F5F7, dark: 0x1C1C1E)
    static let bgElevated = dynamic(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let border = dynamic(light: 0xD2D2D7, dark: 0x3A3A3C)
    static let text = dynamic(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let textSecondary = dynamic(light: 0x6E6E73, dark: 0xA1A1A6)
    static let accent = dynamic(light: 0x0F766E, dark: 0x2DD4BF)
    static let danger = dynamic(light: 0xDC2626, dark: 0xF87171)
    static let dangerMuted = dynamic(light: 0xFEE2E2, dark: 0x450A0A)
    static let progressTrack = dynamic(light: 0xE5E5EA, dark: 0x3A3A3C)
    static let ctaBackground = text
    static let ctaForeground = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)

    static let display = Font.system(size: 28, weight: .semibold)
    static let title = Font.system(size: 20, weight: .semibold)
    static let body = Font.system(size: 14)
    static let caption = Font.system(size: 12)
    static let mono = Font.system(size: 13, design: .monospaced)
    static let monoDisplay = Font.system(size: 32, weight: .medium, design: .monospaced)

    static let column: CGFloat = 420
    static let controlHeight: CGFloat = 40
    static let radiusControl: CGFloat = 8
    static let radiusCard: CGFloat = 12
    static let vaultBarHeight: CGFloat = 40

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                           green: CGFloat((rgb >> 8) & 0xFF) / 255,
                           blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Near-black (light) / near-white (dark) pill: the screen's main action.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body.weight(.medium))
            .foregroundStyle(Theme.ctaForeground)
            .padding(.horizontal, 20)
            .frame(height: Theme.controlHeight)
            .background(Capsule().fill(Theme.ctaBackground))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
    }
}

/// Bordered pill for the other actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body.weight(.medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 20)
            .frame(height: Theme.controlHeight)
            .background(Capsule().fill(Theme.bgElevated))
            .overlay(Capsule().stroke(Theme.border))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Text-only action ("Back").
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body)
            .foregroundStyle(Theme.textSecondary)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
