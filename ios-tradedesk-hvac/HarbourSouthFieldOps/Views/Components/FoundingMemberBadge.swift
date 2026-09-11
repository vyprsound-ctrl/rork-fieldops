import SwiftUI

/// The Founding Member mark.
///
/// A commercial STATUS, deliberately never described as a discount: the copy
/// says what the status is and what sustains it, and never frames the absence
/// of a qualifying payment as a penalty.
///
/// Two sizes because it appears in two kinds of place — a compact line on the
/// owner's account card, and a full card on the billing and payments screens.
/// Rationed on purpose: it belongs on the owner's dashboard, in Settings and
/// Billing, and on the Payments screen, and nowhere else.
struct FoundingMemberBadge: View {
    enum Size {
        /// One line, for an identity card or a settings row.
        case compact
        /// A full card with the benefit spelled out.
        case full
    }

    let number: Int
    /// Whether the $0/month benefit applies this calendar month. Supplied by
    /// the server via `CommercialState` — this view never works it out.
    let isBenefitActive: Bool
    var size: Size = .full

    private var badgeTitle: String { "Founding Member #\(number)" }

    var body: some View {
        switch size {
        case .compact: compactBadge
        case .full: fullCard
        }
    }

    // MARK: - Compact

    private var compactBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "trophy.fill")
                .font(.caption2)
            Text(badgeTitle)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(Theme.accentText)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Theme.accentTint)
        .clipShape(.rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Theme.accent.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isBenefitActive
                ? "\(badgeTitle). Subscription is zero dollars a month."
                : "\(badgeTitle). Subscription applies this month."
        )
    }

    // MARK: - Full

    private var fullCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent)
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 1) {
                    Text("FOUNDING MEMBER")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.accentText)
                    Text(badgeTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                }

                Spacer(minLength: 0)

                StatusPill(badge: StatusBadge(
                    text: isBenefitActive ? "Active" : "Inactive",
                    tone: isBenefitActive ? .success : .warning
                ))
            }

            Divider()

            if isBenefitActive {
                Text("Your Harbour South subscription is $0/month while you actively process customer payments through Harbour South.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Process a customer payment through Harbour South this month to maintain your Founding Member benefit.")
                        .font(.footnote)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    // Said plainly, because the number is the part people worry
                    // about losing and it is the part that never goes.
                    Text("Your Founding Member number is yours to keep.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentTint)
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
        }
    }
}

/// The trial countdown, shown where the remaining time is worth knowing.
///
/// Informational only. Nothing in the product is gated on the trial, and this
/// view never offers to "unlock" anything — the purpose of the trial is to
/// remove friction, not to create a wall.
struct TrialStatusCard: View {
    let daysRemaining: Int
    let endsAt: Date?
    /// What happens at the end, given the model the company is on. Comes from
    /// `CommercialState.trialOutcomeMessage`.
    let outcome: String

    private var headline: String {
        switch daysRemaining {
        case 0: return "Trial ends today"
        case 1: return "1 day left in your free trial"
        default: return "\(daysRemaining) days left in your free trial"
        }
    }

    /// Blue for most of the trial; amber only in the last three days, when the
    /// remaining time is genuinely worth acting on.
    private var isUrgent: Bool { daysRemaining <= 3 }
    private var tint: Color { isUrgent ? Theme.amber : Theme.primary }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: isUrgent ? "clock.badge.exclamationmark.fill" : "clock.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.white)
                    .frame(width: 32, height: 32)
                    .background(tint)
                    .clipShape(.rect(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 1) {
                    Text(headline)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    if let endsAt {
                        Text("Full access until \(Formatters.shortDate(endsAt))")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            Text(outcome)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08))
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            FoundingMemberBadge(number: 27, isBenefitActive: true)
            FoundingMemberBadge(number: 27, isBenefitActive: false)
            FoundingMemberBadge(number: 27, isBenefitActive: true, size: .compact)
            TrialStatusCard(
                daysRemaining: 11,
                endsAt: Date().addingTimeInterval(86400 * 11),
                outcome: "Choose how you take customer payments before your trial ends."
            )
            TrialStatusCard(
                daysRemaining: 2,
                endsAt: Date().addingTimeInterval(86400 * 2),
                outcome: "When your trial ends, your Team subscription of $32.98/month begins."
            )
        }
        .padding()
    }
    .background(Theme.canvas)
}
