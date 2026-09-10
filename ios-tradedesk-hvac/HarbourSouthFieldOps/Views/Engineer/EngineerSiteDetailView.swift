import SwiftUI

/// One site: how to get in, who to ask for, what's installed, and what has
/// happened here before.
///
/// This is the screen that answers "what am I walking into". It carries no
/// price, balance, payment term or invoice reference — the payload type has no
/// such field, so there is nothing to strip.
struct EngineerSiteDetailView: View {
    let addressID: String

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = EngineerSiteDetailViewModel()
    @State private var navigationHandoff: NavigationHandoff?

    private var session: TenantSession? { env.activeSession }
    private var terms: Terminology { env.terms }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle(viewModel.state.value?.customerName ?? "Site")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: addressID) { await reload() }
        .sheet(item: $navigationHandoff) { handoff in
            NavigationHandoffSheet(handoff: handoff, estimate: nil)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading the site")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let site):
            loaded(site)
        }
    }

    private func loaded(_ site: EngineerSiteDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                addressCard(site)
                if !site.contacts.isEmpty { contactsCard(site) }
                equipmentSection(site)
                if !site.openVisits.isEmpty {
                    visitsSection(title: "Open work here", visits: site.openVisits)
                }
                visitsSection(title: "Service history", visits: site.pastVisits)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .refreshable { await reload(showLoading: false) }
    }

    // MARK: - Cards

    private func addressCard(_ site: EngineerSiteDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                icon("mappin.and.ellipse")
                VStack(alignment: .leading, spacing: 3) {
                    Text(site.addressLine)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(site.typeTitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }

            if let access = site.accessNotes {
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    icon("key")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Getting in")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondary)
                        Text(access)
                            .font(.subheadline)
                            .foregroundStyle(Theme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            if let notes = site.siteNotes {
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    icon("note.text")
                    Text(notes)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }

            Button {
                navigate(site)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                    Text("Navigate")
                }
                .font(.headline)
                .foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                .background(Theme.primaryTint)
                .clipShape(.rect(cornerRadius: Theme.buttonRadius))
            }
            .buttonStyle(PressableTileStyle())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func contactsCard(_ site: EngineerSiteDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who to ask for")
                .sectionLabelStyle()

            VStack(spacing: 0) {
                ForEach(Array(site.contacts.enumerated()), id: \.element.id) { index, contact in
                    HStack(spacing: 12) {
                        icon("person.crop.circle")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.ink)
                            if let role = contact.roleTitle {
                                Text(role)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if let phone = contact.phone,
                           let url = URL(string: "tel://\(phone.filter(\.isNumber))") {
                            Link(destination: url) {
                                Text("Call")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Theme.primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Theme.primaryTint)
                                    .clipShape(.capsule)
                            }
                            .accessibilityLabel("Call \(contact.name)")
                        }
                    }
                    .padding(14)

                    if index < site.contacts.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .cardSurface()
        }
    }

    // MARK: - Equipment

    private func equipmentSection(_ site: EngineerSiteDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(terms.AssetPlural) here")
                .sectionLabelStyle()

            if site.equipment.isEmpty {
                Text("No \(terms.assetPlural) recorded at this site yet.")
                    .font(.footnote)
                    .foregroundStyle(Theme.meta)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
            } else {
                ForEach(site.equipment) { unit in
                    equipmentCard(unit)
                }
            }
        }
    }

    /// One unit and everything that has been done to it.
    ///
    /// The history is the whole point for an HVAC call-out: knowing this
    /// compressor was replaced eight months ago changes what you check first.
    private func equipmentCard(_ unit: EquipmentProjection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 44, height: 44)
                    .background(Theme.primaryTint)
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(unit.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(unit.subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !unit.serialNumber.isEmpty {
                        Text("Serial \(unit.serialNumber)")
                            .font(.caption2)
                            .foregroundStyle(Theme.meta)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 0)
            }

            if let warranty = unit.warrantyLabel {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal")
                        .font(.caption2)
                    Text(warranty)
                        .font(.caption)
                }
                .foregroundStyle(warranty.hasPrefix("Warranty expired") ? Theme.meta : Theme.green)
            }

            if !unit.attributes.isEmpty {
                FlowingTags(tags: unit.attributes)
            }

            Divider()

            if unit.history.isEmpty {
                Text("No service history recorded on this \(terms.asset) yet.")
                    .font(.footnote)
                    .foregroundStyle(Theme.meta)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Previous work")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondary)

                    ForEach(unit.history) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "wrench.adjustable")
                                .font(.caption2)
                                .foregroundStyle(Theme.primary)
                                .frame(width: 24, height: 24)
                                .background(Theme.primaryTint)
                                .clipShape(.circle)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.dateLabel)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.meta)
                                Text(entry.summary)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - Visits

    private func visitsSection(title: String, visits: [EngineerVisitRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .sectionLabelStyle()

            VStack(spacing: 0) {
                if visits.isEmpty {
                    Text("Nothing recorded yet.")
                        .font(.footnote)
                        .foregroundStyle(Theme.meta)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else {
                    ForEach(Array(visits.enumerated()), id: \.element.id) { index, visit in
                        NavigationLink(value: FieldJobRoute(jobID: visit.id)) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(visit.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.ink)
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text(visit.dateLabel)
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondary)
                                        Text("· \(visit.number)")
                                            .font(.caption)
                                            .foregroundStyle(Theme.meta)
                                        Text("· \(visit.kindTitle)")
                                            .font(.caption)
                                            .foregroundStyle(Theme.meta)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                StatusPill(badge: visit.badge)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.meta)
                            }
                            .padding(14)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)

                        if index < visits.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
            .cardSurface()
        }
    }

    // MARK: - Helpers

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.footnote)
            .foregroundStyle(Theme.primary)
            .frame(width: 32, height: 32)
            .background(Theme.primaryTint)
            .clipShape(.circle)
    }

    private func navigate(_ site: EngineerSiteDetail) {
        let destination = Coordinate(latitude: site.latitude, longitude: site.longitude)
        navigationHandoff = env.maps.prepareNavigation(
            to: destination,
            label: site.customerName,
            addressLine: site.addressLine
        )
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(
            gateway: env.gateway,
            session: session,
            addressID: addressID,
            showLoading: showLoading
        )
    }
}

/// Wrapping row of small tags. `HStack` would clip a unit with five recorded
/// attributes; a fixed grid would leave gaps on one with two.
struct FlowingTags: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.canvas)
                    .clipShape(.capsule)
            }
        }
    }
}

#Preview {
    NavigationStack {
        EngineerSiteDetailView(addressID: "addr_1")
            .environment(AppEnvironment())
    }
}
