import SwiftUI

/// ISSUE #5 — raising an invoice that belongs to no job and no quote.
///
/// The database has always allowed this: `invoices.job_id` is nullable and
/// `create_invoice` takes a customer and an address, never a job. Only the UI
/// insisted on a source document, which forced the office to invent a fake job
/// to bill a supply-only sale, a call-out fee or a deposit.
///
/// Customer is required because an invoice with nobody to send it to is not an
/// invoice. Site is optional and defaults to the customer's main site.
struct StandaloneInvoiceForm: View {
    @Binding var isWorking: Bool
    @Binding var errorMessage: String?
    let onCreated: (String) -> Void

    @Environment(AppEnvironment.self) private var env

    @State private var customers: [CustomerRow] = []
    @State private var isLoadingCustomers: Bool = true
    @State private var loadError: DataError?
    @State private var selectedCustomer: CustomerRow?
    @State private var addresses: [CustomerAddressProjection] = []
    @State private var selectedAddressID: String?
    @State private var title: String = ""
    @State private var scopeOfWork: String = ""

    private var session: TenantSession? { env.activeSession }

    private var validationMessage: String? {
        if selectedCustomer == nil { return "Choose the customer this invoice is for." }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Give the invoice a description."
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Bill a customer directly. Use this for a supply-only sale, a call-out fee or anything that never needed a scheduled job.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)

                customerSection

                if selectedCustomer != nil {
                    if addresses.count > 1 { siteSection }
                    detailSection
                    createButton
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 28)
        }
        .task { await loadCustomers() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var customerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Customer").sectionLabelStyle()

            if isLoadingCustomers {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Loading customers").font(.footnote).foregroundStyle(Theme.meta)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                .cardSurface()
            } else if let loadError {
                Text(loadError.errorDescription ?? "Couldn't load customers.")
                    .font(.footnote)
                    .foregroundStyle(Theme.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .cardSurface()
            } else if customers.isEmpty {
                Text("Add a customer before raising an invoice.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .cardSurface()
            } else {
                Menu {
                    ForEach(customers) { customer in
                        Button {
                            Task { await select(customer) }
                        } label: {
                            Text(customer.name)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(selectedCustomer?.name ?? "Choose a customer")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedCustomer == nil ? Theme.meta : Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                    .cardSurface()
                }
                .disabled(isWorking)
            }
        }
    }

    @ViewBuilder
    private var siteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Site").sectionLabelStyle()
            Menu {
                ForEach(addresses) { address in
                    Button {
                        selectedAddressID = address.id
                    } label: {
                        Text("\(address.line1), \(address.city)")
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(selectedAddressLabel)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                .cardSurface()
            }
            .disabled(isWorking)
        }
    }

    private var selectedAddressLabel: String {
        guard let match = addresses.first(where: { $0.id == selectedAddressID }) else {
            return "Main site"
        }
        return "\(match.line1), \(match.city)"
    }

    @ViewBuilder
    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details").sectionLabelStyle()

            VStack(spacing: 0) {
                TextField("What is this invoice for?", text: $title)
                    .font(.subheadline)
                    .padding(.horizontal, 14)
                    .frame(minHeight: Theme.minTap)

                Divider().padding(.leading, 14)

                TextField("Notes for the customer (optional)", text: $scopeOfWork, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(3...6)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
            }
            .cardSurface()

            Text("Line items and pricing are added on the invoice itself once it exists.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
        }
    }

    @ViewBuilder
    private var createButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await create() }
            } label: {
                BrandButtonLabel(
                    title: "Create invoice",
                    role: .accent,
                    isEnabled: validationMessage == nil && !isWorking,
                    isWorking: isWorking
                )
            }
            .disabled(validationMessage != nil || isWorking)

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Work

    private func loadCustomers() async {
        guard let session else { return }
        isLoadingCustomers = true
        loadError = nil
        do {
            customers = try await env.gateway.customers(session: session, query: "")
        } catch {
            loadError = DataError.wrap(error)
        }
        isLoadingCustomers = false
    }

    /// Loading the profile is what supplies the site list. A failure here is not
    /// fatal — the invoice can still be raised against the customer's main site,
    /// which is exactly what a nil address id means to `create_invoice`.
    private func select(_ customer: CustomerRow) async {
        guard let session else { return }
        selectedCustomer = customer
        addresses = []
        selectedAddressID = nil
        if let profile = try? await env.gateway.customerProfile(session: session, customerID: customer.id) {
            addresses = profile.addresses
            selectedAddressID = profile.addresses.first(where: \.isPrimarySite)?.id
                ?? profile.addresses.first?.id
        }
    }

    private func create() async {
        guard let session, let customer = selectedCustomer else { return }
        isWorking = true
        errorMessage = nil
        do {
            let input = NewInvoiceInput(
                customerID: customer.id,
                addressID: selectedAddressID,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                scopeOfWork: scopeOfWork.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let invoiceID = try await env.gateway.createInvoice(session: session, input: input)
            isWorking = false
            onCreated(invoiceID)
        } catch {
            errorMessage = DataError.wrap(error).errorDescription
            isWorking = false
        }
    }
}
