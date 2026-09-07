import SwiftUI

struct LoadingStateView: View {
    var message: String = "Loading"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateView: View {
    let symbolName: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Theme.primary)
                .frame(width: 64, height: 64)
                .background(Theme.primaryTint)
                .clipShape(.circle)

            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

struct ErrorStateView: View {
    let error: DataError
    var retry: (() -> Void)?

    private var symbolName: String {
        switch error {
        case .notPermitted: return "lock.fill"
        case .offline: return "wifi.slash"
        case .notFound: return "questionmark.folder"
        case .invalidTransition: return "arrow.triangle.branch"
        case .rejected: return "exclamationmark.octagon.fill"
        case .unexpected: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        if case .notPermitted = error { return Theme.secondary }
        return Theme.red
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(tint.opacity(0.1))
                .clipShape(.circle)

            Text(error.errorDescription ?? "Something went wrong")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)

            Text(error.recoveryHint)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)

            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.bordered)
                    .tint(Theme.primary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 24) {
            LoadingStateView(message: "Loading today's jobs")
                .frame(height: 200)
            EmptyStateView(symbolName: "calendar", title: "Nothing booked", message: "Jobs you schedule will show up here.", actionTitle: "New job", action: {})
            ErrorStateView(error: .notPermitted(.invoicesRead), retry: {})
        }
    }
    .background(Theme.canvas)
}
