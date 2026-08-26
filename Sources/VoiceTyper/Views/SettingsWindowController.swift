import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(appState: AppState) {
        let window = window ?? makeWindow(appState: appState)
        self.window = window

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
    }

    private func makeWindow(appState: AppState) -> NSWindow {
        let rootView = SettingsView(settings: appState.settings)
            .environmentObject(appState)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Настройки VoiceTyper"
        window.setContentSize(NSSize(width: 560, height: 520))
        window.minSize = NSSize(width: 520, height: 440)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.tabbingMode = .disallowed
        return window
    }
}
