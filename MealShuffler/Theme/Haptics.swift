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

    /// One day's reel settling on its dinner after a shuffle. Light, because seven of them
    /// land in a row: together they should feel like a slot machine, not an alarm.
    static func land() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.8)
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
