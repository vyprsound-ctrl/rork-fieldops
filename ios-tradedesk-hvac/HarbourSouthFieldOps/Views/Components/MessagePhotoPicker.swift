import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

/// The camera / photo-library control in a message composer.
///
/// WHY THIS IS NOT `AddPhotoSheet`
/// Attaching evidence to a job is a considered act: you pick a category, you
/// write a caption, you review the list. Sending someone a picture mid-sentence
/// is not. This control is one tap to a choice of camera or library, multi-select
/// in the library, and straight back to the conversation — the categorisation a
/// job photo needs would be noise here, so a message image is filed as `other`
/// and the conversation itself carries the meaning.
///
/// PERMISSION DENIAL IS NOT A DEAD END
/// If the camera or the library is refused, the composer keeps working and the
/// reason is shown with a route to Settings. Text messaging is never affected by
/// a photo permission, and the control is never removed from under somebody.
struct MessagePhotoPicker: View {
    /// Called with every image the person chose, already compressed.
    let onPicked: ([JobMediaUpload]) -> Void
    var isDisabled: Bool = false

    @State private var isChoosingSource: Bool = false
    @State private var isShowingCamera: Bool = false
    @State private var librarySelection: [PhotosPickerItem] = []
    @State private var isShowingLibrary: Bool = false
    @State private var permissionMessage: String?
    @State private var isPreparing: Bool = false

    var body: some View {
        Button {
            isChoosingSource = true
        } label: {
            Group {
                if isPreparing {
                    ProgressView().controlSize(.small).tint(Theme.primary)
                } else {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                }
            }
            .frame(width: 44, height: 44)
            .background(Theme.primaryTint)
            .clipShape(.circle)
        }
        .buttonStyle(PressableTileStyle())
        .disabled(isDisabled || isPreparing)
        .accessibilityLabel("Attach photos")
        .accessibilityIdentifier("composer.attachPhotos")
        .confirmationDialog("Attach a photo", isPresented: $isChoosingSource, titleVisibility: .visible) {
            // A device with no camera — which includes the simulator the app is
            // reviewed on — is offered the library rather than a dead button.
            if CameraPicker.isAvailable {
                Button("Take Photo") { takePhoto() }
            }
            Button("Choose Photos") { choosePhotos() }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in
                if let upload = Self.prepare(image) {
                    onPicked([upload])
                } else {
                    permissionMessage = "That photo couldn't be prepared to send."
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $isShowingLibrary,
            selection: $librarySelection,
            maxSelectionCount: 10,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: librarySelection) { _, items in
            guard !items.isEmpty else { return }
            Task { await load(items) }
        }
        .alert(
            "Photos",
            isPresented: Binding(
                get: { permissionMessage != nil },
                set: { if !$0 { permissionMessage = nil } }
            )
        ) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text(permissionMessage ?? "")
        }
    }

    private func takePhoto() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isShowingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        isShowingCamera = true
                    } else {
                        permissionMessage = Self.cameraDenied
                    }
                }
            }
        case .denied, .restricted:
            permissionMessage = Self.cameraDenied
        @unknown default:
            permissionMessage = Self.cameraDenied
        }
    }

    /// The library is opened directly.
    ///
    /// `PHPickerViewController` runs outside the app's process and returns only
    /// what was actually chosen, so it needs no library permission at all. There
    /// is deliberately no authorisation prompt here — asking for one would be a
    /// gratuitous request for access the app does not need.
    private func choosePhotos() {
        isShowingLibrary = true
    }

    private func load(_ items: [PhotosPickerItem]) async {
        isPreparing = true
        defer {
            isPreparing = false
            librarySelection = []
        }

        var prepared: [JobMediaUpload] = []
        var failed = 0
        for item in items {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data),
                let upload = Self.prepare(image)
            else {
                failed += 1
                continue
            }
            prepared.append(upload)
        }

        // Whatever could be read is attached. One unreadable image out of five
        // must not cost somebody the other four.
        if !prepared.isEmpty { onPicked(prepared) }
        if failed > 0 {
            permissionMessage = failed == 1
                ? "One photo couldn't be read and wasn't attached."
                : "\(failed) photos couldn't be read and weren't attached."
        }
    }

    private static func prepare(_ image: UIImage) -> JobMediaUpload? {
        guard let data = JobImageEncoder.encode(image) else { return nil }
        // Message images are deliberately uncategorised: the conversation is
        // the context. On a job thread this still lands in the job's evidence.
        return JobMediaUpload(kind: .other, data: data)
    }

    private static let cameraDenied =
        "Camera access is off for this app. You can turn it on in Settings — you can still send photos from your library, and messaging works as normal."
}
