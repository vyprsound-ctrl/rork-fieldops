import SwiftUI

/// Narrowing controls for the jobs list. Everything chosen here is applied by
/// the data layer on top of the role's own row gate — a dispatcher filtering by
/// worker still only ever sees their own company's rows.
struct JobFilterSheet: View {
    @Binding var query: JobQuery
    let options: JobFormOptions
    let terms: Terminology

    @Environment(\.dismiss) private var dismiss
    @State private var usesSpecificDate: Bool = false
    @State private var specificDate: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Date") {
                    Picker("Range", selection: scopeBinding) {
                        ForEach(JobDateScope.chips) { scope in
                            Text(scope.title).tag(scope.id)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("Pick a specific day", isOn: $usesSpecificDate)
                        .tint(Theme.primary)

                    if usesSpecificDate {
                        DatePicker("Day", selection: $specificDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                }

                Section("Status") {
                    ForEach(JobStatus.allCases) { status in
                        Button {
                            toggle(status)
                        } label: {
                            HStack {
                                Image(systemName: status.symbolName)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.primary)
                                    .frame(width: 26)
                                Text(status.title(terms))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                if query.statuses.contains(status) {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(Theme.primary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !options.workers.isEmpty {
                    Section(terms.Worker) {
                        Picker(terms.Worker, selection: workerBinding) {
                            Text("Anyone").tag("")
                            ForEach(options.workers) { worker in
                                Text(worker.name).tag(worker.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("Priority") {
                    Picker("Priority", selection: priorityBinding) {
                        Text("Any").tag("")
                        ForEach(JobPriority.allCases) { priority in
                            Text(priority.title).tag(priority.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if !options.customers.isEmpty {
                    Section("Customer") {
                        Picker("Customer", selection: customerBinding) {
                            Text("All customers").tag("")
                            ForEach(options.customers) { customer in
                                Text(customer.name).tag(customer.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section {
                    Button("Clear all filters", role: .destructive) {
                        query.clearRefinements()
                        usesSpecificDate = false
                        query.dateScope = .today
                    }
                }
            }
            .navigationTitle("Filter jobs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if case .on(let date) = query.dateScope {
                    usesSpecificDate = true
                    specificDate = date
                }
            }
            .onChange(of: usesSpecificDate) { _, isOn in
                query.dateScope = isOn ? .on(specificDate) : .today
            }
            .onChange(of: specificDate) { _, newValue in
                if usesSpecificDate { query.dateScope = .on(newValue) }
            }
        }
        .presentationDetents([.large])
    }

    private var scopeBinding: Binding<String> {
        Binding(
            get: { query.dateScope.id },
            set: { newValue in
                guard let scope = JobDateScope.chips.first(where: { $0.id == newValue }) else { return }
                usesSpecificDate = false
                query.dateScope = scope
            }
        )
    }

    private var workerBinding: Binding<String> {
        Binding(
            get: { query.fieldWorkerUserID ?? "" },
            set: { query.fieldWorkerUserID = $0.isEmpty ? nil : $0 }
        )
    }

    private var priorityBinding: Binding<String> {
        Binding(
            get: { query.priority?.rawValue ?? "" },
            set: { query.priority = JobPriority(rawValue: $0) }
        )
    }

    private var customerBinding: Binding<String> {
        Binding(
            get: { query.customerID ?? "" },
            set: { query.customerID = $0.isEmpty ? nil : $0 }
        )
    }

    private func toggle(_ status: JobStatus) {
        if query.statuses.contains(status) {
            query.statuses.remove(status)
        } else {
            query.statuses.insert(status)
        }
    }
}

#Preview {
    JobFilterSheet(
        query: .constant(.today),
        options: JobFormOptions(
            workers: [FieldWorkerOption(id: "1", name: "Marcus Hale", initials: "MH")],
            customers: [],
            canAssign: true
        ),
        terms: Trade.hvac.terminology
    )
}
