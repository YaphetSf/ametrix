import AppKit
import SwiftUI

/// Owns the Ametrix preferences window, hosting the SwiftUI `SettingsView` inside
/// an AppKit `NSWindow`. The window is created lazily and reused across opens.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    /// Persists an edited configuration (debounced by the store) and refreshes any running rain.
    private let onConfigurationChange: (AmetrixConfiguration) -> Void
    /// Opens the raw config.toml in the user's editor.
    private let onOpenConfigFile: () -> Void
    /// Screen saver / wallpaper controls shown at the bottom (menu bar mode only).
    private let setupActions: SettingsSetupActions?

    init(
        onConfigurationChange: @escaping (AmetrixConfiguration) -> Void,
        onOpenConfigFile: @escaping () -> Void,
        setupActions: SettingsSetupActions? = nil
    ) {
        self.onConfigurationChange = onConfigurationChange
        self.onOpenConfigFile = onOpenConfigFile
        self.setupActions = setupActions
    }

    func show() {
        if let window {
            bringToFront(window)
            return
        }

        let result = AmetrixConfiguration.loadWithSource()
        let configurationPath = result.sourceURL?.path
            ?? AmetrixConfiguration.tomlConfigurationURL().path

        let store = SettingsStore(
            configuration: result.configuration,
            configurationPath: configurationPath
        )
        store.onApply = { [weak self] configuration in
            self?.onConfigurationChange(configuration)
        }

        let rootView = SettingsView(
            store: store,
            openConfigFile: { [weak self] in self?.onOpenConfigFile() },
            setup: setupActions
        )

        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = "Ametrix Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        self.window = window
        bringToFront(window)
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
