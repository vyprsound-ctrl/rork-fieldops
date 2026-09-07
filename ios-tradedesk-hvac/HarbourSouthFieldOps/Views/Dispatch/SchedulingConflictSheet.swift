import SwiftUI

/// Shown when a change would double-book a field worker.
///
/// The platform does not forbid overlaps — dispatch is a human job and there are
/// good reasons to double-book. The rule is only that it can never happen
/// *silently*: the data layer refuses the first attempt and returns the clash,
/// this sheet shows exactly what it is, and only an explicit confirmation
/// carries the acknowledgement back.
struct SchedulingConflictSheet: View {
    let title: String
    /// What is about to happen, stated plainly — which job, which worker.
    var context: String? = nil
    let check: SchedulingCheck
    let confirmTitle: String
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    warningHeader

                    VStack(alignment: .leading, spacing: 8) {
                        Text(check.conflicts.count == 1 ? "The clash" : "The clashes")
                            .sectionLabelStyle()

                        VStack(spacing: 0) {
                            ForEach(Array(check.conflicts.enumerated()), id: \.element.id) { index, conflict in
                                conflictRow(conflict)
                                if index < check.conflicts.count - 1 {
                                    Divider().padding(.leading, 14)
                                }
                            }
                        }
                        .cardSurface()
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: 8) {
                        Button {
                            onConfirm()
                            dismiss()
                        } label: {
                            Text(confirmTitle)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                                .background(Theme.amber)
                                .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                        }
                        .buttonStyle(PressableTileStyle())

                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel")
                                .font(.headline)
                                .foregroundStyle(Theme.primary)
                                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                                .cardSurface()
                        }
                        .buttonStyle(PressableTileStyle())
                    }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var warningHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .frame(width: 44, height: 44)
                .background(Theme.amber.opacity(0.12))
                .clipShape(.circle)

            VStack(alignment: .leading, spacing: 3) {
                Text("This would double-book")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                if let context {
                    Text(context)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Go ahead only if that's deliberate. Nothing has been changed yet.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func conflictRow(_ conflict: SchedulingConflict) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.badge.clock.fill")
                .font(.footnote)
                .foregroundStyle(Theme.amber)
                .frame(width: 34, height: 34)
                .background(Theme.amber.opacity(0.12))
                .clipShape(.rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(conflict.workerName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Already on \(conflict.clashingJobNumber) — \(conflict.clashingJobTitle)")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(conflict.overlapLabel)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.amber)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

#Preview {
    SchedulingConflictSheet(
        title: "Assign worker",
        context: "Assigning J-1050 to Marcus Hale",
        check: SchedulingCheck(conflicts: [
            SchedulingConflict(
                id: "1",
                kind: .workerDoubleBooked,
                jobID: "job_1",
                jobNumber: "J-1050",
                clashingJobID: "job_2",
                clashingJobNumber: "J-1042",
                clashingJobTitle: "No cooling — call-out",
                workerUserID: "usr_marcus",
                workerName: "Marcus Hale",
                detail: "Marcus Hale is already on J-1042",
                overlapLabel: "10:30 – 12:00"
            )
        ]),
        confirmTitle: "Assign anyway"
    ) {}
}
