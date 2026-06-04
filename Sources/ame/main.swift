import AppKit
import Foundation

private enum CommandLineMode {
    case startScreenSaver
    case overlay
    case wallpaper
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

private final class OverlaySession {
    let window: OverlayWindow
    let rainView: MatrixRainView

    init(screen: NSScreen, configuration: AmeConfiguration, mode: OverlayMode) {
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
    private var sessions: [OverlaySession] = []
    private var keyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var screenChangeWorkItem: DispatchWorkItem?
    private var cursorHidden = false
    private var terminating = false
    private var originalPresentationOptions: NSApplication.PresentationOptions = []

    init(mode: OverlayMode) {
        self.mode = mode
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        originalPresentationOptions = NSApp.presentationOptions

        if mode == .overlay {
            installKeyMonitor()
        }
        installScreenObserver()
        if mode == .overlay {
            hideCursor()
        }

        if mode == .overlay {
            NSApp.presentationOptions = [
                .hideDock,
                .hideMenuBar
            ]
        }

        rebuildOverlays()
        if mode == .overlay {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminating = true
        tearDown()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        terminating = true
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

    private func installScreenObserver() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleScreenRebuild()
        }
    }

    private func scheduleScreenRebuild() {
        guard !terminating else {
            return
        }

        screenChangeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.rebuildOverlays()
        }
        screenChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func rebuildOverlays() {
        closeSessions()
        let configuration = AmeConfiguration.load()

        sessions = NSScreen.screens.map {
            OverlaySession(screen: $0, configuration: configuration, mode: mode)
        }

        if mode == .overlay, let firstWindow = sessions.first?.window {
            firstWindow.makeKeyAndOrderFront(nil)
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
        screenChangeWorkItem?.cancel()
        screenChangeWorkItem = nil

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        closeSessions()
        unhideCursor()
        NSApp.presentationOptions = originalPresentationOptions
    }

    private func closeSessions() {
        let activeSessions = sessions
        sessions.removeAll()
        activeSessions.forEach { $0.close() }
    }
}

private func parseMode(arguments: [String]) -> CommandLineMode? {
    let args = Array(arguments.dropFirst())
    if args.isEmpty {
        return .startScreenSaver
    }

    if args == ["--overlay"] {
        return .overlay
    }

    if args == ["--wallpaper"] {
        return .wallpaper
    }

    if args == ["--print-config"] {
        return .printConfig
    }

    if args == ["--help"] || args == ["-h"] {
        return .help
    }

    return nil
}

private func printUsage() {
    print(
        """
        Usage:
          ame                Start the currently selected macOS screen saver
          ame --overlay      Run Ame's direct full-screen overlay
          ame --wallpaper    Run Ame as a desktop-level live wallpaper
          ame --print-config Print the resolved config source
          ame --help         Show this help

        Install Ame.saver with scripts/install-screensaver.sh, then select Ame
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
        "\(home)/Library/Screen Savers/Ame.saver",
        "/Library/Screen Savers/Ame.saver"
    ]

    return candidates.contains {
        fileManager.fileExists(atPath: $0)
    }
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
    let result = AmeConfiguration.loadWithSource()
    guard let sourceURL = result.sourceURL,
          let destinationURL = AmeConfiguration.screenSaverContainerConfigurationURL(),
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
        writeError("ame: warning: failed to sync screen saver config: \(error)\n")
    }
}

private func startSystemScreenSaver() -> Int32 {
    guard installedScreenSaverExists() else {
        writeError(
            """
            ame: Ame.saver is not installed.
            Run scripts/install-screensaver.sh, then select Ame in System Settings > Screen Saver.
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
        writeError("ame: failed to start ScreenSaverEngine: \(error)\n")
        return 1
    }
}

private var overlayDelegate: AppDelegate?

private func runOverlay(mode: OverlayMode) {
    let app = NSApplication.shared
    let delegate = AppDelegate(mode: mode)
    overlayDelegate = delegate
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

private func printConfig() {
    let result = AmeConfiguration.loadWithSource()
    let configuration = result.configuration

    print("Config source: \(result.sourceURL?.path ?? "defaults")")
    print("Preset: \(configuration.preset)")
    print("Density: \(configuration.density)")
    print("Frame rate: \(configuration.frameRate)")
    print("Font: \(configuration.fontName) \(Int(configuration.fontSize))pt")
    print("Background: \(configuration.backgroundColor.ameHexString)")
    print("Head: \(configuration.headColor.ameHexString)")
    print("Tail: \(configuration.tailColor.ameHexString)")
    print("Searched:")
    result.searchedURLs.forEach {
        print("  \($0.path)")
    }
}

guard let mode = parseMode(arguments: CommandLine.arguments) else {
    writeError("ame: unknown arguments. Run `ame --help`.\n")
    exit(64)
}

switch mode {
case .startScreenSaver:
    exit(startSystemScreenSaver())
case .overlay:
    runOverlay(mode: .overlay)
case .wallpaper:
    runOverlay(mode: .wallpaper)
case .printConfig:
    printConfig()
case .help:
    printUsage()
}
