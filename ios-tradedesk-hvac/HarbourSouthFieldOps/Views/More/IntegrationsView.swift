import SwiftUI

/// Every integration surface with its honest current state, so simulated
/// behaviour is never mistaken for a production integration.
struct IntegrationsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing here is live")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text("This build runs on local simulations so the architecture can be exercised end to end. No payment is taken, no message is delivered, and no location is tracked.")
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

    private func row(_ integration: IntegrationStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(integration.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 4)
                if integration.mode.isSimulated {
                    SimulatedBadge()
                } else {
                    StatusPill(badge: StatusBadge(text: "Live", tone: .success))
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
