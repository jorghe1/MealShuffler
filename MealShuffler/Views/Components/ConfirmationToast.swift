import SwiftUI

/// The store's `confirmation`, shown briefly at the top and then gone.
///
/// For things that went as asked. A problem still gets an alert through `actionNotice`; a
/// confirmation that has to be dismissed is a confirmation too many.
struct ConfirmationToast: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let text = store.confirmation {
                Label(text, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, AppTheme.Space.l)
                    .padding(.vertical, AppTheme.Space.m)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                    .padding(.horizontal, AppTheme.Space.screen)
                    .padding(.top, AppTheme.Space.s)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .onTapGesture { store.confirmation = nil }
                    .accessibilityIdentifier("confirmation.toast")
                    .task(id: text) {
                        AccessibilityNotification.Announcement(text).post()
                        try? await Task.sleep(for: .seconds(2.5))
                        guard !Task.isCancelled, store.confirmation == text else { return }
                        store.confirmation = nil
                    }
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: store.confirmation)
    }
}
