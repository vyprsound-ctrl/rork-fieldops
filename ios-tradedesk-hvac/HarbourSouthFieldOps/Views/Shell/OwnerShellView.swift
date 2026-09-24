import SwiftUI

/// Owner, Admin, Dispatcher and Accounts share this five-tab shell in the
/// approved order. Which data each tab receives is decided by the data layer,
/// not by this view.
struct OwnerShellView: View {
    @Environment(AppEnvironment.self) private var env

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
            // The global message indicator: unread customer replies and team
            // messages, visible from every tab.
            Tab("More", systemImage: "ellipsis") {
                MoreView()
            }
            .badge(env.communications.unread.total)
        }
        .tint(Theme.primary)
    }
}

#Preview {
    OwnerShellView()
        .environment(AppEnvironment())
}
