import SwiftUI

/// Turns something shared in from another app into a reviewable draft.
///
/// Extraction runs here rather than in the share extension, which is killed for taking too
/// long or using too much memory. It always lands in the editor rather than saving directly:
/// the review step is what makes an occasionally-wrong extraction acceptable.
struct CapturedRecipeImportView: View {
    @Environment(\.dismiss) private var dismiss

    let capture: CapturedRecipe
    let finished: (ImportedRecipeDraft) -> Void
    let cancel: () -> Void

    @State private var errorMessage: String?
    @State private var isWorking = true
    @State private var attempt = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer()
                if isWorking {
                    ProgressView()
                        .controlSize(.large)
                    Text("Reading the recipe…")
                        .font(.headline).foregroundStyle(AppTheme.ink)
                    Text(capture.summary)
                        .font(.subheadline).foregroundStyle(AppTheme.muted)
                        .lineLimit(2).multilineTextAlignment(.center)
                } else if let errorMessage {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40)).foregroundStyle(AppTheme.warning)
                    Text("Could not read that")
                        .font(.headline).foregroundStyle(AppTheme.ink)
                    Text(errorMessage)
                        .font(.subheadline).foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                    Button("Try again") { attempt += 1 }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: AppTheme.controlRadius))
                        .padding(.top, 4)
                }
                Spacer()
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .appBackground()
            .navigationTitle("Add shared recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel(); dismiss() }
                }
            }
        }
        .task(id: attempt) { await run() }
    }

    private func run() async {
        isWorking = true
        errorMessage = nil
        do {
            let draft = try await RecipeCapture.extract(capture)
            try Task.checkCancellation()
            isWorking = false
            finished(draft)
        } catch is CancellationError { }
        catch {
            isWorking = false
            errorMessage = error.localizedDescription
        }
    }
}
