import AppKit
import SwiftUI

/// First-run welcome window. Walks the user through installing the screen saver
/// and pointing macOS at it, so the daily flow no longer depends on the menu bar
/// item. Reusable later via the "Setup Guide…" menu item.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    /// Installs the bundled saver. Returns `true` on success.
    private let installSaver: () -> Bool
    /// Whether `Ametrix.saver` is already installed (drives the step 1 checkmark).
    private let saverInstalled: () -> Bool
    private let openScreenSaverSettings: () -> Void
    private let openLockScreenSettings: () -> Void
    /// Called whenever the guide is dismissed (Done or close) — records that it ran.
    private let onCompleted: () -> Void
    /// Called only when the user presses Done — opens the main app window next.
    private let onProceed: () -> Void

    init(
        installSaver: @escaping () -> Bool,
        saverInstalled: @escaping () -> Bool,
        openScreenSaverSettings: @escaping () -> Void,
        openLockScreenSettings: @escaping () -> Void,
        onCompleted: @escaping () -> Void,
        onProceed: @escaping () -> Void
    ) {
        self.installSaver = installSaver
        self.saverInstalled = saverInstalled
        self.openScreenSaverSettings = openScreenSaverSettings
        self.openLockScreenSettings = openLockScreenSettings
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
            openLockScreenSettings: openLockScreenSettings,
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
        window.setContentSize(NSSize(width: 520, height: 640))
        window.center()

        self.window = window
        bringToFront(window)
    }

    private func finish() {
        onProceed()
        window?.close()
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
    let openLockScreenSettings: () -> Void
    let finish: () -> Void

    @State private var installed = false

    private static let accent = Color(red: 0.0, green: 0.95, blue: 0.37)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Self.accent.opacity(0.25))

            VStack(alignment: .leading, spacing: 14) {
                StepCard(
                    index: 1,
                    title: "Install the screen saver",
                    detail: "Copies Ametrix.saver into your Library so macOS can use it.",
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
                    detail: "Opens Wallpaper settings — click “Screen Saver…” there, then pick Ametrix.",
                    accent: Self.accent,
                    done: false,
                    actionTitle: "Open Screen Saver…",
                    actionDisabled: false,
                    action: openScreenSaverSettings
                )

                StepCard(
                    index: 3,
                    title: "Require a password on lock",
                    detail: "In System Settings → Lock Screen, require a password immediately after the screen saver begins.",
                    accent: Self.accent,
                    done: false,
                    actionTitle: "Open Lock Screen…",
                    actionDisabled: false,
                    action: openLockScreenSettings
                )
            }
            .padding(20)

            Spacer(minLength: 0)

            footer
        }
        .frame(width: 520, height: 640)
        .background(background)
        .onAppear { installed = saverInstalled() }
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
            Text("Matrix rain as your screen saver and lock screen.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.bottom, 20)
    }

    private var footer: some View {
        HStack {
            Text("You can reopen this from the menu bar → Setup Guide.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
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
    let detail: String
    let accent: Color
    let done: Bool
    let actionTitle: String
    let actionDisabled: Bool
    var action: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            badge
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: action) { Text(actionTitle) }
                    .controlSize(.regular)
                    .disabled(actionDisabled)
                    .padding(.top, 4)
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
