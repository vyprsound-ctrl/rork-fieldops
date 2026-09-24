import SwiftUI

/// Authentication shell.
///
/// **Release builds have exactly one sign-in path: production Supabase Auth.**
/// The development account picker verifies no credentials and runs on simulated
/// data, so it is compiled in for DEBUG builds only — the mode switch below and
/// the picker itself are absent from an App Store or TestFlight binary rather
/// than hidden inside it.
///
/// The two stacks stay separate for the same reason they always did: a
/// production identity is never handed to the simulated data layer.
struct SignInView: View {
    @Environment(AppEnvironment.self) private var env
    #if DEBUG
    @State private var mode: AuthMode = .development
    #endif

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    #if DEBUG
                    Picker("Mode", selection: $mode) {
                        ForEach(AuthMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _, _ in env.clearAuthError() }

                    switch mode {
                    case .development:
                        DevelopmentAccountPicker()
                    case .production:
                        ProductionSignInView()
                    }
                    #else
                    ProductionSignInView()
                    #endif

                    LegalSheetLinks()
                        .padding(.top, 8)
                }
                .padding(Theme.margin)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            BrandMark(size: 64)
                .padding(.bottom, 6)

            Text(Brand.name)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
        .padding(.top, 12)
    }

    /// Release builds only ever offer the production form, so the subtitle is
    /// fixed there rather than describing a mode that cannot be selected.
    private var subtitle: String {
        #if DEBUG
        return mode == .development
            ? "Choose an account to continue"
            : "Sign in with your work email"
        #else
        return "Sign in with your work email"
        #endif
    }
}

#Preview {
    SignInView()
        .environment(AppEnvironment())
}
