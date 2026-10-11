import SwiftUI

/// Locks a day's dinner against the next shuffle, in one tap.
///
/// Drawn on every day that can still change, locked or not: an open lock says the day *can*
/// be locked, which a lock shown only once something was already locked never did. 0.6.0 hid
/// it behind a swipe and a sheet, and the feature read as gone.
struct LockButton: View {
    let isLocked: Bool
    let dayName: String
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .font(.body.weight(.semibold))
                .foregroundStyle(isLocked ? AppTheme.accent : AppTheme.muted)
                .contentTransition(.symbolEffect(.replace))
                .iconButtonFrame()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLocked ? L10n.string("Unlock %@", dayName) : L10n.string("Lock %@", dayName))
        .accessibilityHint(L10n.string("A locked dinner stays when you shuffle"))
    }
}
