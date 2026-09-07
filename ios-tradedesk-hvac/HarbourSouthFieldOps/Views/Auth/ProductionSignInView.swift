import SwiftUI

/// PRODUCTION SIGN-IN — native Supabase Auth over the real database.
///
/// The form collects credentials and, when founding a company, the details the
/// approved `create_company_and_owner()` RPC requires. It deliberately offers no
/// company or role field: both are decided server-side.
struct ProductionSignInView: View {
    @Environment(AppEnvironment.self) private var env

    private enum Flow: String, CaseIterable, Identifiable {
        case signIn
        case createCompany

        var id: String { rawValue }
        var title: String {
            switch self {
            case .signIn: return "Sign in"
            case .createCompany: return "Create company"
            }
        }
    }

    @State private var flow: Flow = .signIn
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var ownerName: String = ""
    @State private var companyName: String = ""
    @State private var trade: Trade = .hvac
    @State private var countryCode: String = "US"
    @State private var currencyCode: String = "USD"

    private var canSubmit: Bool {
        guard !env.authPhase.isBusy else { return false }
        let hasCredentials = email.contains("@") && password.count >= 6
        switch flow {
        case .signIn:
            return hasCredentials
        case .createCompany:
            return hasCredentials
                && !ownerName.trimmingCharacters(in: .whitespaces).isEmpty
                && !companyName.trimmingCharacters(in: .whitespaces).isEmpty
                && countryCode.count == 2
                && currencyCode.count == 3
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if env.isProductionAvailable {
                Picker("Flow", selection: $flow) {
                    ForEach(Flow.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: flow) { _, _ in env.clearAuthError() }

                credentialFields

                if flow == .createCompany {
                    companyFields
                }

                submitButton

                if flow == .signIn {
                    Button("Forgot password?") {
                        Task { await env.requestPasswordReset(email: email) }
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.primary)
                    .disabled(email.isEmpty || env.authPhase.isBusy)
                }

                if let notice = env.passwordResetNotice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Theme.green)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = env.authPhase.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                footnote
            } else {
                notConfigured
            }
        }
    }

    private var credentialFields: some View {
        VStack(spacing: 0) {
            TextField("Work email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(minHeight: Theme.minTap)

            Divider().padding(.leading, 14)

            SecureField("Password", text: $password)
                .textContentType(flow == .signIn ? .password : .newPassword)
                .padding(.horizontal, 14)
                .frame(minHeight: Theme.minTap)
        }
        .cardSurface()
    }

    private var companyFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your company")
                .sectionLabelStyle()

            VStack(spacing: 0) {
                TextField("Your name", text: $ownerName)
                    .textContentType(.name)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Theme.minTap)

                Divider().padding(.leading, 14)

                TextField("Company name", text: $companyName)
                    .textContentType(.organizationName)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Theme.minTap)

                Divider().padding(.leading, 14)

                Picker("Trade", selection: $trade) {
                    ForEach(Trade.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: Theme.minTap)

                Divider().padding(.leading, 14)

                HStack(spacing: 12) {
                    TextField("Country", text: $countryCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Divider()
                    TextField("Currency", text: $currencyCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .frame(minHeight: Theme.minTap)
            }
            .cardSurface()

            Text("You'll be the owner of this company. Your role and company are assigned by the server, not by this app.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if env.authPhase.isBusy { ProgressView().tint(.white) }
                Text(flow == .signIn ? "Sign in" : "Create company")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.minTap)
            .background(canSubmit ? Theme.primary : Theme.primary.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(.rect(cornerRadius: Theme.buttonRadius))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connected to \(BackendConfiguration.summary).")
            Text("Your company and role are read from the database on every sign-in. This app cannot choose either one.")
        }
        .font(.caption)
        .foregroundStyle(Theme.meta)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 4)
    }

    private var notConfigured: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Production sign-in unavailable")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("This build wasn't given Supabase credentials, so there is nothing to authenticate against. Development sign-in still works.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func submit() async {
        switch flow {
        case .signIn:
            await env.signInToProduction(email: email, password: password)
        case .createCompany:
            let registration = CompanyRegistration(
                email: email,
                password: password,
                ownerName: ownerName,
                companyName: companyName,
                trade: trade,
                countryCode: countryCode.uppercased(),
                currencyCode: currencyCode.uppercased()
            )
            await env.signUpToProduction(registration)
        }
        password = ""
    }
}
