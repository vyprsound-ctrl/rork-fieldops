import SwiftUI

/// Setting your own availability.
///
/// Three options, not six. Travelling, on site and working are facts about a
/// job — the app already knows them from the job's own status — so offering
/// them here would let an engineer claim to be working when they are not, and
/// give dispatch two answers to the same question. What the engineer sets is
/// the part the job cannot say: am I free, on a break, or done for the day.
struct EngineerAvailabilitySheet: View {
    let profile: EngineerProfile
    let onSelect: (DutyState) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if profile.availability.isDerivedFromJob {
                        liveJobNotice
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(DutyState.allCases.enumerated()), id: \.element.id) { index, state in
                            Button {
                                onSelect(state)
                                dismiss()
                            } label: {
                                row(state)
                            }
                            .buttonStyle(.plain)

                            if index < DutyState.allCases.count - 1 {
                                Divider().padding(.leading, 58)
                            }
                        }
                    }
                    .cardSurface()

                    Text("Dispatch can see this so they know who to send to the next call-out. It changes nothing about your jobs, and you can only set your own.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.margin)
            }
            .background(Theme.canvas)
            .navigationTitle("Availability")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
    }

    private var liveJobNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: profile.availability.symbolName)
                .font(.footnote)
                .foregroundStyle(Theme.amber)
                .frame(width: 32, height: 32)
                .background(Theme.amber.opacity(0.12))
                .clipShape(.circle)

            VStack(alignment: .leading, spacing: 2) {
                Text("You're \(profile.availability.title.lowercased()) right now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(
                    profile.activeJobNumber.map {
                        "That comes from job \($0). Dispatch sees it until you finish — what you choose below applies afterwards."
                    } ?? "That comes from your live job. What you choose below applies once it's finished."
                )
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amber.opacity(0.08))
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    private func row(_ state: DutyState) -> some View {
        let isSelected = profile.dutyState == state
        return HStack(spacing: 12) {
            Image(systemName: state.symbolName)
                .font(.footnote)
                .foregroundStyle(isSelected ? Theme.primary : Theme.secondary)
                .frame(width: 32, height: 32)
                .background(isSelected ? Theme.primaryTint : Theme.canvas)
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(state.title)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Theme.ink)
                Text(state.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.primary)
            }
        }
        .padding(.horizontal, 13)
        .frame(minHeight: Theme.minTap)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
