import SwiftUI

/// Opens the invoice picker from anywhere that isn't the invoices screen.
///
/// `CreateInvoiceSheet` needs the list of completed jobs and accepted quotes
/// that haven't been billed yet. The invoices screen already holds that; the
/// home screen doesn't, so this loads it first rather than presenting an empty
/// picker and calling it a feature.
struct NewInvoiceLauncher: View {
    let onCreated: (String) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var state: LoadState<InvoiceSourceOptions> = .idle

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        switch state {
        case .idle, .loading:
            NavigationStack {
                LoadingStateView(message: "Finding work to invoice")
                    .background(Theme.canvas)
                    .navigationTitle("New invoice")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                    }
            }
            .task { await load() }

        case .failed(let error):
            NavigationStack {
                ScrollView { ErrorStateView(error: error) { Task { await load() } } }
                    .background(Theme.canvas)
                    .navigationTitle("New invoice")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { dismiss() }
                        }
                    }
            }

        case .loaded(let sources):
            CreateInvoiceSheet(sources: sources, onCreated: onCreated)
        }
    }

    private func load() async {
        guard let session else { return }
        state = .loading
        do {
            state = .loaded(try await env.gateway.invoiceSources(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }
}
