import ActivityKit
import SwiftUI
import WidgetKit

/// The cook-mode timer while the phone is locked or another app is open.
///
/// Started and ended by `CookModeView`; nothing is pushed. The countdown is drawn by the
/// system from `endsAt`, so it keeps running without the app being awake.
struct CookingTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CookingTimerAttributes.self) { context in
            CookingTimerLockScreenView(context: context)
                .activityBackgroundTint(AppTheme.background)
                .activitySystemActionForegroundColor(AppTheme.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.emoji)
                        .font(.system(size: 34))
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CookingCountdown(endsAt: context.state.endsAt, isStale: context.isStale)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.mealName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let step = context.state.stepText {
                        Text(step)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } compactLeading: {
                Text(context.attributes.emoji)
                    .accessibilityHidden(true)
            } compactTrailing: {
                CookingCountdown(endsAt: context.state.endsAt, isStale: context.isStale)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 52, alignment: .trailing)
            } minimal: {
                Text(context.attributes.emoji)
                    .accessibilityHidden(true)
            }
            .keylineTint(AppTheme.accent)
        }
    }
}

/// Lock screen and banner presentation.
struct CookingTimerLockScreenView: View {
    let context: ActivityViewContext<CookingTimerAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(context.attributes.emoji)
                .font(.system(size: 40))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.mealName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                if let step = context.state.stepText {
                    Text(step)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            CookingCountdown(endsAt: context.state.endsAt, isStale: context.isStale)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(AppTheme.accent)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120, alignment: .trailing)
        }
        .padding(16)
    }
}

/// Counts down to `endsAt` and stops at zero, rather than counting up past it as
/// `Text(_:style: .timer)` would.
struct CookingCountdown: View {
    let endsAt: Date
    let isStale: Bool

    var body: some View {
        let now = Date.now
        if isStale || endsAt <= now {
            Text(L10n.string("Timer finished"))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        } else {
            Text(timerInterval: now...endsAt, countsDown: true)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}
