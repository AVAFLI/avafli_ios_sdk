//
//  AvafliV2ClaimStep3.swift
//  AvafliSDK
//
//  Step 3 of 4 — "SHOW OFF YOUR WIN!": large circular photo preview with an
//  accent ring + camera badge, UPLOAD PHOTO (library) and TAKE PHOTO (camera,
//  simulator-safe fallback to the library) buttons. Photo is optional.
//

import SwiftUI

struct AvafliClaimStep3View: View {
    let accent: Color
    @Binding var form: AvafliPrizeClaimForm
    @Binding var photo: UIImage?
    let onContinue: () -> Void

    @State private var showLibraryPicker = false
    @State private var showCamera = false

    var body: some View {
        AvafliClaimStepPage(
            accent: accent,
            title: "SHOW OFF YOUR WIN!",
            subtitle: "Upload a photo we'd be proud to\nfeature as one of our winners.",
            onCTA: onContinue
        ) {
            VStack(spacing: 9) {
                avatar
                    .padding(.bottom, 7)

                VStack(spacing: 12) {
                    photoButton(icon: "square.and.arrow.up", title: "UPLOAD PHOTO") {
                        showLibraryPicker = true
                    }
                    photoButton(icon: "camera.fill", title: "TAKE PHOTO") { takePhoto() }
                }
                .frame(width: 277)

                Text("Your photo may appear in our Winner Gallery,\nsocial media, and promotional materials.")
                    .font(AvafliV2Font.inter(12))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 26)
            .padding(.bottom, 17)
        }
        .sheet(isPresented: $showLibraryPicker) {
            AvafliPhotoPicker { attach($0) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            AvafliCameraPicker { attach($0) }
                .ignoresSafeArea()
        }
    }

    /// 242pt circular preview with the 2pt accent ring and the 80pt camera
    /// badge breaking the bottom-right edge (tappable — same as TAKE PHOTO).
    private var avatar: some View {
        ZStack {
            Circle().fill(AvafliV2Color.gunmetal)
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 110))
                    .foregroundColor(.white.opacity(0.18))
            }
        }
        .frame(width: 242, height: 242)
        .clipShape(Circle())
        .overlay(Circle().stroke(accent, lineWidth: 2))
        .overlay(alignment: .bottomTrailing) {
            Button(action: takePhoto) {
                Circle()
                    .fill(AvafliV2Color.deepCharcoal)
                    .overlay(Circle().stroke(accent, lineWidth: 2.2))
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    )
                    .frame(width: 80, height: 80)
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: 2)
            .accessibilityLabel("Take photo")
        }
    }

    private func photoButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(AvafliV2Font.inter(22, .semibold))
                    .kerning(-0.66)
            }
            .foregroundColor(.white)
            .padding(.leading, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 47)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.6), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Camera when available; on the simulator (no camera) fall back to the
    /// photo library so the button still works end-to-end.
    private func takePhoto() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showCamera = true
        } else {
            showLibraryPicker = true
        }
    }

    /// Store the preview immediately, encode the upload payload off-main
    /// (same downscale/base64 pipeline as the Light form).
    private func attach(_ image: UIImage?) {
        photo = image
        form.photoBase64 = nil
        guard let image else { return }
        Task.detached(priority: .userInitiated) {
            let encoded = AvafliClaimPhoto.base64Jpeg(from: image)
            await MainActor.run { form.photoBase64 = encoded }
        }
    }
}

// MARK: - Camera wrapper

/// UIImagePickerController camera wrapper (PHPicker has no camera source).
/// Only presented when `isSourceTypeAvailable(.camera)` — see takePhoto().
struct AvafliCameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            picker.dismiss(animated: true)
            onPick(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
