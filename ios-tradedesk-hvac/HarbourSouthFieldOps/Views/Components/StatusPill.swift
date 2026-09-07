import SwiftUI

struct StatusPill: View {
    let badge: StatusBadge

    private var color: Color {
        switch badge.tone {
        case .neutral: return Theme.meta
        case .info: return Theme.primary
        case .warning: return Theme.amber
        case .success: return Theme.green
        case .danger: return Theme.red
        }
    }

    var body: some View {
        Text(badge.text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(.rect(cornerRadius: 6))
            .accessibilityLabel("Status: \(badge.text)")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        StatusPill(badge: StatusBadge(text: "En route", tone: .warning))
        StatusPill(badge: StatusBadge(text: "Scheduled", tone: .info))
        StatusPill(badge: StatusBadge(text: "Urgent", tone: .danger))
        StatusPill(badge: StatusBadge(text: "Completed", tone: .success))
    }
    .padding()
    .background(Theme.canvas)
}
