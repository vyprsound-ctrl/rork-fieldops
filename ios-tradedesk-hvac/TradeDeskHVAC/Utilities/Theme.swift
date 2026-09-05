import SwiftUI

/// Design tokens for the approved "bright workshop" visual system.
/// Every screen pulls colour, radius and spacing from here so the shells stay consistent.
nonisolated enum Theme {
    // Surfaces
    static let canvas = Color(hex: 0xF7F8FA)
    static let surface = Color.white
    static let border = Color(hex: 0xE3E7ED)

    // Ink
    static let ink = Color(hex: 0x0F1B2A)
    static let secondary = Color(hex: 0x5B6675)
    static let meta = Color(hex: 0x8A94A3)

    // Action
    static let primary = Color(hex: 0x1256D1)
    static let primaryTint = Color(hex: 0xEAF1FE)

    // Semantic status
    static let green = Color(hex: 0x12A150)
    static let amber = Color(hex: 0xE08A00)
    static let red = Color(hex: 0xD93A2B)

    // Geometry
    static let cardRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 12
    static let margin: CGFloat = 16
    static let minTap: CGFloat = 56
}

nonisolated extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// White card with the hairline border used across every screen.
struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.cardRadius

    func body(content: Content) -> some View {
        content
            .background(Theme.surface)
            .clipShape(.rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Theme.border, lineWidth: 1)
            }
    }
}

extension View {
    func cardSurface(radius: CGFloat = Theme.cardRadius) -> some View {
        modifier(CardBackground(radius: radius))
    }

    /// Uppercase tracked section label used above every grouped list.
    func sectionLabelStyle() -> some View {
        self
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.meta)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
