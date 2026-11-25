import SwiftUI

/// Authentication shell.
///
/// **Release builds have exactly one sign-in path: production Supabase Auth.**
/// The development account picker verifies no credentials and runs on simulated
/// data, so it is compiled in for DEBUG builds only — the mode switch below and
/// the picker itself are absent from an App Store or TestFlight binary rather
/// than hidden inside it.
///
/// Production always opens on the Welcome screen. An invitation link opens
/// Join, and a confirmation email just sent opens Sign in.
struct SignInView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var entry: AuthEntry?
    #if DEBUG
    @State private var mode: AuthMode = .development
    #endif

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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
                        header(subtitle: "Choose an account to continue")
                        DevelopmentAccountPicker()
                    case .production:
                        production
                    }
                    #else
                    production
                    #endif

                    LegalSheetLinks()
                        .padding(.top, 8)
                }
                .padding(Theme.margin)
                // Centred and readable on iPad, in Split View and when resized.
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: entry)
        .onChange(of: env.pendingInvitationLink) { _, payload in
            if payload != nil { entry = .join }
        }
        .onChange(of: env.pendingEmailConfirmation) { _, address in
            if let address, !address.isEmpty { entry = .signIn }
        }
        .onAppear {
            if env.pendingInvitationLink != nil {
                entry = .join
            } else if let address = env.pendingEmailConfirmation, !address.isEmpty {
                entry = .signIn
            }
        }
    }

    @ViewBuilder
    private var production: some View {
        if let entry {
            // One form for every route: switching route (an invitation
            // arriving, a confirmation email sent) keeps what was typed.
            ProductionSignInView(entry: $entry, flow: entry)
                .transition(.opacity)
        } else {
            WelcomeView { choice in entry = choice }
                .transition(.opacity)
        }
    }

    private func header(subtitle: String) -> some View {
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
}

#Preview {
    SignInView()
        .environment(AppEnvironment())
}
