import SwiftUI

/// The in-app "New message from Mike · Job #1047" banner. Tapping opens the
/// exact conversation; it slides away on its own after a few seconds.
struct MessageBannerView: View {
    let banner: CommunicationsMonitor.MessageBanner
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: banner.link.contains("/sms/") ? "message.fill" : "bubble.left.and.bubble.right.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent.gradient)
                    .clipShape(.circle)
                    .symbolEffect(.bounce, value: banner.id)
                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(banner.body)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.meta)
            }
            .padding(12)
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: 18))
            .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
        }
        .buttonStyle(PressableTileStyle())
        .padding(.horizontal, 12)
        .accessibilityIdentifier("comms.banner")
        .sensoryFeedback(.impact(weight: .medium), trigger: banner.id)
        .gesture(DragGesture().onEnded { value in if value.translation.height < -20 { dismiss() } })
        .task(id: banner.id) {
            try? await Task.sleep(for: .seconds(6))
            dismiss()
        }
    }
}
