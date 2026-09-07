import SwiftUI
import UIKit

/// Asks for notification permission at a moment where the reason is obvious.
///
/// The system prompt can only be shown once per install, so it is spent
/// deliberately: this card explains what the alerts are for, and the dialog
/// only appears after the person taps. Nothing here runs on launch, and nothing
/// asks on behalf of a user who has not signed in.
///
/// Every state is honest. A refusal is not re-asked (iOS would not show the
/// dialog again anyway) — it offers Settings, which is the only thing that
/// actually works. A restriction offers nothing, because the person cannot
/// change it themselves.
struct PushPermissionCard: View {
    let state: PushAuthorizationState
    let isRegistered: Bool
    let isWorking: Bool
    let detail: String?
    let worker: String
    let onEnable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tone)
                    .frame(width: 38, height: 38)
                    .background(tone.opacity(0.12))
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(headline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)

                    Text(detail ?? state.explanation(worker: worker))
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if let action {
                Button(action: action.handler) {
                    HStack(spacing: 8) {
                        if isWorking {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Theme.surface)
                        }
                        Text(action.title)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.minTap)
                    .background(tone)
                    .foregroundStyle(Theme.surface)
                    .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                }
                .buttonStyle(PressableTileStyle())
                .disabled(isWorking)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.opacity(0.08))
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(tone.opacity(0.25), lineWidth: 1)
        }
    }

    private struct CardAction {
        let title: String
        let handler: () -> Void
    }

    private var action: CardAction? {
        switch state {
        case .notDetermined:
            return CardAction(title: "Turn on job alerts", handler: onEnable)
        case .denied:
            return CardAction(title: "Turn on in Settings", handler: openSettings)
        case .provisional:
            return CardAction(title: "Allow sounds in Settings", handler: openSettings)
        case .authorized:
            // Permission exists but the device never completed registration —
            // the one case where trying again is genuinely useful.
            return isRegistered ? nil : CardAction(title: "Try again", handler: onEnable)
        case .restricted:
            return nil
        }
    }

    private var headline: String {
        switch state {
        case .notDetermined: return "Know the moment a job changes"
        case .authorized: return isRegistered ? "Job alerts are on" : "Job alerts aren't set up yet"
        case .provisional: return "Alerts arrive quietly"
        case .denied: return "Job alerts are off"
        case .restricted: return "Job alerts are blocked on this device"
        }
    }

    private var symbolName: String {
        switch state {
        case .notDetermined: return "bell.badge"
        case .authorized: return isRegistered ? "bell.fill" : "bell.slash"
        case .provisional: return "bell.badge.slash"
        case .denied: return "bell.slash.fill"
        case .restricted: return "lock.fill"
        }
    }

    private var tone: Color {
        switch state {
        case .authorized: return isRegistered ? Theme.green : Theme.amber
        case .notDetermined: return Theme.primary
        case .provisional: return Theme.amber
        case .denied, .restricted: return Theme.amber
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    VStack(spacing: 12) {
        PushPermissionCard(state: .notDetermined, isRegistered: false, isWorking: false, detail: nil, worker: "engineer") {}
        PushPermissionCard(state: .authorized, isRegistered: true, isWorking: false, detail: nil, worker: "engineer") {}
        PushPermissionCard(state: .denied, isRegistered: false, isWorking: false, detail: nil, worker: "engineer") {}
        PushPermissionCard(state: .restricted, isRegistered: false, isWorking: false, detail: nil, worker: "engineer") {}
    }
    .padding()
    .background(Theme.canvas)
}
