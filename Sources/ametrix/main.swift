import AppKit
import Foundation

private enum CommandLineMode {
    case startScreenSaver
    case overlay
    case wallpaper
    case menuBar(startWallpaper: Bool)
    case preferences
    case printConfig
    case help
}

private enum QuitEvent {
    static func matches(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "q"
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if QuitEvent.matches(event) {
            NSApp.terminate(nil)
            return
        }

        super.keyDown(with: event)
    }
}

private enum OverlayMode {
    case overlay
    case wallpaper
}

private final class OverlaySessionManager {
    private let mode: OverlayMode
    private var sessions: [OverlaySession] = []
    private var screenObserver: NSObjectProtocol?
    private var screenChangeWorkItem: DispatchWorkItem?
    private(set) var isRunning = false

    init(mode: OverlayMode) {
        self.mode = mode
    }

    func start() {
        guard !isRunning else {
            return
        }

        isRunning = true
        installScreenObserver()
        rebuildSessions()
    }

    func stop() {
        guard isRunning || screenObserver != nil || !sessions.isEmpty else {
            return
        }

        isRunning = false
        screenChangeWorkItem?.cancel()
        screenChangeWorkItem = nil

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        closeSessions()
    }

    /// Rebuilds running sessions so they pick up the latest configuration on disk.
    func reload() {
        guard isRunning else {
            return
        }

        rebuildSessions()
    }

    private func installScreenObserver() {
        guard screenObserver == nil else {
            return
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleScreenRebuild()
        }
    }

    private func scheduleScreenRebuild() {
        guard isRunning else {
            return
        }

        screenChangeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.rebuildSessions()
        }
        screenChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func rebuildSessions() {
        guard isRunning else {
            return
        }

        closeSessions()
        let configuration = AmetrixConfiguration.load()

        sessions = NSScreen.screens.map {
            OverlaySession(screen: $0, configuration: configuration, mode: mode)
        }

        if mode == .overlay, let firstWindow = sessions.first?.window {
            firstWindow.makeKeyAndOrderFront(nil)
        }
    }

    private func closeSessions() {
        let activeSessions = sessions
        sessions.removeAll()
        activeSessions.forEach { $0.close() }
    }
}

private final class OverlaySession {
    let window: OverlayWindow
    let rainView: MatrixRainView

    init(screen: NSScreen, configuration: AmetrixConfiguration, mode: OverlayMode) {
        let window = OverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = mode == .wallpaper ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow))) : .screenSaver
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = mode == .wallpaper
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.setFrame(screen.frame, display: true)

        let rainView = MatrixRainView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            configuration: configuration
        )
        rainView.autoresizingMask = [.width, .height]

        window.contentView = rainView
        if mode == .wallpaper {
            window.orderFrontRegardless()
        } else {
            window.makeKeyAndOrderFront(nil)
        }

        self.window = window
        self.rainView = rainView
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let mode: OverlayMode
    private let sessionManager: OverlaySessionManager
    private var keyMonitor: Any?
    private var cursorHidden = false
    private var originalPresentationOptions: NSApplication.PresentationOptions = []

    init(mode: OverlayMode) {
        self.mode = mode
        self.sessionManager = OverlaySessionManager(mode: mode)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        originalPresentationOptions = NSApp.presentationOptions

        if mode == .overlay {
            installKeyMonitor()
        }
        if mode == .overlay {
            hideCursor()
        }

        if mode == .overlay {
            NSApp.presentationOptions = [
                .hideDock,
                .hideMenuBar
            ]
        }

        sessionManager.start()
        if mode == .overlay {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        tearDown()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        tearDown()
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if QuitEvent.matches(event) {
                NSApp.terminate(nil)
                return nil
            }

            return event
        }
    }

    private func hideCursor() {
        guard !cursorHidden else {
            return
        }

        NSCursor.hide()
        cursorHidden = true
    }

    private func unhideCursor() {
        guard cursorHidden else {
            return
        }

        NSCursor.unhide()
        cursorHidden = false
    }

    private func tearDown() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        sessionManager.stop()
        unhideCursor()
        NSApp.presentationOptions = originalPresentationOptions
    }
}

private final class MenuBarDelegate: NSObject, NSApplicationDelegate {
    private enum DefaultsKey {
        static let wallpaperEnabled = "AmetrixMenuBarWallpaperEnabled"
    }

    private let wallpaperManager = OverlaySessionManager(mode: .wallpaper)
    private let startWallpaper: Bool
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var installScreenSaverItem: NSMenuItem?
    private var wallpaperItem: NSMenuItem?
    private var settingsWindowController: SettingsWindowController?

    init(startWallpaper: Bool) {
        self.startWallpaper = startWallpaper
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()

        if startWallpaper || UserDefaults.standard.bool(forKey: DefaultsKey.wallpaperEnabled) {
            wallpaperManager.start()
            UserDefaults.standard.set(true, forKey: DefaultsKey.wallpaperEnabled)
        }

        updateMenu()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        wallpaperManager.stop()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaperManager.stop()
    }

    private func installStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Ametrix") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "Ametrix"
            }
        }

        let menu = NSMenu(title: "Ametrix")

        if bundledScreenSaverURL() != nil {
            let installScreenSaverItem = NSMenuItem(
                title: "Install Screen Saver",
                action: #selector(installScreenSaver),
                keyEquivalent: ""
            )
            installScreenSaverItem.target = self
            menu.addItem(installScreenSaverItem)
            menu.addItem(.separator())
            self.installScreenSaverItem = installScreenSaverItem
        }

        let wallpaperItem = NSMenuItem(
            title: "Start Wallpaper",
            action: #selector(toggleWallpaper),
            keyEquivalent: ""
        )
        wallpaperItem.target = self
        menu.addItem(wallpaperItem)

        let lockScreenItem = NSMenuItem(
            title: "Lock Screen",
            action: #selector(lockScreen),
            keyEquivalent: ""
        )
        lockScreenItem.target = self
        menu.addItem(lockScreenItem)

        let preferencesItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Ametrix",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
        self.menu = menu
        self.wallpaperItem = wallpaperItem
    }

    private func updateMenu() {
        let wallpaperEnabled = wallpaperManager.isRunning
        installScreenSaverItem?.title = installedScreenSaverExists()
            ? "Reinstall Screen Saver"
            : "Install Screen Saver"
        wallpaperItem?.title = wallpaperEnabled ? "Stop Wallpaper" : "Start Wallpaper"
        wallpaperItem?.state = wallpaperEnabled ? .on : .off
    }

    @objc private func installScreenSaver() {
        do {
            try installBundledScreenSaver()
            updateMenu()
            showMessage(
                title: "Ametrix screen saver installed.",
                message: "Select Ametrix once in System Settings > Screen Saver, then set Lock Screen to require a password immediately after the screen saver begins."
            )
        } catch {
            showMessage(
                title: "Ametrix could not install the screen saver.",
                message: "\(error)"
            )
        }
    }

    @objc private func toggleWallpaper() {
        if wallpaperManager.isRunning {
            wallpaperManager.stop()
            UserDefaults.standard.set(false, forKey: DefaultsKey.wallpaperEnabled)
        } else {
            wallpaperManager.start()
            UserDefaults.standard.set(true, forKey: DefaultsKey.wallpaperEnabled)
        }

        updateMenu()
    }

    @objc private func lockScreen() {
        DispatchQueue.global(qos: .userInitiated).async {
            let status = startSystemScreenSaver()
            guard status != 0 else {
                return
            }

            DispatchQueue.main.async {
                self.showScreenSaverError()
            }
        }
    }

    @objc private func openPreferences() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                onConfigurationChange: { [weak self] configuration in
                    self?.applyConfiguration(configuration)
                },
                onOpenConfigFile: { [weak self] in
                    self?.openConfigFileInEditor()
                }
            )
        }

        settingsWindowController?.show()
    }

    /// Persists a configuration edited in the preferences window and live-refreshes the wallpaper.
    private func applyConfiguration(_ configuration: AmetrixConfiguration) {
        persistConfiguration(configuration)
        wallpaperManager.reload()
    }

    private func openConfigFileInEditor() {
        do {
            try openConfigurationFileInEditor()
        } catch {
            showMessage(
                title: "Ametrix could not open the config file.",
                message: "\(error)"
            )
        }
    }

    @objc private func quit() {
        wallpaperManager.stop()
        NSApp.terminate(nil)
    }

    private func showScreenSaverError() {
        showMessage(
            title: "Ametrix could not start the lock screen.",
            message: "Install Ametrix.saver, then select Ametrix once in System Settings > Screen Saver."
        )
    }

    private func showMessage(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private final class PreferencesAppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let controller = SettingsWindowController(
            onConfigurationChange: { configuration in
                persistConfiguration(configuration)
            },
            onOpenConfigFile: {
                try? openConfigurationFileInEditor()
            }
        )
        settingsWindowController = controller
        controller.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private func parseMode(arguments: [String]) -> CommandLineMode? {
    let args = Array(arguments.dropFirst())
    if args.isEmpty {
        return launchedFromAppBundle() ? .menuBar(startWallpaper: false) : .startScreenSaver
    }

    if args == ["--overlay"] {
        return .overlay
    }

    if args == ["--wallpaper"] {
        return .wallpaper
    }

    if args == ["--menubar"] || args == ["--menu-bar"] {
        return .menuBar(startWallpaper: false)
    }

    if args == ["--menubar", "--wallpaper"] || args == ["--menu-bar", "--wallpaper"] {
        return .menuBar(startWallpaper: true)
    }

    if args == ["--preferences"] || args == ["--settings"] {
        return .preferences
    }

    if args == ["--print-config"] {
        return .printConfig
    }

    if args == ["--help"] || args == ["-h"] {
        return .help
    }

    return nil
}

private func launchedFromAppBundle() -> Bool {
    Bundle.main.bundleURL.pathExtension == "app"
}

private func printUsage() {
    print(
        """
        Usage:
          ametrix                Start the currently selected macOS screen saver
          ametrix --overlay      Run Ametrix's direct full-screen overlay
          ametrix --wallpaper    Run Ametrix as a desktop-level live wallpaper
          ametrix --menubar      Run Ametrix as a menu bar controller
          ametrix --menubar --wallpaper
                             Run menu bar mode and start wallpaper immediately
          ametrix --preferences  Open the Ametrix preferences window
          ametrix --print-config Print the resolved config source
          ametrix --help         Show this help

        Install Ametrix.saver with scripts/install/screensaver.sh, then select Ametrix
        once in System Settings > Screen Saver. macOS handles unlock/password.
        """
    )
}

private func writeError(_ message: String) {
    if let data = message.data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

private func installedScreenSaverExists() -> Bool {
    let fileManager = FileManager.default
    let home = fileManager.homeDirectoryForCurrentUser.path
    let candidates = [
        "\(home)/Library/Screen Savers/Ametrix.saver",
        "/Library/Screen Savers/Ametrix.saver"
    ]

    return candidates.contains {
        fileManager.fileExists(atPath: $0)
    }
}

private func bundledScreenSaverURL() -> URL? {
    Bundle.main.url(forResource: "Ametrix", withExtension: "saver")
}

private func installBundledScreenSaver() throws {
    guard let bundledScreenSaverURL = bundledScreenSaverURL() else {
        throw NSError(
            domain: "Ametrix",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Ametrix.saver was not found inside this app bundle."
            ]
        )
    }

    let fileManager = FileManager.default
    let destinationDirectory = fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Screen Savers", isDirectory: true)
    let destinationURL = destinationDirectory
        .appendingPathComponent("Ametrix.saver", isDirectory: true)

    try fileManager.createDirectory(
        at: destinationDirectory,
        withIntermediateDirectories: true
    )

    if fileManager.fileExists(atPath: destinationURL.path) {
        try fileManager.removeItem(at: destinationURL)
    }

    try fileManager.copyItem(at: bundledScreenSaverURL, to: destinationURL)
    try installBundledConfigurationIfNeeded()
    syncScreenSaverContainerConfiguration()
}

private func installBundledConfigurationIfNeeded() throws {
    let fileManager = FileManager.default
    let configurationDirectory = fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("Ametrix", isDirectory: true)
    let configurationURL = configurationDirectory
        .appendingPathComponent("config.toml", isDirectory: false)

    guard !fileManager.fileExists(atPath: configurationURL.path) else {
        return
    }

    guard let bundledConfigurationURL = Bundle.main.url(forResource: "config.example", withExtension: "toml") else {
        throw NSError(
            domain: "Ametrix",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey: "config.example.toml was not found inside this app bundle."
            ]
        )
    }

    try fileManager.createDirectory(
        at: configurationDirectory,
        withIntermediateDirectories: true
    )
    try fileManager.copyItem(at: bundledConfigurationURL, to: configurationURL)
}

private func ensureConfigurationFileExists() throws -> URL {
    let fileManager = FileManager.default

    for configurationURL in AmetrixConfiguration.tomlConfigurationURLs() where fileManager.fileExists(atPath: configurationURL.path) {
        return configurationURL
    }

    let configurationURL = AmetrixConfiguration.tomlConfigurationURL()
    if Bundle.main.url(forResource: "config.example", withExtension: "toml") != nil {
        try installBundledConfigurationIfNeeded()
    } else {
        try writeDefaultConfiguration(to: configurationURL)
    }

    return configurationURL
}

private func writeDefaultConfiguration(to configurationURL: URL) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(
        at: configurationURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try AmetrixConfiguration.default.tomlString().write(to: configurationURL, atomically: true, encoding: .utf8)
}

/// Writes a configuration back to the active config file and mirrors it into the
/// screen saver container. Shared by the menu bar and standalone preferences flows.
@discardableResult
private func persistConfiguration(_ configuration: AmetrixConfiguration) -> Bool {
    let target = AmetrixConfiguration.loadWithSource().sourceURL
        ?? AmetrixConfiguration.tomlConfigurationURL()

    do {
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try configuration.tomlString().write(to: target, atomically: true, encoding: .utf8)
        syncScreenSaverContainerConfiguration()
        return true
    } catch {
        writeError("ametrix: failed to save preferences: \(error)\n")
        return false
    }
}

private func openConfigurationFileInEditor() throws {
    let configurationURL = try ensureConfigurationFileExists()
    syncScreenSaverContainerConfiguration()
    NSWorkspace.shared.open(configurationURL)
}

private func terminateScreenSaverHelpers() {
    for processName in ["legacyScreenSaver", "ScreenSaverEngine"] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = [processName]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try? process.run()
        process.waitUntilExit()
    }
}

private func syncScreenSaverContainerConfiguration() {
    let result = AmetrixConfiguration.loadWithSource()
    guard let sourceURL = result.sourceURL,
          let destinationURL = AmetrixConfiguration.screenSaverContainerConfigurationURL(),
          sourceURL.standardizedFileURL.path != destinationURL.standardizedFileURL.path else {
        return
    }

    let fileManager = FileManager.default

    do {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    } catch {
        writeError("ametrix: warning: failed to sync screen saver config: \(error)\n")
    }
}

private func startSystemScreenSaver() -> Int32 {
    guard installedScreenSaverExists() else {
        writeError(
            """
            ametrix: Ametrix.saver is not installed.
            Run scripts/install/screensaver.sh, then select Ametrix in System Settings > Screen Saver.
            """
        )
        return 1
    }

    syncScreenSaverContainerConfiguration()
    terminateScreenSaverHelpers()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["/System/Library/CoreServices/ScreenSaverEngine.app"]

    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        writeError("ametrix: failed to start ScreenSaverEngine: \(error)\n")
        return 1
    }
}

private var overlayDelegate: AppDelegate?
private var menuBarDelegate: MenuBarDelegate?

private func runOverlay(mode: OverlayMode) {
    let app = NSApplication.shared
    let delegate = AppDelegate(mode: mode)
    overlayDelegate = delegate
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

private func runMenuBar(startWallpaper: Bool) {
    let app = NSApplication.shared
    let delegate = MenuBarDelegate(startWallpaper: startWallpaper)
    menuBarDelegate = delegate
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

private var preferencesDelegate: PreferencesAppDelegate?

private func runPreferences() {
    let app = NSApplication.shared
    let delegate = PreferencesAppDelegate()
    preferencesDelegate = delegate
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}

private func printConfig() {
    let result = AmetrixConfiguration.loadWithSource()
    let configuration = result.configuration

    print("Config source: \(result.sourceURL?.path ?? "defaults")")
    print("Preset: \(configuration.preset)")
    print("Density: \(configuration.density)")
    print("Frame rate: \(configuration.frameRate)")
    print("Font: \(configuration.fontName) \(Int(configuration.fontSize))pt")
    print("Background: \(configuration.backgroundColor.ametrixHexString)")
    print("Head: \(configuration.headColor.ametrixHexString)")
    print("Tail: \(configuration.tailColor.ametrixHexString)")
    print("Searched:")
    result.searchedURLs.forEach {
        print("  \($0.path)")
    }
}

guard let mode = parseMode(arguments: CommandLine.arguments) else {
    writeError("ametrix: unknown arguments. Run `ametrix --help`.\n")
    exit(64)
}

switch mode {
case .startScreenSaver:
    exit(startSystemScreenSaver())
case .overlay:
    runOverlay(mode: .overlay)
case .wallpaper:
    runOverlay(mode: .wallpaper)
case .menuBar(let startWallpaper):
    runMenuBar(startWallpaper: startWallpaper)
case .preferences:
    runPreferences()
case .printConfig:
    printConfig()
case .help:
    printUsage()
}
