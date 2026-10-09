import SwiftUI

/// The switch for reading recipes with the online service, and what it sends where.
///
/// App Review asks for clear disclosure, with consent, before personal content goes to a
/// third-party AI service. "The extraction service" said neither who runs it nor who reads the
/// recipe, so the text names both, and turning it on asks once before anything is sent.
struct OnlineExtractionSettingsView: View {
    @AppStorage("online-extraction-enabled") private var enabled = false
    @State private var askingConsent = false

    var body: some View {
        if RemoteRecipeExtractor.Configuration.fromBundle() != nil {
            Toggle("Read recipes online", isOn: Binding(
                get: { enabled },
                set: { wanted in
                    if wanted { askingConsent = true } else { enabled = false }
                }
            ))
            Text("When this is on, the link, text or photos you import are sent to the Meal Shuffler recipe service, which uses Anthropic's Claude to read the recipe. Nothing is stored there. Turn it off to read recipes on this device only.")
                .font(.footnote).foregroundStyle(AppTheme.muted)
                .alert("Read recipes online?", isPresented: $askingConsent) {
                    Button("Turn on") { enabled = true }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("The recipe you import is sent to the Meal Shuffler recipe service and to Anthropic, which reads it and sends the result back. Neither keeps it or uses it for training. You can turn this off at any time.")
                }
        } else {
            Label("On-device recipe recognition", systemImage: "iphone")
            Text("Online extraction is not configured in this build. Pasted text, photos and structured recipe websites can still be imported on this device.")
                .font(.footnote).foregroundStyle(AppTheme.muted)
        }
    }
}
