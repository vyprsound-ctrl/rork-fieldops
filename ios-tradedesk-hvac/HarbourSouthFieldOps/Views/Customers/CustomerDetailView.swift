import SwiftUI

/// The customer record: who they are, where their sites are, what's installed
/// there and everything that has ever been done for them.
///
/// Role decides what appears. A dispatcher sees the operational account and no
/// money; accounts see the documents; a field worker never reaches this screen
/// at all, because the directory is not part of their shell.
struct CustomerDetailView: View {
    let customerID: String

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = CustomerDetailViewModel()

    @State private var editingCustomer: CustomerProfile?
    @State private var editingAddress: AddressDraft?
    @State private var editingContact: ContactDraft?
    @State private var editingEquipment: EquipmentDraft?
    @State private var isConfirmingDelete: Bool = false
    @State private var isMessaging: Bool = false

    private var session: TenantSession? { env.activeSession }
    private var terms: Terminology { env.terms }

    /// Messaging needs the permission *and* somebody to message. Offering the
    /// button to a customer with no phone number on file would be a dead end.
    private var canMessage: Bool {
        guard session?.can(.smsCreditsConsume) == true else { return false }
        guard let profile = viewModel.state.value else { return false }
        return profile.contacts.contains { ($0.phone?.tidied.isEmpty == false) }
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle("Customer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            // Messaging is its own action rather than a menu item: texting the
            // customer is a frequent, one-tap job for the office, and burying it
            // under an ellipsis makes it a chore.
            if canMessage {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isMessaging = true
                    } label: {
                        Image(systemName: "message")
                    }
                    .accessibilityLabel("Send a message")
                }
            }

            if let profile = viewModel.state.value, profile.canManage {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            editingCustomer = profile
                        } label: {
                            Label("Edit customer", systemImage: "pencil")
                        }
                        Button {
                            editingAddress = AddressDraft()
                        } label: {
                            Label("Add service address", systemImage: "mappin.and.ellipse")
                        }
                        Button {
                            editingContact = ContactDraft()
                        } label: {
                            Label("Add contact", systemImage: "person.badge.plus")
                        }
                        if profile.canManageEquipment, !profile.addresses.isEmpty {
                            Button {
                                editingEquipment = EquipmentDraft(addressID: profile.addresses[0].id)
                            } label: {
                                Label("Add \(terms.asset)", systemImage: "shippingbox")
                            }
                        }
                        if profile.canDelete {
                            Divider()
                            Button(role: .destructive) {
                                isConfirmingDelete = true
                            } label: {
                                Label("Delete customer", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Customer actions")
                }
            }
        }
        .task(id: customerID) { await reload() }
        .onChange(of: viewModel.isDeleted) { _, deleted in
            if deleted { dismiss() }
        }
        .sheet(isPresented: $isMessaging) {
            SendSmsSheet(
                customerID: customerID,
                customerName: viewModel.state.value?.name ?? "this customer",
                context: .customer
            )
        }
        .sheet(item: $editingCustomer) { profile in
            CustomerEditorView(existing: profile) { _ in
                Task { await reload(showLoading: false) }
            }
        }
        .sheet(item: $editingAddress) { draft in
            AddressEditorView(draft: draft) { updated in
                guard let session else { return }
                Task {
                    await viewModel.saveAddress(
                        gateway: env.gateway,
                        session: session,
                        customerID: customerID,
                        draft: updated
                    )
                }
            }
        }
        .sheet(item: $editingContact) { draft in
            ContactEditorView(draft: draft) { updated in
                guard let session else { return }
                Task {
                    await viewModel.saveContact(
                        gateway: env.gateway,
                        session: session,
                        customerID: customerID,
                        draft: updated
                    )
                }
            }
        }
        .sheet(item: $editingEquipment) { draft in
            if let profile = viewModel.state.value {
                EquipmentEditorView(draft: draft, addresses: profile.addresses, assetTerm: terms.asset) { updated in
                    guard let session else { return }
                    Task {
                        await viewModel.saveEquipment(
                            gateway: env.gateway,
                            session: session,
                            customerID: customerID,
                            draft: updated
                        )
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this customer?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete customer", role: .destructive) {
                guard let session else { return }
                Task { await viewModel.delete(gateway: env.gateway, session: session, customerID: customerID) }
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("Their sites, contacts and \(terms.assetPlural) go with them. This can't be undone.")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading customer")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let profile):
            loaded(profile)
        }
    }

    private func loaded(_ profile: CustomerProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(profile)
                if let error = viewModel.actionError { errorBanner(error) }
                accountCard(profile)
                if let notes = profile.notes { notesCard(notes) }
                contactsSection(profile)
                sitesSection(profile)
                equipmentSection(profile)
                jobsSection(profile)
                CommunicationHistorySection(
                    title: "Communications",
                    customerID: customerID,
                    customerName: profile.name,
                    context: .customer,
                    quickActions: [.customerFollowUp],
                    hasPhone: profile.contacts.contains { ($0.phone?.tidied.isEmpty == false) }
                )
                if !profile.quotes.isEmpty {
                    documentsSection(title: "Quotes", documents: profile.quotes, kind: .quote)
                }
                if !profile.invoices.isEmpty {
                    documentsSection(title: "Invoices", documents: profile.invoices, kind: .invoice)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .refreshable { await reload(showLoading: false) }
    }

    private func header(_ profile: CustomerProfile) -> some View {
        HStack(spacing: 12) {
            Text(profile.initials)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 56, height: 56)
                .background(Theme.primaryTint)
                .clipShape(.circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(profile.typeTitle) · \(profile.createdLabel)")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private func accountCard(_ profile: CustomerProfile) -> some View {
        VStack(spacing: 0) {
            infoRow(symbol: "creditcard", title: "Billing terms", value: profile.billingTerms)
            if let outstanding = profile.outstandingLabel {
                Divider().padding(.leading, 54)
                infoRow(symbol: "banknote", title: "Outstanding", value: outstanding, valueTone: Theme.red)
            }
            Divider().padding(.leading, 54)
            infoRow(symbol: "briefcase", title: "Open jobs", value: "\(profile.openJobs.count)")
        }
        .cardSurface()
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes").sectionLabelStyle()
            Text(notes)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
        }
    }

    private func contactsSection(_ profile: CustomerProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Contacts").sectionLabelStyle()
                if profile.canManage {
                    Button("Add") { editingContact = ContactDraft() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                }
            }

            VStack(spacing: 0) {
                if profile.contacts.isEmpty {
                    emptyRow("Nobody on file yet.")
                } else {
                    ForEach(Array(profile.contacts.enumerated()), id: \.element.id) { index, contact in
                        if index > 0 { Divider().padding(.leading, 58) }
                        contactRow(contact, canManage: profile.canManage)
                    }
                }
            }
            .cardSurface()
        }
    }

    private func contactRow(_ contact: CustomerContactProjection, canManage: Bool) -> some View {
        HStack(spacing: 12) {
            Text(contact.initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 36, height: 36)
                .background(Theme.primaryTint)
                .clipShape(.circle)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(contact.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    if contact.isPrimary {
                        Text("Main")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.primaryTint)
                            .clipShape(.rect(cornerRadius: 5))
                    }
                }
                Text([contact.roleTitle, contact.phone, contact.email].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            if let phone = contact.phone, let url = URL(string: "tel://\(phone.filter(\.isNumber))") {
                Link(destination: url) {
                    Image(systemName: "phone.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.primary)
                        .frame(width: 40, height: 40)
                        .background(Theme.primaryTint)
                        .clipShape(.circle)
                }
            }

            if canManage {
                Button {
                    editingContact = ContactDraft(
                        id: contact.id,
                        name: contact.name,
                        contactRole: contact.roleTitle ?? "",
                        phone: contact.phone ?? "",
                        email: contact.email ?? "",
                        isPrimary: contact.isPrimary,
                        isBillingContact: contact.isBillingContact
                    )
                } label: {
                    Image(systemName: "pencil")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 36, height: 40)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(contact.name)")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: Theme.minTap)
    }

    private func sitesSection(_ profile: CustomerProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Service addresses").sectionLabelStyle()
                if profile.canManage {
                    Button("Add") { editingAddress = AddressDraft() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                }
            }

            VStack(spacing: 0) {
                if profile.addresses.isEmpty {
                    emptyRow("No sites on file.")
                } else {
                    ForEach(Array(profile.addresses.enumerated()), id: \.element.id) { index, address in
                        if index > 0 { Divider().padding(.leading, 14) }
                        siteRow(address, canManage: profile.canManage)
                    }
                }
            }
            .cardSurface()
        }
    }

    private func siteRow(_ address: CustomerAddressProjection, canManage: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: address.isPrimarySite ? "mappin.circle.fill" : "mappin.circle")
                .font(.body)
                .foregroundStyle(Theme.primary)
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(address.line1)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    if address.isPrimarySite {
                        Text("Main site")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.primaryTint)
                            .clipShape(.rect(cornerRadius: 5))
                    }
                }
                Text("\(address.city) \(address.state) \(address.postalCode)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                if let access = address.accessNotes {
                    Text(access)
                        .font(.caption)
                        .foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if address.equipmentCount > 0 {
                    Text("\(address.equipmentCount) \(address.equipmentCount == 1 ? terms.asset : terms.assetPlural)")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                }
            }

            Spacer(minLength: 4)

            if canManage {
                Button {
                    editingAddress = address.draft
                } label: {
                    Image(systemName: "pencil")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 36, height: 40)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit site")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func equipmentSection(_ profile: CustomerProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(terms.AssetPlural).sectionLabelStyle()
                if profile.canManageEquipment, !profile.addresses.isEmpty {
                    Button("Add") {
                        editingEquipment = EquipmentDraft(addressID: profile.addresses[0].id)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.primary)
                }
            }

            VStack(spacing: 0) {
                if profile.equipment.isEmpty {
                    emptyRow("Nothing registered at these sites yet.")
                } else {
                    ForEach(Array(profile.equipment.enumerated()), id: \.element.id) { index, unit in
                        if index > 0 { Divider().padding(.leading, 14) }
                        equipmentRow(unit, canManage: profile.canManageEquipment)
                    }
                }
            }
            .cardSurface()
        }
    }

    private func equipmentRow(_ unit: CustomerEquipmentProjection, canManage: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.footnote)
                .foregroundStyle(unit.isActive ? Theme.primary : Theme.meta)
                .frame(width: 34, height: 34)
                .background((unit.isActive ? Theme.primary : Theme.meta).opacity(0.12))
                .clipShape(.rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(unit.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    if !unit.isActive {
                        StatusPill(badge: StatusBadge(text: "Inactive", tone: .neutral))
                    }
                }
                Text([unit.category, unit.serialNumber.nilIfBlank.map { "S/N \($0)" }, unit.installedLabel]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let warranty = unit.warrantyLabel {
                    Text(warranty)
                        .font(.caption)
                        .foregroundStyle(Theme.green)
                }
                if unit.historyCount > 0 {
                    Text("\(unit.historyCount) service record\(unit.historyCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                }
            }

            Spacer(minLength: 4)

            if canManage {
                Button {
                    editingEquipment = unit.draft
                } label: {
                    Image(systemName: "pencil")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 36, height: 40)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(unit.displayName)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func jobsSection(_ profile: CustomerProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Service history").sectionLabelStyle()

            VStack(spacing: 0) {
                let jobs = profile.openJobs + profile.closedJobs
                if jobs.isEmpty {
                    emptyRow("No jobs raised for this customer yet.")
                } else {
                    ForEach(Array(jobs.prefix(30).enumerated()), id: \.element.id) { index, job in
                        if index > 0 { Divider().padding(.leading, 14) }
                        NavigationLink(value: AppRoute.job(job.id)) {
                            jobRow(job)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .cardSurface()
        }
    }

    private func jobRow(_ job: CustomerJobProjection) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text([job.number, job.dateLabel, job.workerName].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            StatusPill(badge: job.badge)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.meta)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: Theme.minTap)
        .contentShape(.rect)
    }

    /// Which screen a document row opens.
    private enum DocumentKind {
        case quote
        case invoice

        func route(_ id: String) -> AppRoute {
            switch self {
            case .quote: return .quote(id)
            case .invoice: return .invoice(id)
            }
        }
    }

    /// ISSUE #8 — invoices in a customer's history are now actionable.
    ///
    /// THE DEFECT: these rows were plain `HStack`s. An invoice appeared in the
    /// customer's record showing a number, an amount and a status, and tapping
    /// it did nothing — so the one place an office naturally looks up "what does
    /// this customer owe us" was a dead end. Chasing a payment meant leaving the
    /// customer, opening Invoices, and searching for the number by hand.
    ///
    /// THE FIX: the row opens `InvoiceDetailView`, which already carries every
    /// action this issue asks for — view, edit, send/resend, record a payment,
    /// payment status, and the linked job or quote. No second invoice screen and
    /// no duplicated actions were built.
    ///
    /// PERMISSIONS ARE UNCHANGED: `profile.invoices` is already empty for a role
    /// without `invoicesRead` (the gateway omits it), so a field worker sees no
    /// section to tap. The destination re-checks on its own behalf, and the
    /// database refuses regardless of what the UI offers.
    private func documentsSection(
        title: String,
        documents: [CustomerDocumentProjection],
        kind: DocumentKind
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).sectionLabelStyle()
            VStack(spacing: 0) {
                ForEach(Array(documents.prefix(20).enumerated()), id: \.element.id) { index, document in
                    if index > 0 { Divider().padding(.leading, 14) }
                    NavigationLink(value: kind.route(document.id)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(document.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Text([document.number, document.dateLabel.nilIfBlank].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondary)
                            }
                            Spacer(minLength: 4)
                            if let amount = document.amountLabel {
                                Text(amount)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.ink)
                            }
                            StatusPill(badge: document.badge)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: Theme.minTap)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .cardSurface()
        }
    }

    // MARK: - Small pieces

    private func infoRow(symbol: String, title: String, value: String, valueTone: Color = Theme.ink) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(Theme.primary)
                .frame(width: 30, height: 30)
                .background(Theme.primaryTint)
                .clipShape(.circle)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(valueTone)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: Theme.minTap)
    }

    private func emptyRow(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(Theme.meta)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(Theme.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.red.opacity(0.08))
            .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, customerID: customerID, showLoading: showLoading)
    }
}

#Preview {
    NavigationStack {
        CustomerDetailView(customerID: "cus_ramirez")
            .environment(AppEnvironment())
    }
}
