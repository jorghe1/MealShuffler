import SwiftUI

/// The privacy policy, in the app.
///
/// App Review asks for a policy reachable from inside the app as well as from the store page.
/// The web copy lives on the recipe service (`/privacy`), which only exists once it is
/// deployed, so the facts are also kept here and the web link is offered when there is one.
/// docs/PRIVACY.md is the source both are written from.
struct PrivacyView: View {
    private var webURL: URL? {
        RemoteRecipeExtractor.Configuration.fromBundle()?.baseURL.appendingPathComponent("privacy")
    }

    var body: some View {
        List {
            Section {
                Text("Meal Shuffler keeps your meals, recipes, rules, plans, shopping lists and history on this phone. There is no account, no advertising and no analytics.")
            }
            Section("What can leave the phone") {
                PrivacyRow(
                    title: L10n.string("Reading recipes online"),
                    detail: L10n.string("Off unless you turn it on. The link, text or photos you import are sent to the Meal Shuffler recipe service, which uses Anthropic's Claude to read the recipe and sends the result back. Neither keeps the recipe or uses it for training. A random install id and your IP address are used only to stop abuse.")
                )
                PrivacyRow(
                    title: L10n.string("Importing from a website"),
                    detail: L10n.string("The phone contacts that website directly, the same way a browser would, and loads the recipe picture from it.")
                )
                PrivacyRow(
                    title: L10n.string("Sharing with a friend"),
                    detail: L10n.string("A shared recipe, rule list or week travels inside the link itself. The page that opens it stores nothing.")
                )
                PrivacyRow(
                    title: L10n.string("Send to Bring!"),
                    detail: L10n.string("The shopping list is put in a link that Bring! fetches to import it. Bring! then handles it under its own privacy policy.")
                )
                if FeatureFlags.householdSyncEnabled {
                    PrivacyRow(
                        title: L10n.string("iCloud sharing"),
                        detail: L10n.string("If you share your household through iCloud, it is stored in your own iCloud. The developer cannot read it.")
                    )
                }
            }
            Section("Reminders and widgets") {
                Text("Reminders are scheduled on this phone, and the widget reads the plan on this phone. Nothing is sent to do either.")
            }
            Section("Deleting your data") {
                Text("Deleting the app deletes everything it stored. The recipe service keeps nothing, so there is nothing to delete there.")
            }
            if let webURL {
                Section {
                    Link(destination: webURL) {
                        Label("Full privacy policy", systemImage: "safari")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Space.xs) {
            Text(title).font(.headline).foregroundStyle(AppTheme.ink)
            Text(detail).font(.subheadline).foregroundStyle(AppTheme.muted)
        }
        .padding(.vertical, AppTheme.Space.xxs)
    }
}
