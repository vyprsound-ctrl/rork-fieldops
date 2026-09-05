import SwiftUI

/// Attached wherever a simulated service drives what the user sees, so
/// development behaviour is never mistaken for a live integration.
struct SimulatedBadge: View {
    var text: String = "Simulated"

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Theme.amber)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Theme.amber.opacity(0.12))
        .clipShape(.rect(cornerRadius: 5))
        .accessibilityLabel("\(text) — development data, not a live integration")
    }
}

/// Full-width banner used at the top of shells while any service is mocked.
struct SimulatedServicesBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.caption)
            Text("Development build · \(IntegrationRegistry.simulatedCount) services simulated")
                .font(.caption.weight(.medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.amber)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amber.opacity(0.1))
        .clipShape(.rect(cornerRadius: 10))
    }
}

#Preview {
    VStack(spacing: 12) {
        SimulatedBadge()
        SimulatedServicesBanner()
    }
    .padding()
    .background(Theme.canvas)
}
