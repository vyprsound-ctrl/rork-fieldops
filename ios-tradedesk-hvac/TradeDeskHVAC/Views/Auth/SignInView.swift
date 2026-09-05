import SwiftUI

/// Authentication shell.
///
/// Two stacks live side by side: the development account picker (verifies
/// nothing, runs on simulated data) and production Supabase Auth (real
/// credentials, real tenancy). They are kept separate on purpose — a production
/// identity is never handed to the simulated data layer.
struct SignInView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var mode: AuthMode = .development

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

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
                }
                .padding(Theme.margin)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 56, height: 56)
                .background(Theme.primaryTint)
                .clipShape(.rect(cornerRadius: Theme.cardRadius))
                .padding(.bottom, 6)

            Text("TradeDesk")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Theme.ink)

            Text(mode == .development
                 ? "Choose an account to continue"
                 : "Sign in with your work email")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
        .padding(.top, 12)
    }
}

#Preview {
    SignInView()
        .environment(AppEnvironment())
}
