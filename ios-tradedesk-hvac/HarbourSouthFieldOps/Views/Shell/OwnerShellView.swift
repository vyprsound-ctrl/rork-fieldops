import SwiftUI

/// Owner, Admin, Dispatcher and Accounts share this five-tab shell in the
/// approved order. Which data each tab receives is decided by the data layer,
/// not by this view.
struct OwnerShellView: View {
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "gauge.with.dots.needle.33percent") {
                DashboardView()
            }
            Tab("Jobs", systemImage: "list.clipboard") {
                JobsView()
            }
            Tab("Calendar", systemImage: "calendar") {
                CalendarView()
            }
            Tab("Customers", systemImage: "person.2") {
                CustomersView()
            }
            Tab("More", systemImage: "ellipsis") {
                MoreView()
            }
        }
        .tint(Theme.primary)
    }
}

#Preview {
    OwnerShellView()
        .environment(AppEnvironment())
}
