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
    static let warning = dynamic(light: (0.75, 0.36, 0.18), dark: (0.92, 0.58, 0.38))
    /// Text drawn on top of `accent`. Not plain white: on the light-green dark accent,
    /// white text falls below contrast.
    static let onAccent = dynamic(light: (1.00, 1.00, 1.00), dark: (0.05, 0.10, 0.07))
    static let destructive = dynamic(light: (0.78, 0.22, 0.20), dark: (0.95, 0.48, 0.44))

    static let cardRadius: CGFloat = 24

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
}
