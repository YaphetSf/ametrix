import AppKit
import SwiftUI

/// First-run welcome window. Installs the screen saver and introduces the
/// wallpaper and global lock shortcut.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    /// Installs the bundled saver. Returns `true` on success.
    private let installSaver: () -> Bool
    /// Whether `Ametrix.saver` is already installed (drives the step 1 checkmark).
    private let saverInstalled: () -> Bool
    private let openScreenSaverSettings: () -> Void
    private let toggleWallpaper: () -> Void
    private let wallpaperRunning: () -> Bool
    /// Called whenever the guide is dismissed (Done or close) — records that it ran.
    private let onCompleted: () -> Void
    /// Called only when the user presses Done — opens the main app window next.
    private let onProceed: () -> Void

    init(
        installSaver: @escaping () -> Bool,
        saverInstalled: @escaping () -> Bool,
        openScreenSaverSettings: @escaping () -> Void,
        toggleWallpaper: @escaping () -> Void,
        wallpaperRunning: @escaping () -> Bool,
        onCompleted: @escaping () -> Void,
        onProceed: @escaping () -> Void
    ) {
        self.installSaver = installSaver
        self.saverInstalled = saverInstalled
        self.openScreenSaverSettings = openScreenSaverSettings
        self.toggleWallpaper = toggleWallpaper
        self.wallpaperRunning = wallpaperRunning
        self.onCompleted = onCompleted
        self.onProceed = onProceed
    }

    func show() {
        if let window {
            bringToFront(window)
            return
        }

        let view = OnboardingView(
            appIcon: NSApp.applicationIconImage,
            saverInstalled: saverInstalled,
            installSaver: installSaver,
            openScreenSaverSettings: openScreenSaverSettings,
            toggleWallpaper: toggleWallpaper,
            wallpaperRunning: wallpaperRunning,
            finish: { [weak self] in self?.finish() }
        )

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Ametrix"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 540, height: 580))
        window.center()

        self.window = window
        bringToFront(window)
    }

    private func finish() {
        let proceed = onProceed
        window?.close()
        DispatchQueue.main.async {
            proceed()
        }
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window (red button or Done) records onboarding as complete.
        onCompleted()
        window = nil
    }
}

// MARK: - View

struct OnboardingView: View {
    let appIcon: NSImage?
    let saverInstalled: () -> Bool
    let installSaver: () -> Bool
    let openScreenSaverSettings: () -> Void
    let toggleWallpaper: () -> Void
    let wallpaperRunning: () -> Bool
    let finish: () -> Void

    @State private var installed = false
    @State private var screenSaverSettingsOpened = false
    @State private var wallpaperEnabled = false

    private static let accent = Color(red: 0.0, green: 0.95, blue: 0.37)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Self.accent.opacity(0.25))

            VStack(alignment: .leading, spacing: 14) {
                StepCard(
                    index: 1,
                    title: installed ? "Screen saver installed" : "Install the screen saver",
                    accent: Self.accent,
                    done: installed,
                    actionTitle: installed ? "Installed" : "Install",
                    actionDisabled: installed
                ) {
                    if installSaver() { installed = true }
                }

                StepCard(
                    index: 2,
                    title: "Select Ametrix as your screen saver",
                    accent: Self.accent,
                    done: screenSaverSettingsOpened,
                    actionTitle: screenSaverSettingsOpened ? "Open Again…" : "Open Screen Saver…",
                    actionDisabled: false,
                    action: {
                        openScreenSaverSettings()
                        screenSaverSettingsOpened = true
                    }
                )

                DailyUseStepCard(
                    accent: Self.accent,
                    wallpaperEnabled: wallpaperEnabled
                ) {
                    toggleWallpaper()
                    wallpaperEnabled = wallpaperRunning()
                }
            }
            .padding(20)

            Spacer(minLength: 0)

            footer
        }
        .frame(width: 540, height: 580)
        .background(background)
        .onAppear {
            installed = saverInstalled()
            if !installed {
                installed = installSaver()
            }
            wallpaperEnabled = wallpaperRunning()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 84, height: 84)
                    .shadow(color: Self.accent.opacity(0.4), radius: 16)
            }
            Text("Welcome to Ametrix")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.bottom, 20)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(action: finish) {
                Text("Done")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.accent)
        }
        .padding(20)
    }

    private var background: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.07, blue: 0.05),
                Color(red: 0.01, green: 0.02, blue: 0.015)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// One numbered onboarding step: badge, copy, and a trailing action button.
private struct StepCard: View {
    let index: Int
    let title: String
    let accent: Color
    let done: Bool
    let actionTitle: String
    let actionDisabled: Bool
    var action: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            badge
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Button(action: action) { Text(actionTitle) }
                    .controlSize(.regular)
                    .disabled(actionDisabled)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accent.opacity(done ? 0.5 : 0.15), lineWidth: 1)
                )
        )
    }

    private var badge: some View {
        ZStack {
            Circle().fill(done ? accent.opacity(0.18) : Color.white.opacity(0.06))
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent)
            } else {
                Text("\(index)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: 32, height: 32)
    }
}

/// Final onboarding step: optional wallpaper setup plus the global lock shortcut.
private struct DailyUseStepCard: View {
    let accent: Color
    let wallpaperEnabled: Bool
    let toggleWallpaper: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(wallpaperEnabled ? accent.opacity(0.18) : Color.white.opacity(0.06))
                Text("3")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(wallpaperEnabled ? accent : .white.opacity(0.8))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 12) {
                Text("Use Ametrix every day")
                    .font(.headline)
                    .foregroundStyle(.white)

                HStack {
                    Text("Live wallpaper")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Toggle("", isOn: wallpaperBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(accent)
                }

                Divider().overlay(Color.white.opacity(0.1))

                HStack {
                    Text("Lock shortcut")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("⌃  ⌥  ⌘  L")
                        .font(.system(.headline, design: .monospaced, weight: .bold))
                        .foregroundStyle(accent)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accent.opacity(wallpaperEnabled ? 0.5 : 0.15), lineWidth: 1)
                )
        )
    }

    private var wallpaperBinding: Binding<Bool> {
        Binding(
            get: { wallpaperEnabled },
            set: { enabled in
                guard enabled != wallpaperEnabled else { return }
                toggleWallpaper()
            }
        )
    }
}
