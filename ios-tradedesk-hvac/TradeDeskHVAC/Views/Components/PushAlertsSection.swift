import SwiftUI

/// The notifications addressed to the signed-in person, with their real
/// delivery outcome.
///
/// Read from the same ledger that records customer SMS and email, so a status
/// means the same thing here as it does on an invoice. Nothing is presented as
/// delivered unless the provider accepted it: a queued alert says queued, and a
/// failed one shows the reason it failed.
struct PushAlertsSection: View {
    let alerts: [PushNotificationRecord]
    let onOpen: (AppRoute) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your alerts")
                .sectionLabelStyle()

            if alerts.isEmpty {
                Text("Nothing yet. Assignments, time changes and cancellations for your jobs will appear here.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(alerts.enumerated()), id: \.element.id) { index, alert in
                        if index > 0 { Divider().padding(.leading, 52) }
                        row(alert)
                    }
                }
                .cardSurface()
            }
        }
    }

    @ViewBuilder
    private func row(_ alert: PushNotificationRecord) -> some View {
        let content = HStack(alignment: .top, spacing: 12) {
            Image(systemName: alert.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tone(alert.status))
                .frame(width: 28, height: 28)
                .background(tone(alert.status).opacity(0.12))
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(alert.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(alert.body)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(alert.statusTitle.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(tone(alert.status))
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(Theme.meta)
                    Text(Formatters.shortDayAndTime(alert.sentAt ?? alert.createdAt))
                        .font(.caption2)
                        .foregroundStyle(Theme.meta)
                }

                if let reason = alert.failureReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if alert.route != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.meta)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)

        if let route = alert.route {
            Button { onOpen(route) } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func tone(_ status: NotificationStatus) -> Color {
        switch status {
        case .queued: return Theme.amber
        case .sent: return Theme.primary
        case .delivered: return Theme.green
        case .failed: return Theme.red
        }
    }
}
