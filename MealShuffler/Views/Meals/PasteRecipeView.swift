import SwiftUI
import UIKit

/// Paste a recipe in as text.
///
/// The third way people actually have a recipe -- copied out of a message, an email, a note
/// or a social post that no link can be made of. There was no way to do it in the app at all:
/// the only route was sharing text in from elsewhere, and that then reported that the import
/// service was not set up.
struct PasteRecipeView: View {
    @Environment(\.dismiss) private var dismiss
    let imported: (ImportedRecipeDraft) -> Void

    @State private var text = ""
    @State private var isReading = false
    @State private var errorMessage: String?

    private var canRead: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 && !isReading
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: $text)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("Paste the recipe here — the name, the ingredients, and the steps.")
                                .font(.body).foregroundStyle(AppTheme.muted)
                                .padding(.horizontal, 17).padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }

                VStack(alignment: .leading, spacing: 12) {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(AppTheme.warning)
                    }
                    Text("A heading like “Ingredients” helps, but is not required. You can correct everything before it is saved.")
                        .font(.caption).foregroundStyle(AppTheme.muted)

                    HStack(spacing: 10) {
                        Button {
                            if let clipboard = UIPasteboard.general.string { text = clipboard }
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                                .font(.subheadline.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.roundedRectangle(radius: AppTheme.controlRadius))
                        .disabled(!UIPasteboard.general.hasStrings)

                        Button {
                            Task { await read() }
                        } label: {
                            HStack {
                                Text("Read recipe").font(.headline)
                                if isReading { ProgressView().padding(.leading, 4) }
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: AppTheme.controlRadius))
                        .disabled(!canRead)
                    }
                }
                .padding(20)
            }
            .appBackground()
            .navigationTitle("Paste a recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func read() async {
        isReading = true
        errorMessage = nil
        defer { isReading = false }
        do {
            imported(try await RecipeCapture.extractText(text))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
