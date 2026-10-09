import AudioToolbox
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

    /// The reels rolling: a light, quick tick, like a wheel passing its pegs.
    static func tick() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// One day's reel settling on its dinner after a shuffle. Firmer than the ticks, so the
    /// landing is felt as the week falls into place, day by day.
    static func land() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)
        ShuffleSound.land()
    }

    /// Ticking something off in the shop.
    static func check() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// A meal finished and recorded, or a whole week drawn.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// An optional soft click as each day lands. Off by default; follows the silent switch,
/// because system sounds do.
enum ShuffleSound {
    static let enabledKey = "shuffle-sound-enabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static func land() {
        guard isEnabled else { return }
        // The keyboard "tock": short, wooden, and already familiar.
        AudioServicesPlaySystemSound(1104)
    }
}

extension Notification.Name {
    /// The phone was shaken. Posted by `UIWindow`; the Week screen shuffles on it.
    static let deviceDidShake = Notification.Name("no.mealshuffler.deviceDidShake")
}

extension UIWindow {
    /// Shaking the phone is the natural gesture for "shuffle", and children love it.
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}
