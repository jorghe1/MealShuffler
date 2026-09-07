import UIKit

/// Touch feedback for the app's few genuinely physical moments.
///
/// Shuffle is the signature interaction and the one thing the app is named after; it should
/// feel like something happened. Kept to a handful of calls on purpose -- haptics everywhere
/// stop meaning anything.
enum Haptics {
    /// A new week, or a new dinner for one day.
    static func shuffle() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Ticking something off in the shop.
    static func check() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// A meal finished and recorded.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
