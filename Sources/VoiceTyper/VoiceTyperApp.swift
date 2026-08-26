import SwiftUI

@main
@MainActor
struct VoiceTyperApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.statusSymbol)
                .accessibilityLabel(appState.statusTitle)
        }
        .menuBarExtraStyle(.window)

    }
}
