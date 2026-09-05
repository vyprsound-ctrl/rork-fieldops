import SwiftUI

/// Honest placeholder for capabilities that are intentionally out of scope in
/// the foundation phase. It never pretends the feature exists.
struct PhaseTwoSheet: View {
    let title: String
    var permission: Permission?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 56, height: 56)
                        .background(Theme.primaryTint)
                        .clipShape(.circle)

                    Text("\(title) is next")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.ink)

                    Text("The foundation phase builds the architecture, permissions and navigation only. This flow is scheduled for the next phase and has not been implemented yet.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)

                    if let permission {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Data layer requirement")
                                .sectionLabelStyle()
                            HStack(spacing: 8) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundStyle(Theme.primary)
                                Text(permission.title)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.ink)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardSurface()
                        }
                        .padding(.top, 4)
                    }

                    Spacer(minLength: 0)
                }
                .padding(Theme.margin)
            }
            .background(Theme.canvas)
            .navigationTitle("Not built yet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationContentInteraction(.scrolls)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        PhaseTwoSheet(title: "New Quote", permission: .quotesManage)
    }
}
