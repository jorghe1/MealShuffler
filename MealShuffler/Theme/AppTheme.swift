import SwiftUI
import UIKit

/// The app's palette, defined for both appearances.
///
/// These used to be fixed literals, which is why `RootView` pinned the whole app to
/// `.preferredColorScheme(.light)`: without a second set of values, honouring the system
/// appearance would have painted dark text on dark ground. Each token resolves against the
/// current trait collection instead, so the modifier could be removed.
enum AppTheme {
    static let background = dynamic(light: (0.97, 0.95, 0.90), dark: (0.07, 0.08, 0.07))
    static let surface = dynamic(light: (1.00, 1.00, 1.00), dark: (0.12, 0.13, 0.12))
    /// Sits on `surface`; used for chips and pills that need to read as raised.
    static let raised = dynamic(light: (1.00, 1.00, 1.00), dark: (0.17, 0.19, 0.17))
    static let accent = dynamic(light: (0.12, 0.42, 0.28), dark: (0.44, 0.78, 0.58))
    static let accentSoft = dynamic(light: (0.82, 0.90, 0.80), dark: (0.16, 0.25, 0.19))
    static let ink = dynamic(light: (0.12, 0.16, 0.12), dark: (0.91, 0.94, 0.91))
    static let muted = dynamic(light: (0.39, 0.42, 0.36), dark: (0.63, 0.68, 0.62))
    static let warning = dynamic(light: (0.62, 0.27, 0.10), dark: (0.92, 0.58, 0.38))
    /// Text drawn on top of `accent`. Not plain white: on the light-green dark accent,
    /// white text falls below contrast.
    static let onAccent = dynamic(light: (1.00, 1.00, 1.00), dark: (0.05, 0.10, 0.07))
    static let destructive = dynamic(light: (0.78, 0.22, 0.20), dark: (0.95, 0.48, 0.44))

    // MARK: - Category palette
    //
    // Five hues for "what kind of food is this", used by the week composition bar. Kept
    // apart from the semantic colours above: `warning` means something is wrong, and a bar
    // segment for chicken does not. Each is defined for both appearances and ordered so
    // neighbouring segments never share a hue family.
    static let categoryFish = dynamic(light: (0.15, 0.45, 0.62), dark: (0.46, 0.75, 0.93))
    static let categoryChicken = dynamic(light: (0.80, 0.58, 0.16), dark: (0.94, 0.76, 0.38))
    static let categoryMeat = dynamic(light: (0.68, 0.30, 0.24), dark: (0.91, 0.55, 0.47))
    static let categoryVegetarian = dynamic(light: (0.28, 0.55, 0.31), dark: (0.53, 0.82, 0.57))
    static let categoryOther = dynamic(light: (0.52, 0.48, 0.60), dark: (0.72, 0.69, 0.80))

    // MARK: - Scale
    //
    // Corner radii and control sizes were picked per view, which produced eight radii and
    // five circular-button sizes for what are really three shapes and two roles. Four of the
    // icon buttons also landed under the 44pt Apple asks for, and the day lock sat inside a
    // tappable card -- so a near miss opened the recipe instead of locking the day.

    /// Cards: day plans, list groups, sheets.
    static let cardRadius: CGFloat = 24
    /// Buttons, banners and inline panels sitting on a card.
    static let controlRadius: CGFloat = 16
    /// Chips, tokens and the small emoji tiles.
    static let chipRadius: CGFloat = 12
    /// The one large image or illustration on a screen: a recipe hero, an onboarding card.
    static let heroRadius: CGFloat = 28

    /// The smallest a tappable control may be.
    static let tapTarget: CGFloat = 44
    /// The one prominent circular action per screen.
    static let primaryAction: CGFloat = 54
    /// Emoji tile on a full-width row.
    static let emojiTile: CGFloat = 56
    /// Emoji tile on a compact row.
    static let emojiTileCompact: CGFloat = 44

    private static func dynamic(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let channels = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: channels.0,
                green: channels.1,
                blue: channels.2,
                alpha: 1
            )
        })
    }
}

extension View {
    func appBackground() -> some View {
        background(AppTheme.background.ignoresSafeArea())
    }

    func mealCard() -> some View {
        self
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 18, y: 8)
    }

    /// A selectable pill. Three views drew this three ways -- `surface`, `raised` and a
    /// permanently-tinted variant -- for the same control.
    func chipStyle(selected: Bool) -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(selected ? AppTheme.accent : AppTheme.raised)
            .foregroundStyle(selected ? AppTheme.onAccent : AppTheme.ink)
            .clipShape(Capsule())
    }

    /// An icon-only control, sized so it can actually be hit.
    func iconButtonFrame() -> some View {
        frame(width: AppTheme.tapTarget, height: AppTheme.tapTarget)
            .contentShape(Rectangle())
    }
}
