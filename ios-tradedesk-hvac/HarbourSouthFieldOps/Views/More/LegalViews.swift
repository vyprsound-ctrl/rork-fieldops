import SwiftUI

/// More → Legal: the four in-app Harbour South documents.
struct LegalView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "building.columns.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 48, height: 48)
                        .background(Theme.brandNavy.gradient)
                        .clipShape(.rect(cornerRadius: 13))
                    Text("Legal")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text("Harbour South's documents, readable right here in the app.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(LegalDocument.allCases.enumerated()), id: \.element.id) { index, document in
                        NavigationLink {
                            LegalDocumentView(document: document)
                        } label: {
                            LegalRow(document: document)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("legal.row.\(document.rawValue)")
                        if index < LegalDocument.allCases.count - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .cardSurface()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Published on harboursouth.us")
                        .sectionLabelStyle()
                    VStack(spacing: 0) {
                        ForEach(Array(LegalDocument.allCases.enumerated()), id: \.element.id) { index, document in
                            LegalWebRow(document: document)
                            if index < LegalDocument.allCases.count - 1 {
                                Divider().padding(.leading, 58)
                            }
                        }
                    }
                    .cardSurface()
                    Text("Opens the current published version in your browser.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                }

                Text("Last updated \(LegalDocument.lastUpdated)")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 12)
        }
        .background(Theme.canvas)
        .navigationTitle("Legal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

private struct LegalRow: View {
    let document: LegalDocument

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: document.symbolName)
                .font(.footnote)
                .foregroundStyle(Theme.primary)
                .frame(width: 32, height: 32)
                .background(Theme.primaryTint)
                .clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                Text(document.summary)
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.meta)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .frame(minHeight: Theme.minTap)
        .contentShape(.rect)
    }
}

/// Opens the published copy of a document at its exact harboursouth.us URL.
struct LegalWebRow: View {
    let document: LegalDocument

    var body: some View {
        if let url = document.webURL {
            Link(destination: url) {
                HStack(spacing: 12) {
                    Image(systemName: "safari")
                        .font(.footnote)
                        .foregroundStyle(Theme.primary)
                        .frame(width: 32, height: 32)
                        .background(Theme.primaryTint)
                        .clipShape(.rect(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.title)
                            .font(.body)
                            .foregroundStyle(Theme.ink)
                        Text(url.host().map { "\($0)\(url.path())" } ?? document.webURLString)
                            .font(.caption)
                            .foregroundStyle(Theme.meta)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.meta)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .frame(minHeight: Theme.minTap)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(document.title), opens harboursouth.us in your browser")
            .accessibilityIdentifier("legal.web.\(document.rawValue)")
        }
    }
}

/// One legal document, rendered natively.
struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(document.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("legal.document.title")
                    Text("Harbour South FieldOps · Updated \(LegalDocument.lastUpdated)")
                        .font(.footnote)
                        .foregroundStyle(Theme.meta)
                }

                ForEach(document.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.heading)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let url = document.webURL {
                    Link(destination: url) {
                        Label("View the published version on harboursouth.us", systemImage: "safari")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("legal.document.web")
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 16)
            .textSelection(.enabled)
        }
        .background(Theme.surface)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

/// Compact links to the in-app documents, used beside sign-in, Delete account,
/// Subscription and SMS setup. Pass `includeAppleEULA` where App Store
/// subscriptions are sold.
struct LegalLinksView: View {
    var documents: [LegalDocument] = [.privacyPolicy, .termsOfService]
    var includeAppleEULA: Bool = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { links }
            VStack(alignment: .leading, spacing: 8) { links }
        }
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var links: some View {
        ForEach(documents) { document in
            NavigationLink {
                LegalDocumentView(document: document)
            } label: {
                Text(document.title).foregroundStyle(Theme.primary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier(document))
        }
        if includeAppleEULA, let eula = Brand.appleEULAURL {
            Link("Apple EULA", destination: eula)
                .accessibilityIdentifier("legal.appleEULA")
        }
    }

    private func identifier(_ document: LegalDocument) -> String {
        switch document {
        case .privacyPolicy: return "legal.privacy"
        case .termsOfService: return "legal.terms"
        case .smsTerms: return "legal.sms"
        case .accountDeletion: return "legal.deletion"
        }
    }
}

/// Presents documents in a sheet where there is no navigation stack (sign-in).
struct LegalSheetLinks: View {
    @State private var shown: LegalDocument?
    var documents: [LegalDocument] = [.privacyPolicy, .termsOfService]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(documents) { document in
                Button(document.title) { shown = document }
                    .accessibilityIdentifier("signin.legal.\(document.rawValue)")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Theme.primary)
        .frame(maxWidth: .infinity)
        .sheet(item: $shown) { document in
            NavigationStack {
                LegalDocumentView(document: document)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { shown = nil }
                        }
                    }
            }
        }
    }
}

#Preview {
    NavigationStack { LegalView() }
}
