import SwiftUI

/// Status history, rendered as a vertical timeline. Shared by the office job
/// screen and the engineer job screen so both read the same audit trail.
struct JobTimelineSection: View {
    let entries: [JobTimelineEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Job timeline")
                .sectionLabelStyle()

            VStack(alignment: .leading, spacing: 0) {
                if entries.isEmpty {
                    Text("No status changes recorded yet.")
                        .font(.footnote)
                        .foregroundStyle(Theme.meta)
                        .padding(14)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                Image(systemName: entry.symbolName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(color(for: entry.tone))
                                    .frame(width: 28, height: 28)
                                    .background(color(for: entry.tone).opacity(0.12))
                                    .clipShape(.circle)

                                if index < entries.count - 1 {
                                    Rectangle()
                                        .fill(Theme.border)
                                        .frame(width: 1)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                            .frame(minHeight: 46)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.ink)
                                Text("\(entry.byLabel) · \(entry.timeLabel)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondary)
                                if let location = entry.locationLabel {
                                    HStack(spacing: 5) {
                                        Image(systemName: "location.fill")
                                            .font(.system(size: 9))
                                        Text(location)
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(Theme.meta)
                                }
                            }
                            .padding(.bottom, index < entries.count - 1 ? 14 : 0)

                            Spacer(minLength: 0)
                        }
                    }
                    .padding(14)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private func color(for tone: StatusTone) -> Color {
        switch tone {
        case .neutral: return Theme.meta
        case .info: return Theme.primary
        case .warning: return Theme.amber
        case .success: return Theme.green
        case .danger: return Theme.red
        }
    }
}

// MARK: - Notes

struct JobNotesSection: View {
    let notes: [JobNoteProjection]
    let canAdd: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Notes")
                    .sectionLabelStyle()
                if canAdd {
                    Button("Add", action: onAdd)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                }
            }

            VStack(spacing: 0) {
                if notes.isEmpty {
                    Text("No notes on this job yet.")
                        .font(.footnote)
                        .foregroundStyle(Theme.meta)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.body)
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 6) {
                                Text(note.authorInitials)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.primary)
                                    .frame(width: 22, height: 22)
                                    .background(Theme.primaryTint)
                                    .clipShape(.circle)
                                Text("\(note.authorName) · \(note.timeLabel)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondary)
                                Spacer(minLength: 0)
                                Text(note.visibilityTitle)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(note.isInternal ? Theme.meta : Theme.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background((note.isInternal ? Theme.meta : Theme.green).opacity(0.12))
                                    .clipShape(.rect(cornerRadius: 5))
                            }
                        }
                        .padding(14)

                        if index < notes.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }
}

// MARK: - Photos

struct JobPhotosSection: View {
    let photos: [JobPhotoProjection]
    let canAdd: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Photos")
                    .sectionLabelStyle()
                if canAdd {
                    Button("Add", action: onAdd)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                }
            }

            VStack(spacing: 0) {
                if photos.isEmpty {
                    Text("No photos attached yet.")
                        .font(.footnote)
                        .foregroundStyle(Theme.meta)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        HStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.primary)
                                .frame(width: 46, height: 46)
                                .background(Theme.primaryTint)
                                .clipShape(.rect(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(photo.caption ?? photo.kindTitle)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(2)
                                Text("\(photo.kindTitle) · \(photo.authorName) · \(photo.timeLabel)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)
                            SimulatedBadge(text: "No file")
                        }
                        .padding(14)

                        if index < photos.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()

            if !photos.isEmpty {
                Text("Development build: photo records are real, the image files are not uploaded anywhere.")
                    .font(.caption2)
                    .foregroundStyle(Theme.meta)
            }
        }
    }
}

// MARK: - Composers

struct AddNoteSheet: View {
    var showsVisibilityPicker: Bool = true
    let onSave: (String, NoteVisibility) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var body_: String = ""
    @State private var visibility: NoteVisibility = .internalOnly
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextEditor(text: $body_)
                    .font(.body)
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .cardSurface()
                    .focused($isFocused)
                    .overlay(alignment: .topLeading) {
                        if body_.isEmpty {
                            Text("What happened on site?")
                                .font(.body)
                                .foregroundStyle(Theme.meta)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }

                if showsVisibilityPicker {
                    Picker("Visibility", selection: $visibility) {
                        Text("Internal").tag(NoteVisibility.internalOnly)
                        Text("Customer visible").tag(NoteVisibility.customerVisible)
                    }
                    .pickerStyle(.segmented)
                }

                Spacer(minLength: 0)
            }
            .padding(Theme.margin)
            .background(Theme.canvas)
            .navigationTitle("Add note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(body_, visibility)
                        dismiss()
                    }
                    .disabled(body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
    }
}

struct AddPhotoSheet: View {
    let onSave: (JobPhotoKind, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: JobPhotoKind = .before
    @State private var caption: String = ""

    private let kinds: [JobPhotoKind] = [.before, .after, .part, .proof]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "camera.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.amber)
                        .frame(width: 32, height: 32)
                        .background(Theme.amber.opacity(0.12))
                        .clipShape(.circle)
                    Text("The camera isn't wired up yet. Saving attaches a photo record to the job with a simulated file reference.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.amber.opacity(0.08))
                .clipShape(.rect(cornerRadius: Theme.cardRadius))

                Picker("Type", selection: $kind) {
                    ForEach(kinds, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Caption (optional)", text: $caption)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .frame(minHeight: Theme.minTap)
                    .cardSurface()

                Spacer(minLength: 0)
            }
            .padding(Theme.margin)
            .background(Theme.canvas)
            .navigationTitle("Attach photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(kind, caption.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            JobTimelineSection(entries: [
                JobTimelineEntry(id: "1", title: "Scheduled → Engineer assigned", byLabel: "Carla Bell", timeLabel: "Sep 4 · 8:12 AM", locationLabel: nil, tone: .info, symbolName: "person.badge.shield.checkmark"),
                JobTimelineEntry(id: "2", title: "Engineer assigned → Travelling", byLabel: "Marcus Hale", timeLabel: "Sep 5 · 10:12 AM", locationLabel: "Location captured · 27.9760, -82.4720", tone: .warning, symbolName: "car.fill")
            ])
            JobNotesSection(notes: [], canAdd: true, onAdd: {})
        }
        .padding()
    }
    .background(Theme.canvas)
}
