import SwiftUI

/// Every integration surface with its honest current state, so simulated
/// behaviour is never mistaken for a production integration.
struct IntegrationsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(headline)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Integration surfaces")
                        .sectionLabelStyle()

                    VStack(spacing: 0) {
                        ForEach(Array(IntegrationRegistry.all.enumerated()), id: \.element.id) { index, integration in
                            row(integration)
                            if index < IntegrationRegistry.all.count - 1 {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .cardSurface()
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    /// The header used to say "Nothing here is live" unconditionally. In a
    /// build with a configured database that is simply false — sign-in, the
    /// database, location, routing, maps and recurring generation are all real
    /// — so it now describes the actual mix.
    private var headline: String {
        if IntegrationRegistry.notLiveCount == 0 { return "Everything is live" }
        if SupabaseClientProvider.isConfigured { return "Mostly live" }
        return "Nothing here is live"
    }

    private var summary: String {
        guard SupabaseClientProvider.isConfigured else {
            return "This build has no database configured, so it runs on local simulations. "
                + "No payment is taken, no message is delivered and no location is tracked."
        }

        let waiting = IntegrationRegistry.needingConfiguration.map(\.name)
        guard waiting.isEmpty == false else {
            return "Every capability below is backed by its real integration."
        }

        return "Most capabilities run against their real integration. "
            + "\(ListFormatter.localizedString(byJoining: waiting)) "
            + (waiting.count == 1 ? "is" : "are")
            + " implemented but still waiting on an external account, so "
            + (waiting.count == 1 ? "it fails" : "they fail")
            + " honestly rather than reporting a success that never happened."
    }

    private func row(_ integration: IntegrationStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(integration.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 4)
                switch integration.mode {
                case .simulated:
                    SimulatedBadge()
                case .needsConfiguration:
                    StatusPill(badge: StatusBadge(text: integration.mode.label, tone: .warning))
                case .production:
                    StatusPill(badge: StatusBadge(text: integration.mode.label, tone: .success))
                }
            }
            Text(integration.detail)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Planned: \(integration.plannedProvider)")
                .font(.caption)
                .foregroundStyle(Theme.meta)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        IntegrationsView()
    }
}
