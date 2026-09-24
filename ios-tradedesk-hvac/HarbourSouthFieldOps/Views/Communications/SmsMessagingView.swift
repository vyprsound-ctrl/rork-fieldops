import SwiftUI

/// More → SMS & Messaging. Owner-only setup and control of the company's own
/// dedicated number. Written so a trade business owner never has to know what
/// Twilio is.
struct SmsMessagingView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = SmsSetupViewModel()
    @State private var isSettingUp: Bool = false
    @State private var isChoosingNumber: Bool = false
    @State private var isConfirmingRelease: Bool = false

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch viewModel.state {
                case .idle, .loading:
                    LoadingStateView(message: "Checking SMS")
                case .failed(let error):
                    ErrorStateView(error: error) { Task { await reload() } }
                case .loaded(let status):
                    loaded(status)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 12)
        }
        .background(Theme.canvas)
        .navigationTitle("SMS & Messaging")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await reload(showLoading: false) }
        .task(id: session?.userID) { await reload() }
        .sheet(isPresented: $isSettingUp) {
            SmsSetupFlowView { result in
                viewModel.apply(result)
            }
        }
        .sheet(isPresented: $isChoosingNumber) {
            SmsSetupFlowView(onlyChooseNumber: true) { result in
                viewModel.apply(result)
            }
        }
        .alert("Turn off SMS and release your number?", isPresented: $isConfirmingRelease) {
            Button("Turn off SMS", role: .destructive) {
                guard let session else { return }
                Task { await viewModel.release(gateway: env.gateway, session: session) }
            }
            Button("Keep SMS", role: .cancel) {}
        } message: {
            Text("Customers will no longer be able to text your number and you won't be able to text them. Released numbers usually can't be recovered.")
        }
    }

    @ViewBuilder
    private func loaded(_ status: MessagingSetupStatus) -> some View {
        statusHero(status)

        if let notice = viewModel.notice { banner(notice, tone: Theme.primary, symbol: "info.circle.fill") }
        if let error = viewModel.actionError { banner(error, tone: Theme.red, symbol: "exclamationmark.triangle.fill") }

        if !status.canManage {
            banner("Only the company owner can set up or change SMS.", tone: Theme.secondary, symbol: "lock.fill")
        } else {
            actions(status)
        }

        if status.friendly == .notSetUp || status.friendly == .needsAttention {
            explainer(status)
        } else {
            details(status)
        }

        responsibilityCard

        VStack(alignment: .leading, spacing: 8) {
            Text("Read more").sectionLabelStyle()
            LegalLinksView(documents: [.smsTerms, .privacyPolicy, .termsOfService])
        }
    }

    // MARK: Hero

    private func statusHero(_ status: MessagingSetupStatus) -> some View {
        let tint = color(status.friendly.tone)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: status.friendly.symbolName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 54, height: 54)
                    .background(tint.gradient)
                    .clipShape(.rect(cornerRadius: 15))
                    .symbolEffect(.pulse, isActive: status.friendly == .settingUp || status.friendly == .waitingApproval)
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.friendly.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("sms.status.title")
                    Text(subtitle(status))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let number = status.displayNumber {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your business number").font(.caption).foregroundStyle(Theme.meta)
                        Text(number)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Image(systemName: "phone.bubble.fill")
                        .font(.title2)
                        .foregroundStyle(tint)
                }
                .padding(14)
                .background(tint.opacity(0.08))
                .clipShape(.rect(cornerRadius: 12))
            }

            if status.friendly == .waitingApproval {
                ApprovalProgress(status: status)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func subtitle(_ status: MessagingSetupStatus) -> String {
        if let attention = status.attention { return attention }
        switch status.friendly {
        case .notSetUp:
            return status.providerAvailable
                ? "Text customers from your own business number."
                : "SMS isn't available yet. Harbour South is finishing its setup."
        case .settingUp: return "We're creating your business number. This usually takes a minute."
        case .waitingApproval:
            return status.solePropVerificationPending
                ? "Check your mobile: reply YES to the verification text so carriers can approve you."
                : "Carriers are reviewing your registration. This usually takes a few days. We'll notify you when it's approved."
        case .ready: return "Customers get texts from your number and their replies land in Communications."
        case .needsAttention: return "Something needs fixing before you can text customers."
        case .suspended: return "SMS is paused for your company."
        }
    }

    // MARK: Actions

    @ViewBuilder
    private func actions(_ status: MessagingSetupStatus) -> some View {
        VStack(spacing: 10) {
            if status.needsNumberChoice {
                primaryButton("Choose a new number", symbol: "number") { isChoosingNumber = true }
            } else if status.friendly == .notSetUp {
                primaryButton("Set Up SMS", symbol: "sparkles") { isSettingUp = true }
                    .disabled(!status.providerAvailable || !status.hasSubscription)
                    .accessibilityIdentifier("sms.setup.start")
                if !status.hasSubscription {
                    Text("SMS needs an active Harbour South subscription.")
                        .font(.caption).foregroundStyle(Theme.amber)
                }
            } else if status.friendly == .needsAttention, status.billingState != "paused" {
                primaryButton("Update details and resubmit", symbol: "arrow.clockwise") { isSettingUp = true }
                secondaryButton("Try again", symbol: "arrow.triangle.2.circlepath") {
                    guard let session else { return }
                    Task { await viewModel.refresh(gateway: env.gateway, session: session, retry: true) }
                }
            } else if status.friendly == .settingUp || status.friendly == .waitingApproval {
                secondaryButton(viewModel.isWorking ? "Checking…" : "Check progress", symbol: "arrow.clockwise") {
                    guard let session else { return }
                    Task { await viewModel.refresh(gateway: env.gateway, session: session, retry: false) }
                }
                .disabled(viewModel.isWorking)
            }
            if status.billingState != "current" {
                NavigationLink(value: AppRoute.more(.smsCredits)) {
                    label("Add SMS credits", symbol: "plus.circle.fill", filled: true)
                }
                .buttonStyle(PressableTileStyle())
            }
        }
        if status.phoneNumber != nil, status.friendly != .suspended {
            Button(role: .destructive) { isConfirmingRelease = true } label: {
                Text("Turn off SMS and release number")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .tint(Theme.red)
        }
    }

    private func primaryButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { label(title, symbol: symbol, filled: true) }
            .buttonStyle(PressableTileStyle())
    }

    private func secondaryButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { label(title, symbol: symbol, filled: false) }
            .buttonStyle(PressableTileStyle())
    }

    private func label(_ title: String, symbol: String, filled: Bool) -> some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(filled ? Color.white : Theme.primary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(filled ? AnyShapeStyle(Theme.accent.gradient) : AnyShapeStyle(Theme.primaryTint))
            .clipShape(.rect(cornerRadius: Theme.buttonRadius))
    }

    // MARK: Explainer & details

    private func explainer(_ status: MessagingSetupStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it works").sectionLabelStyle()
            VStack(alignment: .leading, spacing: 14) {
                point("hand.raised", "SMS is optional", "Turn it on only if you want to text customers from Harbour South.")
                point("phone.fill", "Your own number", "You get a dedicated local number that only your business uses. No other account or contract needed.")
                point("creditcard", "Pay as you go", "Texts use SMS credits (1 credit per text segment). Your number is \(status.numberFeeLabel)/month, taken from your credits.\(status.setupFeeCents == 0 ? " No setup fee." : "")")
                point("checkmark.shield", "Carrier approval", "US carriers must approve every business that texts. It usually takes a few days.")
                point("building.2", "Accurate business details", "Use your real legal business name and details. They're checked by carriers.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private func details(_ status: MessagingSetupStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details").sectionLabelStyle()
            VStack(spacing: 0) {
                row("Monthly number fee", "\(status.numberFeeLabel) · \(status.numberFeeCredits) credits")
                Divider().padding(.leading, 14)
                if let due = status.nextFeeDueAt {
                    row("Next fee", Formatters.shortDate(due))
                    Divider().padding(.leading, 14)
                }
                row("Credits", "\(status.balance)")
                if let name = status.businessName {
                    Divider().padding(.leading, 14)
                    row("Registered as", name)
                }
                if let route = status.registrationRoute {
                    Divider().padding(.leading, 14)
                    row("Registration", route.title)
                }
            }
            .cardSurface()
        }
    }

    private var responsibilityCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.badge.shield.checkmark")
                .foregroundStyle(Theme.primary)
            Text("Your business is responsible for providing accurate business information, maintaining any required website or privacy information, obtaining appropriate customer consent, and complying with applicable messaging requirements.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.primaryTint.opacity(0.6))
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 28, height: 28)
                .background(Theme.primaryTint)
                .clipShape(.circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(detail).font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(Theme.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }

    private func banner(_ text: String, tone: Color, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tone)
            Text(text).font(.footnote).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func color(_ tone: StatusTone) -> Color {
        switch tone {
        case .success: return Theme.green
        case .danger: return Theme.red
        case .warning: return Theme.amber
        case .info: return Theme.primary
        case .neutral: return Theme.primary
        }
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

/// Three-step progress for carrier approval.
private struct ApprovalProgress: View {
    let status: MessagingSetupStatus

    var body: some View {
        HStack(spacing: 6) {
            stage("Number", done: status.phoneNumber != nil)
            bar
            stage("Business", done: true)
            bar
            stage("Carriers", done: false, active: true)
        }
    }

    private var bar: some View {
        Capsule().fill(Theme.border).frame(height: 3).frame(maxWidth: .infinity)
    }

    private func stage(_ title: String, done: Bool, active: Bool = false) -> some View {
        VStack(spacing: 4) {
            Image(systemName: done ? "checkmark.circle.fill" : (active ? "circle.dotted" : "circle"))
                .foregroundStyle(done ? Theme.green : Theme.amber)
                .symbolEffect(.variableColor, isActive: active)
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondary)
        }
    }
}
