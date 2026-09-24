import SwiftUI

/// Seat resolution: Apple applied a smaller plan and the company has more
/// active people than it allows.
///
/// Nobody is chosen, suspended or deleted automatically. The owner opens the
/// team, deactivates the people they choose (everyone keeps their records and
/// can be reactivated later within the plan), and normal work resumes the
/// moment the company is within its plan.
struct SeatResolutionView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var isChecking: Bool = false

    private var access: WorkspaceAccess? { env.workspaceAccess }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let access, let limit = access.userLimit {
                    seatCard(active: access.activeUsers, limit: limit)
                }

                VStack(spacing: 10) {
                    NavigationLink(value: AppRoute.more(.fieldWorkers)) {
                        BrandButtonLabel(title: "Choose who stays active", role: .accent)
                    }
                    .buttonStyle(PressableTileStyle())
                    .accessibilityIdentifier("seatResolution.manageTeam")

                    NavigationLink(value: AppRoute.more(.subscription)) {
                        BrandOutlineLabel(title: "Subscription", symbol: "creditcard")
                    }
                    .buttonStyle(PressableTileStyle())

                    Button {
                        Task { await check() }
                    } label: {
                        BrandOutlineLabel(title: isChecking ? "Checking…" : "Check again", symbol: "arrow.clockwise")
                    }
                    .buttonStyle(PressableTileStyle())
                    .disabled(isChecking)
                }

                Text("Nobody is removed automatically. People you deactivate keep all their records and can be reactivated later within your plan.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)

                NavigationLink {
                    DeleteAccountView()
                } label: {
                    Text("Delete account")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.meta)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 12)
        }
        .background(Theme.canvas)
        .navigationTitle("Too many active users")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await check() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "person.2.slash")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(width: 52, height: 52)
                .background(Theme.amber.gradient)
                .clipShape(.rect(cornerRadius: 14))
            Text(access?.planName.map { "Your plan is now \($0)" } ?? "Your plan has changed")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text(access?.seatResolutionMessage ?? "Your plan now allows fewer active users than your company has. Deactivate people to continue.")
                .font(.body)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("seatResolution.message")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func seatCard(active: Int, limit: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(active)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.amber)
                .contentTransition(.numericText())
            Text("active · your plan allows \(limit)")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: active)
    }

    private func check() async {
        isChecking = true
        await env.refreshWorkspaceAccess()
        isChecking = false
    }
}

#Preview {
    NavigationStack {
        SeatResolutionView()
    }
    .environment(AppEnvironment())
}
