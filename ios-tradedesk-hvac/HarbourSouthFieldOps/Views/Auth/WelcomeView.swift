import SwiftUI

/// Where someone signed out begins: create a company, join one, or sign in.
///
/// Every route ends in the existing production form; this screen only decides
/// which form opens, so sign-up, invitations and sign-in behave exactly as
/// before.
enum AuthEntry: String, Hashable, Identifiable {
    case createCompany
    case join
    case signIn

    var id: String { rawValue }
}

struct WelcomeView: View {
    @Environment(AppEnvironment.self) private var env
    let onChoose: (AuthEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                BrandMark(size: 64)
                    .padding(.bottom, 6)

                Text("Welcome to FieldOps")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("How would you like to get started?")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            .padding(.top, 12)

            notices

            VStack(spacing: 12) {
                createCard
                joinCard
            }

            Button {
                choose(.signIn)
            } label: {
                (Text("Already have an account? ").foregroundStyle(Theme.secondary)
                    + Text("Sign in").foregroundStyle(Theme.primary).fontWeight(.semibold))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcome.signIn")
        }
    }

    private func choose(_ entry: AuthEntry) {
        env.clearAuthError()
        onChoose(entry)
    }

    /// Messages that arrive while signed out (an account just deleted, a
    /// restored session that no longer has a company) stay visible here.
    @ViewBuilder
    private var notices: some View {
        if let notice = env.accountDeletedNotice {
            Text(notice)
                .font(.footnote)
                .foregroundStyle(Theme.green)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("signIn.accountDeleted")
        }
        if let error = env.authPhase.errorMessage {
            Text(error)
                .font(.footnote)
                .foregroundStyle(Theme.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var createCard: some View {
        Button {
            choose(.createCompany)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "building.2.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.16), in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create a company account")
                        .font(.headline)
                    Text("I'm a business owner or operator setting up Harbour South FieldOps for my company.")
                        .font(.subheadline)
                        .opacity(0.9)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .opacity(0.8)
                    .padding(.top, 4)
            }
            .multilineTextAlignment(.leading)
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Theme.primary, Theme.primary.opacity(0.86)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: .rect(cornerRadius: Theme.cardRadius)
            )
            .shadow(color: Theme.primary.opacity(0.25), radius: 12, y: 6)
        }
        .buttonStyle(PressableTileStyle())
        .accessibilityIdentifier("welcome.createCompany")
    }

    private var joinCard: some View {
        Button {
            choose(.join)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "person.badge.plus")
                    .font(.title3)
                    .foregroundStyle(Theme.primary)
                    .frame(width: 44, height: 44)
                    .background(Theme.primary.opacity(0.08), in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Join an existing company")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text("I've been invited by my employer or a company administrator to join their team.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.meta)
                    .padding(.top, 4)
            }
            .multilineTextAlignment(.leading)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(PressableTileStyle())
        .accessibilityIdentifier("welcome.join")
    }
}
