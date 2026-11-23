import SwiftUI
import UIKit

// Eitan Shay design system tokens (from the "Eitan Shay" design system artifact).
// Raw palette switches to the night tones in dark mode, mirroring the web build.

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

enum ES {
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }

    // Surfaces
    static let base = dynamic(0xE9E8E4, 0x1D1D1B)
    static let panel = dynamic(0xF6F5F2, 0x2A2A27)
    static let paper = dynamic(0xFFFFFF, 0x3A3936)
    static let line = dynamic(0xD3D1CB, 0x44433F)
    static let lineSoft = dynamic(0xDFDDD8, 0x3A3936)

    // Text
    static let ink = dynamic(0x1D1D1B, 0xECEBE7)
    static let ink2 = dynamic(0x4B4A46, 0xB5B2AB)
    static let ink3 = dynamic(0x77756F, 0x9A978F)
    static let ink4 = dynamic(0xA9A7A1, 0x6B6963)

    // Accent: one orange, text on it is always ink.
    static let signal = Color(hex: 0xF0662A)
    static let signalPress = Color(hex: 0xD9551C)
    static let signalSoft = dynamic(0xFBE1D5, 0x4A2615)
    static let onSignal = Color(hex: 0x1D1D1B)

    // State
    static let ok = Color(hex: 0x3F9A5B)
    static let warn = Color(hex: 0xC98A12)
    static let error = Color(hex: 0xC8372D)
    static let badgeSignalFG = dynamic(0x8A3410, 0xFBE1D5)
    static let badgeOKBG = dynamic(0xDDEEDF, 0x1F3B29)
    static let badgeOKFG = dynamic(0x245C35, 0xBFE3C9)
    static let badgeWarnBG = dynamic(0xF5E8C8, 0x46350C)
    static let badgeWarnFG = dynamic(0x6E4B06, 0xF2DCA3)
    static let badgeErrorBG = dynamic(0xF6DAD7, 0x4A1E1A)
    static let badgeErrorFG = dynamic(0x7E1F18, 0xF5C9C4)

    // Radii: corners shrink as panels nest.
    static let radiusSm: CGFloat = 7
    static let radiusMd: CGFloat = 10
    static let radiusLg: CGFloat = 14
    static let radiusXl: CGFloat = 16
    static let radius2xl: CGFloat = 20

    static let gutter: CGFloat = 16

    // Motion: one curve, no springs.
    static let ease = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.18)
    static let easeFast = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.12)
    static let easeSlow = Animation.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.32)
}

/// Bundled fonts: Figtree (sans) and JetBrains Mono (mono), static instances.
enum ESFont {
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name: String
        switch weight {
        case .semibold: name = "Figtree-SemiBold"
        case .bold, .heavy, .black: name = "Figtree-Bold"
        case .medium: name = "Figtree-Medium"
        default: name = "Figtree-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium, relativeTo style: Font.TextStyle = .caption) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black, .semibold: name = "JetBrainsMono-Bold"
        case .medium: name = "JetBrainsMono-Medium"
        default: name = "JetBrainsMono-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    static let display = sans(46, .semibold, relativeTo: .largeTitle)
    static let h2 = sans(30, .semibold, relativeTo: .title)
    static let h3 = sans(22, .semibold, relativeTo: .title3)
    static let lead = sans(18, .regular, relativeTo: .body)
    static let body = sans(16, .regular, relativeTo: .body)
    static let small = sans(14, .regular, relativeTo: .subheadline)
    static let label = mono(11, .medium, relativeTo: .caption2)
    static let model = mono(13, .bold, relativeTo: .caption)
}
