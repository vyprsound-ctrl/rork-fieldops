import SwiftUI

/// The shared job row used on Dashboard, Jobs and Calendar so the component
/// language stays identical across the shell.
///
/// The row is built to answer the dispatcher's question without opening the
/// job: when, who for, where, what state, and who is on it.
struct JobRowView: View {
    let row: JobRow
    var showsTime: Bool = true
    var showsDay: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsTime {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.timeLabel)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(row.scheduledStart == nil ? Theme.meta : Theme.ink)
                    if showsDay {
                        Text(row.dayLabel)
                            .font(.caption2)
                            .foregroundStyle(Theme.meta)
                            .lineLimit(1)
                    }
                }
                .frame(width: 74, alignment: .leading)
            }

            Rectangle()
                .fill(row.isUrgent ? Theme.red.opacity(0.55) : Theme.border)
                .frame(width: row.isUrgent ? 2 : 1)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(row.customerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if row.isUrgent {
                        Text("Urgent")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.red.opacity(0.12))
                            .clipShape(.capsule)
                    }
                }

                Text(row.title)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)

                Text(row.addressShort)
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    StatusPill(badge: row.badge)
                    if let value = row.value {
                        Text(value)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 4)

            VStack(spacing: 6) {
                if let initials = row.workerInitials {
                    Text(initials)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 34, height: 34)
                        .background(Theme.primaryTint)
                        .clipShape(.circle)
                } else {
                    Image(systemName: "person.badge.plus")
                        .font(.caption)
                        .foregroundStyle(Theme.amber)
                        .frame(width: 34, height: 34)
                        .background(Theme.amber.opacity(0.12))
                        .clipShape(.circle)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.meta)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(minHeight: Theme.minTap)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [row.timeLabel, row.customerName, row.title, row.badge.text]
        if row.isUrgent { parts.insert("Urgent", at: 0) }
        if let worker = row.workerName { parts.append(worker) } else { parts.append("Unassigned") }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    VStack(spacing: 0) {
        JobRowView(
            row: JobRow(
                id: "1",
                number: "J-1042",
                title: "No cooling — call-out",
                timeLabel: "10:30 AM",
                dayLabel: "Today",
                scheduledStart: Date(),
                customerName: "Ana Ramirez",
                addressShort: "214 Oak St",
                badge: StatusBadge(text: "Travelling", tone: .warning),
                kindTitle: "Call-out",
                kindSymbol: "exclamationmark.bubble.fill",
                workerName: "Marcus Hale",
                workerInitials: "MH",
                isUrgent: true,
                isUnassigned: false,
                value: "$470.80"
            )
        )
        Divider().padding(.leading, 14)
        JobRowView(
            row: JobRow(
                id: "2",
                number: "J-1046",
                title: "Compressor rebuild",
                timeLabel: "No slot",
                dayLabel: "Unscheduled",
                scheduledStart: nil,
                customerName: "Whitfield Dental",
                addressShort: "907 E Columbus Dr",
                badge: StatusBadge(text: "Scheduled", tone: .info),
                kindTitle: "Call-out",
                kindSymbol: "exclamationmark.bubble.fill",
                workerName: nil,
                workerInitials: nil,
                isUrgent: true,
                isUnassigned: true,
                value: nil
            )
        )
    }
    .cardSurface()
    .padding()
    .background(Theme.canvas)
}
