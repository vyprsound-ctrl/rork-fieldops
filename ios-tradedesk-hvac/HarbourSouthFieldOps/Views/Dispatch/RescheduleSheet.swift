import SwiftUI

/// Moves a job to a new slot, or clears its slot entirely so it drops back into
/// the unscheduled backlog.
///
/// Whether the move is allowed is decided by the data layer, not by this sheet:
/// an overlap comes back as a conflict warning the dispatcher must accept.
struct RescheduleSheet: View {
    let jobNumber: String
    let jobTitle: String
    let currentStart: Date?
    let currentEnd: Date?
    let onSave: (Date?, Date?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isScheduled: Bool = true
    @State private var start: Date = Date()
    @State private var durationMinutes: Int = 90

    private static let durationOptions: [Int] = [30, 45, 60, 90, 120, 180, 240, 480]

    private var end: Date { start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(jobTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                } header: {
                    Text(jobNumber)
                }

                Section {
                    Toggle("Give this job a slot", isOn: $isScheduled.animation())
                } footer: {
                    Text(isScheduled
                         ? "The job appears on the calendar and counts towards the assigned worker's day."
                         : "The job goes back to the unscheduled list for dispatch to place later.")
                }

                if isScheduled {
                    Section("When") {
                        DatePicker("Starts", selection: $start)

                        Picker("Duration", selection: $durationMinutes) {
                            ForEach(Self.durationOptions, id: \.self) { minutes in
                                Text(Formatters.relativeDuration(minutes: minutes)).tag(minutes)
                            }
                        }

                        LabeledContent("Ends") {
                            Text(Formatters.dayAndTime(end))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(isScheduled ? start : nil, isScheduled ? end : nil)
                        dismiss()
                    }
                }
            }
            .onAppear(perform: prime)
        }
        .presentationDetents([.medium, .large])
    }

    private func prime() {
        if let currentStart {
            isScheduled = true
            start = currentStart
            if let currentEnd {
                let minutes = Int(currentEnd.timeIntervalSince(currentStart) / 60)
                durationMinutes = Self.durationOptions.min { abs($0 - minutes) < abs($1 - minutes) } ?? 90
            }
        } else {
            // An unscheduled job opens on the next sensible working slot rather
            // than "right now, this second".
            isScheduled = false
            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
    }
}

#Preview {
    RescheduleSheet(
        jobNumber: "J-1046",
        jobTitle: "Compressor rebuild",
        currentStart: nil,
        currentEnd: nil
    ) { _, _ in }
}
