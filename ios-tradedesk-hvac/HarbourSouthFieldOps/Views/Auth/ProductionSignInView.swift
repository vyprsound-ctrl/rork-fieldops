import SwiftUI

/// PRODUCTION SIGN-IN — native Supabase Auth over the real database.
///
/// The form collects credentials and, when founding a company, the details the
/// approved `create_company_and_owner()` RPC requires. It deliberately offers no
/// company or role field: both are decided server-side.
struct ProductionSignInView: View {
    @Environment(AppEnvironment.self) private var env

    /// The route chosen on Welcome. Setting it to `nil` returns there.
    @Binding var entry: AuthEntry?
    /// The route this form is showing.
    let flow: AuthEntry

    init(entry: Binding<AuthEntry?>, flow: AuthEntry) {
        self._entry = entry
        self.flow = flow
    }

    private enum Field: Hashable {
        case email, password, ownerName, companyName, joinName, joinCode
    }

    @FocusState private var focused: Field?
    /// Fields the person has left at least once. Problems are only pointed
    /// out after that, so an empty form doesn't open covered in red.
    @State private var touched: Set<Field> = []

    /// ISSUE #15 — the currencies a new company may be created in.
    ///
    /// Exactly the set the supported markets trade in, so an unsupported
    /// currency cannot be entered. Deduplicated because Ireland and any future
    /// euro market share one.
    private static let selectableCurrencyCodes: [String] = {
        var seen = Set<String>()
        return SupportedMarket.allCases
            .map(\.defaultCurrencyCode)
            .filter { seen.insert($0).inserted }
    }()

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var ownerName: String = ""
    @State private var companyName: String = ""
    @State private var trade: Trade = .hvac
    /// ISSUE #15 — country and currency were two free-text boxes, so a company
    /// could be founded in a market Stripe Connect cannot serve and only find
    /// out on the day it tried to get paid. The market is now chosen from the
    /// list Harbour South actually supports, and it supplies the currency.
    @State private var market: SupportedMarket = .fallback
    @State private var currencyCode: String = SupportedMarket.fallback.defaultCurrencyCode
    @State private var joinName: String = ""
    @State private var joinCode: String = ""

    // MARK: - Validation

    private static let minimumPassword = AuthError.minimumPasswordLength

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var emailIsValid: Bool {
        trimmedEmail.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }

    /// Sign-in only needs a password; length rules apply to new passwords.
    private var passwordIsValid: Bool {
        flow == .signIn ? !password.isEmpty : password.count >= Self.minimumPassword
    }

    private func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var joinCodeIsValid: Bool {
        joinCode.trimmingCharacters(in: .whitespaces).count >= 6
    }

    /// What still stops the form being sent, in the order the fields appear.
    private var missing: [String] {
        var items: [String] = []
        if trimmedEmail.isEmpty {
            items.append("your email")
        } else if !emailIsValid {
            items.append("a valid email address")
        }
        if flow == .signIn {
            if password.isEmpty { items.append("your password") }
        } else if password.count < Self.minimumPassword {
            items.append("a password of at least \(Self.minimumPassword) characters")
        }
        switch flow {
        case .signIn:
            break
        case .join:
            if isBlank(joinName) { items.append("your name") }
            if !joinCodeIsValid { items.append("the join code from your invitation") }
        case .createCompany:
            // The market and currency pickers are closed sets, so neither can
            // be missing or invalid.
            if isBlank(ownerName) { items.append("your name") }
            if isBlank(companyName) { items.append("your company name") }
        }
        return items
    }

    private var missingSummary: String {
        "To continue, add \(ListFormatter.localizedString(byJoining: missing))."
    }

    private var canSubmit: Bool {
        !env.authPhase.isBusy && missing.isEmpty
    }

    private var isNetworkFailure: Bool {
        env.authPhase.errorMessage == AuthError.network.errorDescription
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if env.isProductionAvailable {
                header

                credentialFields

                if flow == .createCompany {
                    companyFields
                }

                if flow == .join {
                    joinFields
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

                if let notice = env.signUpNotice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Theme.green)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let notice = env.passwordResetNotice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Theme.green)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let notice = env.accountDeletedNotice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Theme.green)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("signIn.accountDeleted")
                }

                if let error = env.authPhase.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("signIn.error")
                        if isNetworkFailure {
                            Button {
                                Task { await submit() }
                            } label: {
                                Label("Try again", systemImage: "arrow.clockwise")
                                    .font(.footnote.weight(.semibold))
                            }
                            .foregroundStyle(Theme.primary)
                            .disabled(!canSubmit)
                        }
                    }
                }
            } else {
                backButton
                notConfigured
            }
        }
        .onChange(of: focused) { previous, _ in
            if let previous { touched.insert(previous) }
        }
        .onChange(of: flow) { _, _ in
            touched = []
        }
        // An invitation tapped in an email lands here. The code is copied into
        // the form once and then released, so a later redraw never overwrites
        // something the person has since typed.
        .onChange(of: env.pendingInvitationLink) { _, payload in
            adopt(payload)
        }
        // A confirmation email has gone out. Whatever form they were on, the
        // next thing they need on their return is Sign in — see below.
        .onChange(of: env.pendingEmailConfirmation) { _, address in
            awaitConfirmation(of: address)
        }
        .onAppear {
            adopt(env.pendingInvitationLink)
            awaitConfirmation(of: env.pendingEmailConfirmation)
        }
    }

    private func adopt(_ payload: InvitationLink.Payload?) {
        guard let payload else { return }
        entry = .join
        joinCode = payload.token
        if !payload.name.isEmpty, joinName.trimmingCharacters(in: .whitespaces).isEmpty {
            joinName = payload.name
        }
        env.consumePendingInvitationLink()
    }

    /// Moves the form to Sign in once a confirmation email has been sent.
    ///
    /// This is the fix for coming back from the inbox and finding Join still
    /// on screen. Join is not merely the wrong tab at that point, it is a dead
    /// end: the invitation code is parked on the identity and spent by the
    /// first authenticated session, so redeeming it a second time fails. The
    /// person's real next step is to sign in with the email and password they
    /// just chose, and the join completes itself server-side.
    ///
    /// The email is carried across so they are typing one field, not three.
    /// Everything invitation-specific is cleared, because none of it applies to
    /// a sign-in.
    private func awaitConfirmation(of address: String?) {
        guard let address, !address.isEmpty else { return }
        entry = .signIn
        email = address
        password = ""
        joinCode = ""
        joinName = ""
        env.consumePendingEmailConfirmation()
    }

    // MARK: - Header

    private var backButton: some View {
        Button {
            env.clearAuthError()
            entry = nil
        } label: {
            Label("Back", systemImage: "chevron.left")
                .font(.body.weight(.medium))
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .foregroundStyle(Theme.primary)
        .accessibilityIdentifier("auth.back")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            backButton

            BrandMark(size: 48)
                .padding(.top, 2)

            Text(headerTitle)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerTitle: String {
        switch flow {
        case .signIn: return "Sign in"
        case .join: return "Join your company"
        case .createCompany: return "Create a company account"
        }
    }

    private var headerSubtitle: String {
        switch flow {
        case .signIn:
            return "Sign in with your work email."
        case .join:
            return "Use the email address your invitation was sent to, choose a password, and enter the join code from your invitation."
        case .createCompany:
            return "You're creating a new company account and you'll be its owner. You can invite your team once you're set up. All fields are required."
        }
    }

    // MARK: - Fields

    private func fieldHint(_ text: String, isProblem: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if isProblem {
                Image(systemName: "exclamationmark.circle.fill")
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(isProblem ? Theme.red : Theme.meta)
        .padding(.horizontal, 4)
    }

    private var emailProblem: String? {
        guard touched.contains(.email) else { return nil }
        if trimmedEmail.isEmpty { return "Enter your email address." }
        if !emailIsValid { return "Enter a valid email address, like name@company.com." }
        return nil
    }

    private var passwordProblem: String? {
        guard touched.contains(.password) else { return nil }
        if password.isEmpty { return flow == .signIn ? "Enter your password." : "Choose a password." }
        if flow != .signIn, password.count < Self.minimumPassword {
            return "Use at least \(Self.minimumPassword) characters."
        }
        return nil
    }

    private var credentialFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 0) {
                TextField("Work email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
                    .padding(.horizontal, 14)
                    .frame(minHeight: Theme.minTap)
                    .accessibilityIdentifier("auth.email")

                Divider().padding(.leading, 14)

                SecureField(flow == .signIn ? "Password" : "Choose a password", text: $password)
                    .textContentType(flow == .signIn ? .password : .newPassword)
                    .focused($focused, equals: .password)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Theme.minTap)
                    .accessibilityIdentifier("auth.password")
            }
            .cardSurface()

            if let emailProblem {
                fieldHint(emailProblem, isProblem: true)
            }
            if let passwordProblem {
                fieldHint(passwordProblem, isProblem: true)
            } else if flow != .signIn {
                fieldHint("At least \(Self.minimumPassword) characters. Only you will know it.", isProblem: false)
            }
        }
    }

    private var companyFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your company")
                .sectionLabelStyle()

            VStack(spacing: 0) {
                TextField("Your name", text: $ownerName)
                    .textContentType(.name)
                    .focused($focused, equals: .ownerName)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Theme.minTap)

                Divider().padding(.leading, 14)

                TextField("Company name", text: $companyName)
                    .textContentType(.organizationName)
                    .focused($focused, equals: .companyName)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Theme.minTap)

                Divider().padding(.leading, 14)

                LabeledContent("Business type") {
                    Picker("Business type", selection: $trade) {
                        ForEach(Trade.setupOptions) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                }
                .padding(.horizontal, 14)
                .frame(minHeight: Theme.minTap)

                Divider().padding(.leading, 14)

                LabeledContent("Country") {
                    Picker("Country", selection: $market) {
                        ForEach(SupportedMarket.allCases) { item in
                            Text(item.countryName).tag(item)
                        }
                    }
                    .labelsHidden()
                }
                .padding(.horizontal, 14)
                .frame(minHeight: Theme.minTap)
                // Choosing a country sets the currency it trades in. It stays a
                // separate, explicit value — a business may invoice in another
                // currency — but it is never left to be typed from scratch.
                .onChange(of: market) { _, newValue in
                    currencyCode = newValue.defaultCurrencyCode
                }

                Divider().padding(.leading, 14)

                LabeledContent("Currency") {
                    Picker("Currency", selection: $currencyCode) {
                        ForEach(Self.selectableCurrencyCodes, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .labelsHidden()
                }
                .padding(.horizontal, 14)
                .frame(minHeight: Theme.minTap)
            }
            .cardSurface()

            if touched.contains(.ownerName), isBlank(ownerName) {
                fieldHint("Enter your name.", isProblem: true)
            }
            if touched.contains(.companyName), isBlank(companyName) {
                fieldHint("Enter your company's name.", isProblem: true)
            }

            fieldHint("You'll be the owner of this company account.", isProblem: false)
        }
    }

    private var joinFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Join a company")
                .sectionLabelStyle()

            VStack(spacing: 0) {
                TextField("Your name", text: $joinName)
                    .textContentType(.name)
                    .focused($focused, equals: .joinName)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Theme.minTap)

                Divider().padding(.leading, 14)

                TextField("Join code", text: $joinCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .joinCode)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 14)
                    .frame(minHeight: Theme.minTap)
            }
            .cardSurface()

            if touched.contains(.joinName), isBlank(joinName) {
                fieldHint("Enter your name.", isProblem: true)
            }
            if touched.contains(.joinCode), !joinCodeIsValid {
                fieldHint("Enter the join code from your invitation email.", isProblem: true)
            }

            fieldHint("Tapping the link in your invitation email fills in the code for you. Your company and role come from your invitation.", isProblem: false)
        }
    }

    /// The single action on the whole screen, so it carries the accent.
    ///
    /// Bold at this size is WCAG "large text", which is what keeps white
    /// legible on the orange fill.
    private var submitButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                focused = nil
                Task { await submit() }
            } label: {
                HStack(spacing: 8) {
                    if env.authPhase.isBusy { ProgressView().tint(.white) }
                    Text(submitTitle)
                        .font(.body.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: Theme.minTap)
                .background(canSubmit ? Theme.accent : Theme.accent.opacity(0.35))
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: Theme.buttonRadius))
            }
            .buttonStyle(PressableTileStyle())
            .disabled(!canSubmit)
            .accessibilityIdentifier("auth.submit")
            .accessibilityHint(missing.isEmpty ? "" : missingSummary)

            // A disabled button always says why.
            if !env.authPhase.isBusy, !missing.isEmpty {
                fieldHint(missingSummary, isProblem: false)
                    .accessibilityIdentifier("auth.missing")
            }
        }
    }

    private var submitTitle: String {
        switch flow {
        case .signIn: return "Sign in"
        case .join: return "Join company"
        case .createCompany: return "Create company account"
        }
    }

    private var notConfigured: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sign-in unavailable")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(AuthError.notConfigured.errorDescription ?? "")
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
        case .join:
            await env.joinCompany(
                InvitationRedemption(
                    email: email,
                    password: password,
                    name: joinName,
                    token: joinCode
                )
            )
        case .createCompany:
            let registration = CompanyRegistration(
                email: email,
                password: password,
                ownerName: ownerName,
                companyName: companyName,
                trade: trade,
                countryCode: market.countryCode,
                currencyCode: currencyCode.uppercased()
            )
            await env.signUpToProduction(registration)
        }
        // Kept only after a connection failure, so Try again can resend it.
        if !isNetworkFailure {
            password = ""
            touched.remove(.password)
        }
    }
}
