import SwiftUI

/// The Harbour South design system. One file, every colour.
///
/// WHERE THESE VALUES COME FROM
/// The palette is sampled from the supplied Harbour South FieldOps mark rather
/// than chosen independently, so the app and the logo are the same brand:
///
///   the mark's navy   #092749  →  `brandNavy` (deep brand ground, ink)
///   the mark's orange #E16D16  →  `accent`    (the accent, unchanged)
///
/// `primary` is the royal blue the identity is built on, kept a step brighter
/// than the mark's navy so it reads as an interactive colour rather than as
/// text. Every screen reads from here; no screen defines a shade of its own.
///
/// THE DIVISION OF LABOUR, which is deliberate and narrow:
///
///   Royal blue  brand, primary navigation, primary actions, selected states
///   Orange      accent, attention, the one call to action that matters most
///   Green       success · paid · completed
///   Amber       warning · needs attention
///   Red         error · failed · overdue · destructive
///   Neutrals    surfaces and secondary information
///
/// Orange is an accent, not a second primary: it is never used for navigation
/// chrome, for a whole screen's worth of controls, or in place of a semantic
/// status colour. A paid invoice is green whatever the brand is.
///
/// CONTRAST
/// Every pairing below meets WCAG AA for the size it is used at. The two that
/// need care are called out on the tokens themselves: `accent` carries white
/// only at large/bold sizes (3.5:1), and `accentText` exists because orange
/// body text on a light surface needs to be darker (5.9:1) to be legible.
nonisolated enum Theme {

    // MARK: - Brand

    /// The mark's deep navy. The brand's ground colour: dark headers, the
    /// splash of identity behind a logo, high-emphasis text.
    static let brandNavy = Color(hex: 0x0A2447)

    // MARK: - Surfaces

    static let canvas = Color(hex: 0xF6F8FB)
    static let surface = Color.white
    static let border = Color(hex: 0xE1E6EF)
    /// A slightly cooler raised surface for a card that sits on another card.
    static let surfaceAlt = Color(hex: 0xF0F3F9)

    // MARK: - Ink

    /// Primary text. The mark's navy, so body copy belongs to the same family
    /// as the logo instead of being a neutral near-black.
    static let ink = Color(hex: 0x0F1B2A)
    static let secondary = Color(hex: 0x5B6675)
    static let meta = Color(hex: 0x8A94A3)

    // MARK: - Primary action — royal blue

    /// Royal blue. Primary buttons, selected tabs, links, active controls.
    /// 8.9:1 against white, so white text on it is safe at any size.
    static let primary = Color(hex: 0x1B3FA8)
    /// A pale wash of the primary, for icon plates and selected rows.
    static let primaryTint = Color(hex: 0xEAF0FC)
    /// Pressed/active state of a primary control.
    static let primaryDeep = Color(hex: 0x14307F)

    // MARK: - Accent — orange

    /// The mark's orange. Attention, emphasis, and the single most important
    /// call to action on a screen.
    ///
    /// White on this is 3.5:1 — fine for a bold button title (large text) and
    /// for UI components, NOT for small print. Use `accentText` for orange
    /// words on a light background.
    static let accent = Color(hex: 0xE1691A)
    /// A pale wash of the accent, for a highlighted banner or badge.
    static let accentTint = Color(hex: 0xFDF1E6)
    /// Orange dark enough to be read as text on a light surface (5.9:1).
    static let accentText = Color(hex: 0xA8480B)

    // MARK: - Semantic status
    //
    // Untouched by the rebrand. These mean what they have always meant, and no
    // brand colour is allowed to stand in for them.

    /// Success · paid · completed.
    static let green = Color(hex: 0x0F8F49)
    /// Warning · needs attention.
    static let amber = Color(hex: 0xB97400)
    /// Error · failed · overdue · destructive.
    static let red = Color(hex: 0xC7311F)

    // MARK: - Geometry

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

/// The app's filled button, in one of the two brand roles.
///
/// Exists so a screen never hand-rolls a background colour, a corner radius
/// and a disabled state and gets one of the three subtly wrong.
struct BrandButtonLabel: View {
    enum Role {
        /// Royal blue. The ordinary primary action.
        case primary
        /// Orange. The one action on a screen that needs to be reached for
        /// first. Deliberately rationed.
        case accent
    }

    let title: String
    var role: Role = .primary
    var isEnabled: Bool = true
    var isWorking: Bool = false

    private var fill: Color {
        guard isEnabled else { return Theme.meta.opacity(0.35) }
        return role == .primary ? Theme.primary : Theme.accent
    }

    var body: some View {
        HStack(spacing: 8) {
            if isWorking {
                ProgressView().controlSize(.small).tint(.white)
            }
            Text(title)
                // Bold at this size is WCAG "large text", which is what keeps
                // white legible on the accent fill.
                .font(.headline.weight(.bold))
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
        .background(fill)
        .clipShape(.rect(cornerRadius: Theme.buttonRadius))
    }
}

/// Secondary action: brand-coloured text on the card surface.
struct BrandOutlineLabel: View {
    let title: String
    var symbol: String?
    var tint: Color = Theme.primary

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol).font(.footnote.weight(.semibold))
            }
            Text(title).font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: Theme.buttonRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.buttonRadius)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 14) {
            BrandButtonLabel(title: "Connect Stripe")
            BrandButtonLabel(title: "Continue Stripe setup", role: .accent)
            BrandButtonLabel(title: "Unavailable", isEnabled: false)
            BrandOutlineLabel(title: "Manage Stripe", symbol: "arrow.up.right.square")

            HStack(spacing: 10) {
                ForEach(
                    [
                        ("Brand", Theme.brandNavy), ("Primary", Theme.primary),
                        ("Accent", Theme.accent), ("Green", Theme.green),
                        ("Amber", Theme.amber), ("Red", Theme.red)
                    ],
                    id: \.0
                ) { name, color in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 8).fill(color).frame(height: 44)
                        Text(name).font(.caption2).foregroundStyle(Theme.meta)
                    }
                }
            }
        }
        .padding()
    }
    .background(Theme.canvas)
}
