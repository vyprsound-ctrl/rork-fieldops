import SwiftUI

/// Turns an accepted quote into a job. Everything the customer agreed to is
/// carried across; the quote is left exactly as it was.
struct QuoteConvertSheet: View {
    let quote: QuoteDetailProjection
    let workers: [FieldWorkerOption]
    let terms: Terminology
    let onConvert: (QuoteConversionInput) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: JobKind = .install
    @State private var priority: JobPriority = .standard
    @State private var isScheduled: Bool = true
    @State private var start: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var durationMinutes: Int = 240
    @State private var workerID: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Carried over from \(quote.number)") {
                    carried(symbol: "person.crop.circle", text: quote.customerName)
                    carried(symbol: "mappin.and.ellipse", text: quote.addressLine)
                    carried(symbol: "doc.text", text: "Agreed scope of work")
                    carried(symbol: "link", text: "Quote reference kept on the job")
                }

                Section("New job") {
                    Picker("Type", selection: $kind) {
                        ForEach(JobKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(JobPriority.allCases) { priority in
                            Text(priority.title).tag(priority)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Schedule") {
                    Toggle("Book a slot now", isOn: $isScheduled)
                        .tint(Theme.primary)
                    if isScheduled {
                        DatePicker("Starts", selection: $start)
                        Picker("Duration", selection: $durationMinutes) {
                            Text("1 hr").tag(60)
                            Text("2 hrs").tag(120)
                            Text("Half day").tag(240)
                            Text("Full day").tag(480)
                        }
                    }
                }

                if !workers.isEmpty {
                    Section(terms.Worker) {
                        Picker("Assign to", selection: $workerID) {
                            Text("Assign later").tag("")
                            ForEach(workers) { worker in
                                Text(worker.name).tag(worker.id)
                            }
                        }
                    }
                }

                Section {
                    Text("The quote's status, dates, line items and totals are not changed by this. It keeps a link to the job that came from it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.meta)
                }
            }
            .navigationTitle("Quote → job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create job") {
                        let end = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: start)
                        onConvert(
                            QuoteConversionInput(
                                kind: kind,
                                priority: priority,
                                scheduledStart: isScheduled ? start : nil,
                                scheduledEnd: isScheduled ? end : nil,
                                fieldWorkerUserID: workerID.isEmpty ? nil : workerID
                            )
                        )
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func carried(symbol: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(Theme.primary)
                .frame(width: 26)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
