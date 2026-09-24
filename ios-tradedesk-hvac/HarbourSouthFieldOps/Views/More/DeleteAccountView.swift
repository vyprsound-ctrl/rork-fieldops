import SwiftUI

/// Delete Account (App Store Review Guideline 5.1.1(v)).
///
/// Explains the consequences before anything happens, then deletes the
/// signed-in person's own account on the server — which also ends every
/// session — and signs out.
///
/// Two paths, decided by the server:
///   * anyone but the sole Owner: the account goes; the company, its other
///     people and its records are untouched;
///   * the sole Owner: deleting the account closes the company's Harbour South
///     workspace. That needs a second, explicit confirmation.
struct DeleteAccountView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var context: AccountDeletionContext?
    @State private var loadError: String?
    @State private var isConfirming: Bool = false
    @State private var isConfirmingClosure: Bool = false
    @State private var isDeleting: Bool = false
    @State private var deleteError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let context {
                    consequences(context)
                    deleteButton(context)
                } else if let loadError {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { Task { await load() } }
                        .font(.footnote.weight(.semibold))
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }

                if let deleteError {
                    Text(deleteError)
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("deleteAccount.error")
                }

                LegalLinksView()
            }
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 12)
        }
        .background(Theme.canvas)
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await load() }
        .alert("Delete your account?", isPresented: $isConfirming) {
            Button("Delete account", role: .destructive) { Task { await delete(closeCompany: false) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account and sign-in are deleted and you'll be signed out on every device. This can't be undone.")
        }
        .alert("Close your company's workspace?", isPresented: $isConfirmingClosure) {
            Button("Delete account and close workspace", role: .destructive) { Task { await delete(closeCompany: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You're the only owner of \(context?.companyName ?? "this company"). This closes the workspace for everyone and can't be undone.")
        }
        .sensoryFeedback(.warning, trigger: isConfirmingClosure)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(width: 52, height: 52)
                .background(Theme.red.gradient)
                .clipShape(.rect(cornerRadius: 14))
            Text("Delete your account")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text("Deleting your account removes your name, email and phone number from Harbour South, deletes your sign-in, and signs you out everywhere. It can't be undone.")
                .font(.body)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    @ViewBuilder
    private func consequences(_ context: AccountDeletionContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What happens").sectionLabelStyle()
            VStack(alignment: .leading, spacing: 12) {
                if context.isSoleOwner {
                    point("building.2.crop.circle", "You're the only owner of \(context.companyName). Deleting your account closes the company's Harbour South workspace.")
                    point("person.2.slash", context.otherActiveMembers == 0
                          ? "Nobody else can use the workspace after it's closed."
                          : "The \(context.otherActiveMembers) other \(context.otherActiveMembers == 1 ? "person" : "people") in your company lose access to the workspace.")
                    point("archivebox", "Business and financial records (customers, jobs, quotes, invoices, payments, photos and messages) are kept but can no longer be opened in the app. They're retained, not deleted, so financial records stay intact.")
                    point("creditcard", "Your Stripe account is your company's own and isn't touched. Manage or close it with Stripe.")
                    point("apple.logo", "If you pay for Harbour South through Apple, cancel the subscription in Settings → Apple ID → Subscriptions. Deleting your account doesn't cancel it.")
                    point("person.badge.key", "To keep the company running instead, make someone else an Owner first. Then deleting your account leaves the company as it is.")
                } else {
                    point("building.2", "\(context.companyName.isEmpty ? "Your company" : context.companyName) keeps running. Its customers, jobs, invoices and other records aren't affected.")
                    point("doc.text", "Work you recorded (notes, photos, job history) stays with the company as part of its records, without your name attached.")
                    if context.isOwner {
                        point("apple.logo", "If you pay for Harbour South through Apple, the subscription belongs to the company. Cancel it in Settings → Apple ID → Subscriptions if you no longer want to pay for it.")
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 22)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func deleteButton(_ context: AccountDeletionContext) -> some View {
        Button {
            if context.isSoleOwner {
                isConfirmingClosure = true
            } else {
                isConfirming = true
            }
        } label: {
            HStack(spacing: 8) {
                if isDeleting { ProgressView().tint(Color.white) }
                Text(context.isSoleOwner ? "Delete account and close workspace" : "Delete my account")
                    .font(.headline)
            }
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.red)
            .clipShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(PressableTileStyle())
        .disabled(isDeleting)
        .accessibilityIdentifier("deleteAccount.confirm")
    }

    private func load() async {
        loadError = nil
        do {
            context = try await env.accountDeletionContext()
        } catch {
            loadError = DataError.wrap(error).errorDescription
        }
    }

    private func delete(closeCompany: Bool) async {
        isDeleting = true
        deleteError = nil
        do {
            _ = try await env.deleteAccount(closeCompany: closeCompany)
        } catch {
            deleteError = DataError.wrap(error).errorDescription
        }
        isDeleting = false
    }
}

/// Privacy Policy and Terms of Use, as Apple requires them to be reachable in
/// the app. The privacy link comes from configuration; while no public policy
/// is configured the row says so rather than linking anywhere.
struct LegalLinksView: View {
    var body: some View {
        HStack(spacing: 16) {
            if let privacy = Brand.privacyPolicyURL {
                Link("Privacy Policy", destination: privacy)
                    .accessibilityIdentifier("legal.privacy")
            } else {
                Text("Privacy Policy — coming soon")
                    .foregroundStyle(Theme.meta)
                    .accessibilityIdentifier("legal.privacy.unavailable")
            }
            if let terms = Brand.termsOfUseURL {
                Link("Terms of Use", destination: terms)
                    .accessibilityIdentifier("legal.terms")
            }
        }
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        DeleteAccountView()
    }
    .environment(AppEnvironment())
}
