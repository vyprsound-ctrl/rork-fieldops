import SwiftUI

/// Set Up SMS: business type → business details → choose number → review.
/// With `onlyChooseNumber`, just picks a replacement for a number that was taken.
struct SmsSetupFlowView: View {
    var onlyChooseNumber: Bool = false
    let onFinished: (SmsSetupResult) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var flow = SmsSetupFlowViewModel()

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !onlyChooseNumber { stepper }
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch onlyChooseNumber ? .number : flow.step {
                        case .route: routeStep
                        case .details: detailsStep
                        case .number: numberStep
                        case .review: reviewStep
                        }
                        if let error = flow.error {
                            Label(error, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(Theme.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("sms.setup.error")
                        }
                    }
                    .padding(Theme.margin)
                    .animation(.snappy, value: flow.step)
                }
                footer
            }
            .background(Theme.canvas)
            .navigationTitle(onlyChooseNumber ? "Choose a number" : "Set Up SMS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .interactiveDismissDisabled(flow.isSubmitting)
    }

    // MARK: Stepper

    private var stepper: some View {
        HStack(spacing: 6) {
            ForEach(SmsSetupFlowViewModel.Step.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= flow.step.rawValue ? Theme.accent : Theme.border)
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 8)
        .animation(.snappy, value: flow.step)
    }

    // MARK: Steps

    private var routeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("What kind of business are you?", "This decides how carriers register your business. You can't text customers until they approve it.")
            ForEach(SmsRegistrationRoute.allCases) { route in
                Button {
                    flow.details.route = route
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: flow.details.route == route ? "largecircle.fill.circle" : "circle")
                            .font(.title3)
                            .foregroundStyle(flow.details.route == route ? Theme.accent : Theme.meta)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(route.title).font(.headline).foregroundStyle(Theme.ink)
                            Text(route.detail).font(.footnote).foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(flow.details.route == route ? Theme.accentTint : Theme.surface)
                    .clipShape(.rect(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .stroke(flow.details.route == route ? Theme.accent.opacity(0.5) : Theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: flow.details.route)
            }
        }
    }

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Your business details", "Use your real details exactly as registered. Carriers check them.")
            group("Business") {
                field("Legal business name", text: $flow.details.legalName, id: "legalName")
                if flow.details.route.needsEIN {
                    Picker("Company structure", selection: $flow.details.structure) {
                        ForEach(SmsBusinessStructure.allCases) { Text($0.title).tag($0) }
                    }
                    .padding(.horizontal, 12).frame(minHeight: 48)
                    Divider()
                    field("EIN (12-3456789)", text: $flow.details.ein, keyboard: .numbersAndPunctuation, id: "ein")
                    field("Website (https://…)", text: $flow.details.website, keyboard: .URL, id: "website")
                } else {
                    field("Website (optional)", text: $flow.details.website, keyboard: .URL, id: "website")
                }
            }
            group("Business address") {
                field("Street", text: $flow.details.street, id: "street")
                field("Suite / unit (optional)", text: $flow.details.street2, id: "street2")
                field("City", text: $flow.details.city, id: "city")
                HStack(spacing: 0) {
                    field("State (FL)", text: $flow.details.state, id: "state")
                    Divider()
                    field("ZIP", text: $flow.details.postalCode, keyboard: .numberPad, id: "zip")
                }
            }
            group("Authorized representative") {
                field("First name", text: $flow.details.repFirstName, id: "repFirst")
                field("Last name", text: $flow.details.repLastName, id: "repLast")
                field("Title (e.g. Owner)", text: $flow.details.repTitle, id: "repTitle")
                field("Email", text: $flow.details.repEmail, keyboard: .emailAddress, id: "repEmail")
                field("Phone", text: $flow.details.repPhone, keyboard: .phonePad, id: "repPhone")
                if flow.details.route == .soleProprietor {
                    field("Your mobile (gets a one-time text)", text: $flow.details.mobilePhone, keyboard: .phonePad, id: "mobile")
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("How customers agree to texts").sectionLabelStyle()
                TextEditor(text: $flow.details.optInDescription)
                    .frame(minHeight: 110)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Theme.surface)
                    .clipShape(.rect(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))
                    .accessibilityIdentifier("sms.setup.optIn")
                Button("Use a suggestion") {
                    flow.details.optInDescription = "Customers give their mobile number when they book a job with us by phone, in person or online, and agree to receive texts about their appointments, job updates, quotes and invoices. They can reply STOP at any time to opt out."
                }
                .font(.caption.weight(.semibold))
                Text("Edit the suggestion so it matches exactly how your customers agree.")
                    .font(.caption).foregroundStyle(Theme.meta)
            }
        }
    }

    private var numberStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("Choose your number", "Pick a local number your customers will recognise.")
            HStack(spacing: 10) {
                TextField("Area code", text: $flow.areaCode)
                    .keyboardType(.numberPad)
                    .font(.title3.monospacedDigit())
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(Theme.surface)
                    .clipShape(.rect(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))
                    .accessibilityIdentifier("sms.setup.areaCode")
                Button {
                    guard let session else { return }
                    Task { await flow.search(gateway: env.gateway, session: session) }
                } label: {
                    Group {
                        if flow.isSearching { ProgressView().tint(.white) } else { Text("Search").font(.headline) }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 100, height: 50)
                    .background(Theme.primary)
                    .clipShape(.rect(cornerRadius: Theme.cardRadius))
                }
                .disabled(flow.isSearching)
            }
            if !flow.numbers.isEmpty {
                VStack(spacing: 0) {
                    ForEach(flow.numbers) { number in
                        Button { flow.selectedNumber = number } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(number.pretty).font(.headline.monospacedDigit()).foregroundStyle(Theme.ink)
                                    if !number.place.isEmpty {
                                        Text(number.place).font(.caption).foregroundStyle(Theme.meta)
                                    }
                                }
                                Spacer()
                                Image(systemName: flow.selectedNumber == number ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(flow.selectedNumber == number ? Theme.accent : Theme.border)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 56)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if number != flow.numbers.last { Divider().padding(.leading, 14) }
                    }
                }
                .cardSurface()
                .sensoryFeedback(.selection, trigger: flow.selectedNumber)
            }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            header("Review and submit", "We'll create your number and send your details for carrier approval.")
            VStack(spacing: 0) {
                reviewRow("Business", flow.details.legalName)
                Divider().padding(.leading, 14)
                reviewRow("Type", flow.details.route.title)
                Divider().padding(.leading, 14)
                reviewRow("Number", flow.selectedNumber?.pretty ?? "—")
                Divider().padding(.leading, 14)
                reviewRow("Setup fee", "$0")
                Divider().padding(.leading, 14)
                reviewRow("Number fee", "$2.99/month from SMS credits")
                Divider().padding(.leading, 14)
                reviewRow("Texts", "1 credit per segment")
            }
            .cardSurface()

            Toggle(isOn: $flow.details.acceptedResponsibility) {
                Text("I confirm these details are accurate. My business is responsible for providing accurate business information, maintaining any required website or privacy information, obtaining appropriate customer consent, and complying with applicable messaging requirements. I've read the SMS & Messaging Terms.")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("sms.setup.accept")

            LegalLinksView(documents: [.smsTerms, .privacyPolicy])
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if !onlyChooseNumber, flow.step != .route {
                Button("Back") {
                    flow.error = nil
                    if let previous = SmsSetupFlowViewModel.Step(rawValue: flow.step.rawValue - 1) { flow.step = previous }
                }
                .font(.headline)
                .frame(width: 90, height: 52)
                .background(Theme.primaryTint)
                .clipShape(.rect(cornerRadius: Theme.buttonRadius))
            }
            Button { advance() } label: {
                Group {
                    if flow.isSubmitting { ProgressView().tint(.white) } else { Text(primaryTitle).font(.headline) }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.accent.gradient)
                .clipShape(.rect(cornerRadius: Theme.buttonRadius))
            }
            .disabled(flow.isSubmitting)
            .accessibilityIdentifier("sms.setup.next")
        }
        .padding(Theme.margin)
        .background(.bar)
    }

    private var primaryTitle: String {
        if onlyChooseNumber { return "Use this number" }
        return flow.step == .review ? "Submit" : "Continue"
    }

    private func advance() {
        flow.error = nil
        guard let session else { return }
        if onlyChooseNumber {
            Task {
                if let result = await flow.choose(gateway: env.gateway, session: session) {
                    onFinished(result)
                    dismiss()
                }
            }
            return
        }
        switch flow.step {
        case .route: flow.step = .details
        case .details:
            var check = flow.details
            check.acceptedResponsibility = true
            if let problem = check.problem { flow.error = problem } else { flow.step = .number }
        case .number:
            if flow.selectedNumber == nil { flow.error = "Choose a number to continue." } else { flow.step = .review }
        case .review:
            Task {
                if await flow.submit(gateway: env.gateway, session: session), let result = flow.result {
                    onFinished(result)
                    dismiss()
                }
            }
        }
    }

    // MARK: Pieces

    private func header(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
            Text(detail).font(.subheadline).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).sectionLabelStyle()
            VStack(spacing: 0) { content() }.cardSurface()
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default, id: String) -> some View {
        VStack(spacing: 0) {
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .default ? .words : .never)
                .autocorrectionDisabled(keyboard != .default)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .accessibilityIdentifier("sms.setup.\(id)")
            Divider()
        }
    }

    private func reviewRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(Theme.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }
}
