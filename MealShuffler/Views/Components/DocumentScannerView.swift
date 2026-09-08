import SwiftUI
import UIKit
import VisionKit

/// The system document scanner, for photographing a recipe off a page.
///
/// The library picker was the only way in, so a cookbook on the kitchen counter could not be
/// imported without first taking a photo in another app and coming back. This is also the
/// right tool rather than a plain camera: it finds the page edges, corrects the perspective
/// and lets a recipe that runs over two pages be captured as two pages.
struct DocumentScannerView: UIViewControllerRepresentable {
    let scanned: ([Data]) -> Void
    let cancelled: () -> Void

    /// False in the simulator and on the rare device without support, so the caller can hide
    /// an entry point that could only disappoint.
    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator {
        Coordinator(scanned: scanned, cancelled: cancelled)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let scanned: ([Data]) -> Void
        private let cancelled: () -> Void

        init(scanned: @escaping ([Data]) -> Void, cancelled: @escaping () -> Void) {
            self.scanned = scanned
            self.cancelled = cancelled
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            // JPEG rather than the raw image: this is handed to text recognition or uploaded,
            // and a full-resolution scan of a page is tens of megabytes.
            let pages = (0..<scan.pageCount).compactMap { index in
                scan.imageOfPage(at: index).jpegData(compressionQuality: 0.85)
            }
            scanned(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            cancelled()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            cancelled()
        }
    }
}
