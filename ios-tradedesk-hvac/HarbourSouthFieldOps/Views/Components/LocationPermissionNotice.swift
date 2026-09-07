import SwiftUI
import UIKit

/// Shown to a field worker when a job step could not record a position.
///
/// Deliberately not a blocker. The job still moved — the workflow rules decide
/// whether work can proceed, not the GPS — so this explains what was missed and
/// offers the one action that fixes it, without standing between the worker and
/// the next tap.
///
/// A restriction is treated differently from a refusal on purpose: sending
/// someone to Settings to change something a device policy controls would be
/// advice that cannot work.
struct LocationPermissionNotice: View {
    let state: LocationAuthorizationState
    let worker: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.footnote)
                .foregroundStyle(Theme.amber)
                .frame(width: 30, height: 30)
                .background(Theme.amber.opacity(0.12))
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                Text(state.explanation(worker: worker))
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if state.isResolvableInSettings {
                    Button {
                        openSettings()
                    } label: {
                        Text(state == .unavailable ? "Open Settings" : "Turn on in Settings")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amber.opacity(0.1))
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    private var headline: String {
        switch state {
        case .denied, .unavailable, .restricted: return "Step recorded without a position"
        case .notDetermined: return "Why we ask for your location"
        case .authorized: return "Location is on"
        }
    }

    private var symbolName: String {
        switch state {
        case .restricted: return "lock.fill"
        case .unavailable: return "location.slash.fill"
        default: return "location.slash"
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    VStack(spacing: 12) {
        LocationPermissionNotice(state: .denied, worker: "engineer")
        LocationPermissionNotice(state: .restricted, worker: "engineer")
        LocationPermissionNotice(state: .unavailable, worker: "engineer")
    }
    .padding()
    .background(Theme.canvas)
}
