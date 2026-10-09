import PhotosUI
import SwiftUI
import UIKit

/// "Take a picture of it?" -- offered once, right after a dish is marked cooked, while it is
/// still on the table. The photo then replaces the drawing wherever the dish shows.
///
/// Optional and easy to wave away: the library already looks finished with drawings, and a
/// prompt that nags would get turned off.
struct DinnerPhotoSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let meal: Meal

    @State private var showsCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: AppTheme.Space.l) {
            MealArtwork(meal: meal)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                .accessibilityHidden(true)

            VStack(spacing: AppTheme.Space.xs) {
                Text("Take a picture of it?")
                    .font(AppTheme.Typography.title)
                    .foregroundStyle(AppTheme.ink)
                Text(L10n.string("Your own photo of %@ replaces the drawing in the library and on the week.", meal.name))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
            }

            if failed {
                Text("That photo could not be saved. Try another one.")
                    .font(.footnote).foregroundStyle(AppTheme.warning)
            }

            VStack(spacing: AppTheme.Space.s) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showsCamera = true } label: { Label("Take photo", systemImage: "camera") }
                        .buttonStyle(.primary)
                }
                PhotosPicker(selection: $libraryItem, matching: .images) {
                    Label("Choose from photos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.secondaryFullWidth)
                Button("Not now") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
                    .frame(minHeight: 44)
            }
            .disabled(isSaving)
        }
        .padding(AppTheme.Space.xl)
        .overlay { if isSaving { ProgressView() } }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { data in
                showsCamera = false
                if let data { save(data) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    libraryItem = nil
                    if let data { save(data) } else { failed = true }
                }
            }
        }
    }

    private func save(_ data: Data) {
        isSaving = true
        let saved = store.savePhoto(data, for: meal)
        isSaving = false
        if saved {
            Haptics.success()
            dismiss()
        } else {
            failed = true
        }
    }
}

/// The system camera, returning JPEG data, or nil when cancelled.
struct CameraPicker: UIViewControllerRepresentable {
    let completion: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (Data?) -> Void

        init(completion: @escaping (Data?) -> Void) {
            self.completion = completion
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            completion(image?.jpegData(compressionQuality: 0.85))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
        }
    }
}
