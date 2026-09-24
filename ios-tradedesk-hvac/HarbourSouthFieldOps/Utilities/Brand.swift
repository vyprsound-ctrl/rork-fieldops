import SwiftUI

/// The product's identity, in one place.
///
/// WHY THIS EXISTS
/// The name and the mark were previously typed into whichever screen needed
/// them, which is how a stale product name survived in the sign-in header long
/// after the product had been renamed. Everything user-facing now reads from
/// here, so a future rename is one edit rather than a search.
///
/// REPLACING THE LOGO
/// Drop a new image into the `BrandLogo` image set in `Assets.xcassets` and
/// every screen picks it up — no code change, no layout change. If that asset
/// is ever missing, `BrandMark` falls back to a system symbol rather than
/// rendering a blank space, so the app still looks deliberate.
///
/// The fallback symbol is a bridge arch, echoing the arch in the Harbour South
/// mark. It used to be a wrench and screwdriver, which belonged to the previous
/// product identity and would have reintroduced the old branding on any build
/// where the logo asset failed to load.
nonisolated enum Brand {
    /// The product name, exactly as it should appear to a user.
    static let name = "Harbour South FieldOps"

    /// The company behind it, for copy that talks about the platform itself
    /// rather than the app.
    static let company = "Harbour South"

    /// The image set holding the logo. Swap the contents of this asset to
    /// rebrand; the name is the only contract.
    static let logoAssetName = "BrandLogo"

    /// Used when the asset is absent, so the mark is never an empty box.
    static let fallbackSymbolName = "point.topleft.down.to.point.bottomright.curvepath.fill"

    /// The Info.plist key holding Harbour South's published privacy policy URL.
    static let privacyPolicyInfoKey = "HarbourSouthPrivacyPolicyURL"

    /// Harbour South's published privacy policy, linked from More, the
    /// subscription screen and Delete Account as Apple requires.
    ///
    /// CONFIGURATION-DRIVEN: read from `HarbourSouthPrivacyPolicyURL` in
    /// Info.plist. It is empty until the real policy is published — put the
    /// public https URL there and every entry point opens it, with no code
    /// change. Until then the entry points say the policy is not yet available
    /// rather than linking to an invented address.
    static var privacyPolicyURL: URL? {
        privacyPolicyURL(from: Bundle.main.object(forInfoDictionaryKey: privacyPolicyInfoKey) as? String)
    }

    /// Only a real https address counts.
    static func privacyPolicyURL(from raw: String?) -> URL? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("https://"), let url = URL(string: trimmed), url.host != nil else { return nil }
        return url
    }

    /// Apple's standard licensed application end user licence agreement,
    /// used as the Terms of Use unless a custom EULA is set in App Store Connect.
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

    /// Whether a real logo asset is present in this build.
    static var hasLogoAsset: Bool { UIImage(named: logoAssetName) != nil }
}

/// The Harbour South FieldOps mark, at whatever size the caller needs.
///
/// One view for every placement — sign-in, onboarding, empty states — so the
/// corner radius, inset and fallback behaviour cannot drift apart between
/// screens.
struct BrandMark: View {
    var size: CGFloat = 56
    /// Corner rounding. Defaults to the app's card radius scaled to the mark,
    /// which keeps a small mark from looking like a circle.
    var cornerRadius: CGFloat?

    private var radius: CGFloat { cornerRadius ?? max(10, size * 0.225) }

    var body: some View {
        Group {
            if let image = UIImage(named: Brand.logoAssetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: Brand.fallbackSymbolName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: size, height: size)
                    .background(Theme.primaryTint)
            }
        }
        .clipShape(.rect(cornerRadius: radius))
        .accessibilityLabel(Brand.name)
    }
}

#Preview {
    VStack(spacing: 20) {
        BrandMark(size: 88)
        BrandMark(size: 56)
        BrandMark(size: 32)
        Text(Brand.name).font(.title2.weight(.bold))
    }
    .padding()
    .background(Theme.canvas)
}
