import PhotosUI
import SwiftUI
import UIKit

/// Turns a captured image into something worth sending over a job-site
/// connection.
///
/// Field photos are evidence, not portfolio pieces: 1400px on the long edge is
/// enough to read a rating plate or show a cracked coil, and it keeps a typical
/// frame under a quarter of a megabyte. The compression steps down until it
/// fits rather than sending whatever the camera produced.
nonisolated enum JobImageEncoder {
    static let maximumDimension: CGFloat = 1400
    static let targetBytes: Int = 240_000

    static func encode(_ image: UIImage) -> Data? {
        let resized = downscale(image)
        var quality: CGFloat = 0.7
        var data = resized.jpegData(compressionQuality: quality)

        while let current = data, current.count > targetBytes, quality > 0.3 {
            quality -= 0.1
            data = resized.jpegData(compressionQuality: quality)
        }
        return data
    }

    private static func downscale(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maximumDimension else { return image }

        let scale = maximumDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// The device camera.
///
/// Kept as a plain UIKit picker on purpose: it is the one component that works
/// identically on a handset in a plant room and on a machine where the camera
/// is presented as an external device. `isAvailable` is checked at runtime, so
/// a device with no camera shows the library instead of a dead button.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.allowsEditing = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture) { dismiss() }
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let onFinish: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onFinish: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onFinish = onFinish
        }

        nonisolated func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            Task { @MainActor in
                if let image { onCapture(image) }
                onFinish()
            }
        }

        nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            Task { @MainActor in onFinish() }
        }
    }
}

/// Collects job photos before they are sent: pick or shoot, label, remove.
///
/// Used by the completion sheet and by the "add photo" flow on a job, so an
/// engineer meets the same control in both places.
struct JobPhotoCollector: View {
    @Binding var uploads: [JobMediaUpload]
    /// Categorisation is optional and deliberately quick: a segmented row would
    /// not fit ten categories, so this is a menu that defaults to something
    /// sensible. A worker on a roof can shoot several photos without ever
    /// opening it.
    var allowedKinds: [JobPhotoKind] = JobPhotoKind.selectable

    @State private var libraryItem: PhotosPickerItem?
    @State private var isShowingCamera: Bool = false
    @State private var pendingKind: JobPhotoKind = .before
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Category")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)

                Picker("Category", selection: $pendingKind) {
                    ForEach(allowedKinds, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.primary)

                Spacer(minLength: 0)

                Text("Optional")
                    .font(.caption2)
                    .foregroundStyle(Theme.meta)
            }

            HStack(spacing: 10) {
                if CameraPicker.isAvailable {
                    Button {
                        isShowingCamera = true
                    } label: {
                        captureLabel(symbol: "camera.fill", title: "Take photo")
                    }
                    .buttonStyle(PressableTileStyle())
                }

                PhotosPicker(selection: $libraryItem, matching: .images, photoLibrary: .shared()) {
                    captureLabel(symbol: "photo.on.rectangle", title: "Choose photo")
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Theme.red)
            }

            if uploads.isEmpty {
                Text("No photos attached yet.")
                    .font(.footnote)
                    .foregroundStyle(Theme.meta)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(uploads.enumerated()), id: \.element.id) { index, upload in
                        if index > 0 { Divider().padding(.leading, 74) }
                        row(for: upload, at: index)
                    }
                }
                .cardSurface()
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in add(image) }
                .ignoresSafeArea()
        }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                defer { libraryItem = nil }
                guard
                    let data = try? await item.loadTransferable(type: Data.self),
                    let image = UIImage(data: data)
                else {
                    errorMessage = "That image couldn't be read. Try another one."
                    return
                }
                add(image)
            }
        }
    }

    private func captureLabel(symbol: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Theme.primary)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Theme.primaryTint)
        .clipShape(.rect(cornerRadius: Theme.buttonRadius))
    }

    private func row(for upload: JobMediaUpload, at index: Int) -> some View {
        HStack(spacing: 12) {
            if let image = UIImage(data: upload.data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(.rect(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(upload.kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                TextField("Caption (optional)", text: captionBinding(for: index))
                    .font(.footnote)
                    .textFieldStyle(.plain)
            }

            Spacer(minLength: 4)

            Text(upload.sizeLabel)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Theme.meta)

            Button {
                uploads.removeAll { $0.id == upload.id }
            } label: {
                Image(systemName: "trash")
                    .font(.footnote)
                    .foregroundStyle(Theme.red)
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(upload.kind.title) photo")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func captionBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { uploads.indices.contains(index) ? uploads[index].caption : "" },
            set: { if uploads.indices.contains(index) { uploads[index].caption = $0 } }
        )
    }

    private func add(_ image: UIImage) {
        guard let data = JobImageEncoder.encode(image) else {
            errorMessage = "That photo couldn't be prepared for upload."
            return
        }
        errorMessage = nil
        uploads.append(JobMediaUpload(kind: pendingKind, data: data))
    }
}

/// One stored photo, full screen.
///
/// Evidence is only useful if it can be read: a 46pt thumbnail cannot show a
/// rating plate, a serial number or a hairline crack. This loads the stored
/// image at full size and allows pinch-to-zoom, which is the difference between
/// "there is a photo of the fault" and "I can see the fault".
///
/// The image is shown directly rather than behind a `Color` anchor because this
/// is a full-screen interactive viewer — the zoom and pan gestures have to
/// reach the image itself.
struct JobPhotoViewer: View {
    let reference: String
    let title: String
    let subtitle: String

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var isLoading: Bool = true
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoom)
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    // Clamped so the image cannot be pinched
                                    // away to nothing or into a blur.
                                    zoom = min(max(committedZoom * value.magnification, 1), 6)
                                }
                                .onEnded { _ in committedZoom = zoom }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.snappy) {
                                zoom = zoom > 1 ? 1 : 2.5
                                committedZoom = zoom
                            }
                        }
                        .accessibilityIdentifier("photoViewer.image")
                } else if isLoading {
                    ProgressView().tint(.white)
                } else {
                    ContentUnavailableView(
                        "Photo unavailable",
                        systemImage: "photo",
                        description: Text("This photo couldn't be loaded. Check your connection and try again.")
                    )
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("photoViewer.unavailable")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: reference) { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        switch JobMediaReference.parse(reference) {
        case .inlineData(let data, _):
            image = UIImage(data: data)
        case .storage:
            guard let session = env.activeSession else { return }
            guard let url = try? await env.gateway.jobMediaURL(session: session, reference: reference) else { return }
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            image = UIImage(data: data)
        case .simulated, .unrecognised:
            image = nil
        }
    }
}

/// Loads a stored job photo, whichever way it was stored.
///
/// An uploaded object is fetched through a signed URL; an image held with the
/// record is decoded straight from the reference. A reference with no image
/// behind it shows a plain marker rather than a spinner that never stops.
struct JobPhotoThumbnail: View {
    let reference: String
    var size: CGFloat = 52

    @Environment(AppEnvironment.self) private var env
    @State private var image: UIImage?
    @State private var isLoading: Bool = true

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading, JobMediaReference.parse(reference).hasImage {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: size * 0.32))
                    .foregroundStyle(Theme.primary)
            }
        }
        .frame(width: size, height: size)
        .background(Theme.primaryTint)
        .clipShape(.rect(cornerRadius: 10))
        .task(id: reference) { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        switch JobMediaReference.parse(reference) {
        case .inlineData(let data, _):
            image = UIImage(data: data)
        case .storage:
            guard let session = env.activeSession else { return }
            guard let url = try? await env.gateway.jobMediaURL(session: session, reference: reference) else { return }
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            image = UIImage(data: data)
        case .simulated, .unrecognised:
            image = nil
        }
    }
}
