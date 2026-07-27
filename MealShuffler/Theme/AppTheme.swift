import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.97, green: 0.95, blue: 0.90)
    static let surface = Color.white.opacity(0.92)
    static let accent = Color(red: 0.12, green: 0.42, blue: 0.28)
    static let accentSoft = Color(red: 0.82, green: 0.90, blue: 0.80)
    static let ink = Color(red: 0.12, green: 0.16, blue: 0.12)
    static let muted = Color(red: 0.39, green: 0.42, blue: 0.36)
    static let warning = Color(red: 0.75, green: 0.36, blue: 0.18)

    static let cardRadius: CGFloat = 24
}
extension View {
    func appBackground() -> some View {
        background(AppTheme.background.ignoresSafeArea())
    }

    func mealCard() -> some View {
        self
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .shadow(color: AppTheme.ink.opacity(0.07), radius: 18, y: 8)
    }
}
