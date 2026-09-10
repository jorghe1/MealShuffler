import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Share to Meal Shuffler" from Safari, Instagram, Notes or Photos.
///
/// Where recipes actually come from now. This removes the copy-paste step that keeps meal
/// libraries small, and a small library is what makes shuffle feel repetitive.
///
/// It captures and returns. Extraction is a network round trip and share extensions are
/// killed for taking too long or using too much memory, so the work happens in the app.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let view = UIHostingController(rootView: ShareConfirmationView(
            capture: { [weak self] in await self?.capture() ?? false },
            done: { [weak self] in self?.finish() }
        ))
        addChild(view)
        view.view.frame = self.view.bounds
        view.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.view.backgroundColor = .clear
        self.view.addSubview(view.view)
        view.didMove(toParent: self)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Pulls whatever the host app offered, in order of usefulness.
    private func capture() async -> Bool {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return false }
        let providers = items.flatMap { $0.attachments ?? [] }

        // A URL beats its own page text: the service fetches the page itself and can also
        // take the hero image from it.
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
               url.scheme?.lowercased() == "https" {
                return RecipeInbox.add(CapturedRecipe(url: url))
            }
        }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let data = await imageData(from: provider), let filename = RecipeInbox.storeImage(data) {
                return RecipeInbox.add(CapturedRecipe(imageFilename: filename))
            }
        }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // A bare link arriving as text is still a link.
                if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                   url.scheme?.lowercased() == "https" {
                    return RecipeInbox.add(CapturedRecipe(url: url))
                } else {
                    return RecipeInbox.add(CapturedRecipe(text: text))
                }
            }
        }

        return false
    }

    /// Providers hand images over as a URL, UIImage or Data depending on the host app.
    private func imageData(from provider: NSItemProvider) async -> Data? {
        let identifier = UTType.image.identifier
        guard let item = try? await provider.loadItem(forTypeIdentifier: identifier) else { return nil }
        if let url = item as? URL { return try? Data(contentsOf: url) }
        if let data = item as? Data { return data }
        if let image = item as? UIImage { return image.jpegData(compressionQuality: 0.85) }
        return nil
    }
}

private struct ShareConfirmationView: View {
    let capture: () async -> Bool
    let done: () -> Void

    @State private var outcome: Outcome = .working

    /// Not named `State`: a nested type by that name shadows SwiftUI's property wrapper
    /// inside this view, and `@State` then fails to resolve.
    private enum Outcome {
        case working, saved, failed
    }

    var body: some View {
        VStack(spacing: 16) {
            switch outcome {
            case .working:
                ProgressView()
                Text("Saving…").font(.headline)
            case .saved:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 42)).foregroundStyle(AppTheme.accent)
                Text("Saved to Meal Shuffler").font(.headline)
                Text("Open the app to finish adding it.")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 42)).foregroundStyle(AppTheme.warning)
                Text("Nothing to save here").font(.headline)
                Text("Share a link, some text or a photo of a recipe.")
                    .font(.subheadline).foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
        .task {
            outcome = await capture() ? .saved : .failed
            // Long enough to read, short enough not to be in the way.
            try? await Task.sleep(for: .milliseconds(outcome == .saved ? 900 : 1600))
            done()
        }
    }
}
