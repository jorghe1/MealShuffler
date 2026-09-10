import SwiftUI

struct OnlineExtractionSettingsView: View {
    @AppStorage("online-extraction-enabled") private var enabled = false
    var body: some View {
        if RemoteRecipeExtractor.Configuration.fromBundle() != nil {
            Toggle("Use online recipe extraction", isOn: $enabled)
            Text("When enabled, recipe text and photos may be sent to the extraction service for recognition. Turn it off to use on-device recognition.")
        } else {
            Label("On-device recipe recognition", systemImage: "iphone")
            Text("Online extraction is not configured in this build. Pasted text, photos and structured recipe websites can still be imported on this device.")
        }
    }
}
