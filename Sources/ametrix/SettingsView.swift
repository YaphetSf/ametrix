import AppKit
import Combine
import SwiftUI

/// Editable, observable mirror of `AmetrixConfiguration` that the settings UI
/// binds to. Field changes are coalesced and forwarded to `onApply` so the
/// caller can persist them and refresh any running rain.
final class SettingsStore: ObservableObject {
    @Published var preset: String = ""
    @Published var backgroundColor: Color = .black
    @Published var headColor: Color = .black
    @Published var tailColor: Color = .black
    @Published var frameRate: Double = 60
    @Published var density: Double = 1
    @Published var fontName: String = ""
    @Published var fontSize: Double = 16
    @Published var minimumTailAlpha: Double = 0.08
    @Published var speedMin: Double = 18
    @Published var speedMax: Double = 38
    @Published var trailMin: Double = 14
    @Published var trailMax: Double = 48
    @Published var trailRowMultiplier: Double = 0.75
    @Published var characters: String = ""

    let configurationPath: String

    /// Called (debounced) with the resolved configuration whenever a field changes.
    var onApply: ((AmetrixConfiguration) -> Void)?

    private var cancellable: AnyCancellable?

    init(configuration: AmetrixConfiguration, configurationPath: String) {
        self.configurationPath = configurationPath
        populate(from: configuration)

        cancellable = objectWillChange
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.onApply?(self.configuration)
            }
    }

    /// The current edits resolved back into a configuration, with ranges clamped
    /// so they always satisfy the loader's validation.
    var configuration: AmetrixConfiguration {
        let speedLow = min(speedMin, speedMax)
        let speedHigh = max(speedMin, speedMax)
        let trailLow = Int(min(trailMin, trailMax).rounded())
        let trailHigh = Int(max(trailMin, trailMax).rounded())

        return AmetrixConfiguration(
            frameRate: frameRate,
            preset: preset,
            density: density,
            fontName: fontName,
            fontSize: CGFloat(fontSize),
            backgroundColor: NSColor(backgroundColor),
            headColor: NSColor(headColor),
            tailColor: NSColor(tailColor),
            minimumTailAlpha: CGFloat(minimumTailAlpha),
            speed: AmetrixConfiguration.SpeedRange(min: speedLow, max: speedHigh),
            trail: AmetrixConfiguration.TrailRange(
                min: trailLow,
                max: trailHigh,
                rowMultiplier: trailRowMultiplier
            ),
            characters: characters
        )
    }

    /// Applies a named preset's colours without disturbing the other fields.
    func loadPreset(_ name: String) {
        let configured = AmetrixConfiguration.default.applyingPreset(name)
        preset = name
        backgroundColor = Color(nsColor: configured.backgroundColor)
        headColor = Color(nsColor: configured.headColor)
        tailColor = Color(nsColor: configured.tailColor)
    }

    func resetToDefaults() {
        populate(from: .default)
    }

    private func populate(from configuration: AmetrixConfiguration) {
        preset = configuration.preset
        backgroundColor = Color(nsColor: configuration.backgroundColor)
        headColor = Color(nsColor: configuration.headColor)
        tailColor = Color(nsColor: configuration.tailColor)
        frameRate = configuration.frameRate
        density = configuration.density
        fontName = configuration.fontName
        fontSize = Double(configuration.fontSize)
        minimumTailAlpha = Double(configuration.minimumTailAlpha)
        speedMin = configuration.speed.min
        speedMax = configuration.speed.max
        trailMin = Double(configuration.trail.min)
        trailMax = Double(configuration.trail.max)
        trailRowMultiplier = configuration.trail.rowMultiplier
        characters = configuration.characters
    }
}

/// Optional setup controls surfaced at the bottom of the preferences window:
/// reinstalling the screen saver and toggling the live wallpaper. Supplied only
/// in menu bar mode, where a wallpaper manager exists.
struct SettingsSetupActions {
    let reinstallSaver: () -> Void
    let saverInstalled: () -> Bool
    let toggleWallpaper: () -> Void
    let wallpaperRunning: () -> Bool
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case appearance
    case rain
    case motion
    case glyphs
    case setup

    var id: Self { self }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .rain: "Rain"
        case .motion: "Motion"
        case .glyphs: "Glyphs"
        case .setup: "Setup"
        }
    }

    var subtitle: String {
        switch self {
        case .appearance: "Shape the colour palette and glow."
        case .rain: "Tune the density, size, and rendering cadence."
        case .motion: "Control fall speed and trail behaviour."
        case .glyphs: "Choose the typeface and character set."
        case .setup: "Install and maintain the Ametrix screen saver."
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "paintpalette.fill"
        case .rain: "cloud.rain.fill"
        case .motion: "waveform.path"
        case .glyphs: "character.cursor.ibeam"
        case .setup: "slider.horizontal.3"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    var openConfigFile: () -> Void
    var setup: SettingsSetupActions?

    @State private var selectedPage: SettingsPage = .appearance
    @State private var saverInstalled = false
    @State private var wallpaperRunning = false

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(
                selection: $selectedPage,
                showsSetup: setup != nil,
                setup: setup,
                wallpaperRunning: $wallpaperRunning,
                openConfigFile: openConfigFile
            )

            VStack(spacing: 0) {
                SettingsPreview(configuration: store.configuration)

                SettingsDetail(
                    page: selectedPage,
                    store: store,
                    setup: setup,
                    saverInstalled: $saverInstalled
                )
            }
        }
        .frame(minWidth: 820, minHeight: 640)
        .background(AmetrixTheme.background)
        .preferredColorScheme(.dark)
        .onAppear {
            saverInstalled = setup?.saverInstalled() ?? false
            wallpaperRunning = setup?.wallpaperRunning() ?? false
        }
    }
}

private enum AmetrixTheme {
    static let accent = Color(red: 0.0, green: 0.94, blue: 0.36)
    static let background = Color(red: 0.025, green: 0.035, blue: 0.03)
    static let sidebar = Color(red: 0.035, green: 0.055, blue: 0.045)
    static let panel = Color.white.opacity(0.055)
    static let border = Color.white.opacity(0.09)
    static let secondaryText = Color.white.opacity(0.52)
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPage
    let showsSetup: Bool
    let setup: SettingsSetupActions?
    @Binding var wallpaperRunning: Bool
    let openConfigFile: () -> Void

    private var pages: [SettingsPage] {
        SettingsPage.allCases.filter { showsSetup || $0 != .setup }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AmetrixTheme.accent.opacity(0.14))
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AmetrixTheme.accent)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text("AMETRIX")
                        .font(.system(.headline, design: .monospaced, weight: .bold))
                        .tracking(1.8)
                    Text("Matrix studio")
                        .font(.caption)
                        .foregroundStyle(AmetrixTheme.secondaryText)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 24)

            VStack(spacing: 5) {
                ForEach(pages) { page in
                    SidebarButton(page: page, selected: selection == page) {
                        selection = page
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            SidebarControls(
                setup: setup,
                wallpaperRunning: $wallpaperRunning,
                openConfigFile: openConfigFile
            )
        }
        .frame(width: 205)
        .background(AmetrixTheme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AmetrixTheme.border)
                .frame(width: 1)
        }
    }
}

private struct SidebarControls: View {
    let setup: SettingsSetupActions?
    @Binding var wallpaperRunning: Bool
    let openConfigFile: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let setup {
                Toggle(isOn: wallpaperBinding(setup)) {
                    Label("Wallpaper", systemImage: wallpaperRunning ? "play.fill" : "pause.fill")
                        .font(.caption.weight(.semibold))
                }
                .toggleStyle(.switch)
                .tint(AmetrixTheme.accent)
            }

            Button(action: openConfigFile) {
                Label("Open Config File...", systemImage: "doc.text")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white.opacity(0.68))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.16))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AmetrixTheme.border)
                .frame(height: 1)
        }
    }

    private func wallpaperBinding(_ setup: SettingsSetupActions) -> Binding<Bool> {
        Binding(
            get: { wallpaperRunning },
            set: { enabled in
                guard enabled != wallpaperRunning else { return }
                setup.toggleWallpaper()
                wallpaperRunning = setup.wallpaperRunning()
            }
        )
    }
}

private struct SidebarButton: View {
    let page: SettingsPage
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: page.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
                Text(page.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .foregroundStyle(selected ? AmetrixTheme.accent : Color.white.opacity(0.68))
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? AmetrixTheme.accent.opacity(0.11) : .clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? AmetrixTheme.accent.opacity(0.2) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SettingsPreview: View {
    let configuration: AmetrixConfiguration

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RainPreview(configuration: configuration)
                .background(Color.black)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LIVE PREVIEW")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(AmetrixTheme.accent)
                    Text(configuration.preset.capitalized)
                        .font(.title2.weight(.semibold))
                }
                Spacer()
                Text("\(Int(configuration.frameRate.rounded())) FPS")
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.64))
            }
            .padding(18)
        }
        .frame(height: 230)
        .accessibilityLabel("Live matrix rain preview")
        .overlay(alignment: .bottom) {
            Rectangle().fill(AmetrixTheme.border).frame(height: 1)
        }
    }
}

private struct SettingsDetail: View {
    let page: SettingsPage
    @ObservedObject var store: SettingsStore
    let setup: SettingsSetupActions?
    @Binding var saverInstalled: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(page.title)
                        .font(.title2.weight(.semibold))
                    Text(page.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AmetrixTheme.secondaryText)
                }
                Spacer()
                Button("Reset to Defaults", action: store.resetToDefaults)
                    .buttonStyle(.borderless)
                    .foregroundStyle(AmetrixTheme.secondaryText)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 15)

            ScrollView {
                Group {
                    switch page {
                    case .appearance:
                        AppearanceSettings(store: store)
                    case .rain:
                        RainSettings(store: store)
                    case .motion:
                        MotionSettings(store: store)
                    case .glyphs:
                        GlyphSettings(store: store)
                    case .setup:
                        SetupSettings(
                            actions: setup,
                            saverInstalled: $saverInstalled
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}

private struct AppearanceSettings: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "Colour preset", detail: "Start with a palette, then fine-tune it below.") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 10)], spacing: 10) {
                    ForEach(AmetrixConfiguration.presetNames, id: \.self) { preset in
                        PresetButton(
                            name: preset,
                            selected: store.preset == preset,
                            colours: presetColours(preset)
                        ) {
                            store.loadPreset(preset)
                        }
                    }
                }
            }

            SettingsCard(title: "Palette", detail: "Changes apply to the preview and running wallpaper instantly.") {
                HStack(spacing: 12) {
                    ColourControl(title: "Background", colour: colourBinding(\.backgroundColor))
                    ColourControl(title: "Head glow", colour: colourBinding(\.headColor))
                    ColourControl(title: "Trail", colour: colourBinding(\.tailColor))
                }
            }
        }
    }

    private func presetColours(_ name: String) -> [Color] {
        let configuration = AmetrixConfiguration.default.applyingPreset(name)
        return [
            Color(nsColor: configuration.backgroundColor),
            Color(nsColor: configuration.tailColor),
            Color(nsColor: configuration.headColor)
        ]
    }

    private func colourBinding(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Color>) -> Binding<Color> {
        Binding(
            get: { store[keyPath: keyPath] },
            set: {
                store[keyPath: keyPath] = $0
                store.preset = "custom"
            }
        )
    }
}

private struct RainSettings: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        SettingsCard(title: "Rain field", detail: "Balance detail and performance for your display.") {
            VStack(spacing: 18) {
                ValueSlider(title: "Density", detail: "Number of active columns", value: $store.density, range: 0.2...3, format: "%.2f")
                ValueSlider(title: "Frame rate", detail: "Rendering target", value: $store.frameRate, range: 15...120, format: "%.0f fps")
                ValueSlider(title: "Font size", detail: "Glyph scale", value: $store.fontSize, range: 8...48, format: "%.0f pt")
                ValueSlider(title: "Tail fade floor", detail: "Minimum trail visibility", value: $store.minimumTailAlpha, range: 0...1, format: "%.2f")
            }
        }
    }
}

private struct MotionSettings: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "Fall speed", detail: "Each column chooses a speed inside this range.") {
                VStack(spacing: 18) {
                    ValueSlider(title: "Minimum", detail: "Slowest columns", value: $store.speedMin, range: 1...120, format: "%.0f")
                    ValueSlider(title: "Maximum", detail: "Fastest columns", value: $store.speedMax, range: 1...120, format: "%.0f")
                }
            }
            SettingsCard(title: "Trail length", detail: "Control how long each stream remains visible.") {
                VStack(spacing: 18) {
                    ValueSlider(title: "Minimum", detail: "Shortest trails", value: $store.trailMin, range: 1...80, format: "%.0f")
                    ValueSlider(title: "Maximum", detail: "Longest trails", value: $store.trailMax, range: 1...120, format: "%.0f")
                    ValueSlider(title: "Height response", detail: "Scale trails with display height", value: $store.trailRowMultiplier, range: 0.1...2, format: "%.2f×")
                }
            }
        }
    }
}

private struct GlyphSettings: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "Typeface", detail: "Use an installed monospaced font for the cleanest rain.") {
                TextField("Font name", text: $store.fontName)
                    .textFieldStyle(.roundedBorder)
            }
            SettingsCard(title: "Character set", detail: "Ametrix randomly draws from these characters.") {
                TextEditor(text: $store.characters)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 120)
                    .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(AmetrixTheme.border)
                    }
            }
        }
    }
}

private struct SetupSettings: View {
    let actions: SettingsSetupActions?
    @Binding var saverInstalled: Bool

    var body: some View {
        SettingsCard(title: "Screen saver", detail: "Install the bundled saver into your user Library.") {
            SetupActionRow(
                symbol: saverInstalled ? "checkmark.circle.fill" : "arrow.down.circle.fill",
                title: saverInstalled ? "Screen saver installed" : "Screen saver not installed",
                detail: saverInstalled ? "Reinstall if you update Ametrix." : "Install it before selecting Ametrix in System Settings.",
                actionTitle: saverInstalled ? "Reinstall" : "Install",
                prominent: !saverInstalled
            ) {
                actions?.reinstallSaver()
                saverInstalled = actions?.saverInstalled() ?? false
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: Content

    init(title: String, detail: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AmetrixTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AmetrixTheme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AmetrixTheme.border)
        }
    }
}

private struct PresetButton: View {
    let name: String
    let selected: Bool
    let colours: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(Array(colours.enumerated()), id: \.offset) { _, colour in
                        colour
                    }
                }
                .frame(height: 24)
                .clipShape(.rect(cornerRadius: 6))

                HStack {
                    Text(name.capitalized)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AmetrixTheme.accent)
                    }
                }
            }
            .padding(10)
            .background(Color.black.opacity(selected ? 0.28 : 0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? AmetrixTheme.accent.opacity(0.5) : AmetrixTheme.border)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ColourControl: View {
    let title: String
    @Binding var colour: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ColorPicker(title, selection: $colour, supportsOpacity: false)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(title)
                .font(.caption.weight(.medium))
            Text(NSColor(colour).ametrixHexString.uppercased())
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(AmetrixTheme.secondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ValueSlider: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AmetrixTheme.secondaryText)
            }
            .frame(width: 145, alignment: .leading)

            Slider(value: $value, in: range)
                .tint(AmetrixTheme.accent)

            Text(String(format: format, value))
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(AmetrixTheme.accent)
                .frame(width: 62, alignment: .trailing)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SetupActionRow: View {
    let symbol: String
    let title: String
    let detail: String
    let actionTitle: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(AmetrixTheme.accent)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AmetrixTheme.secondaryText)
            }
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(AmetrixActionButtonStyle(prominent: prominent))
        }
    }
}

private struct AmetrixActionButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Color.black.opacity(0.82) : AmetrixTheme.accent)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                prominent ? AmetrixTheme.accent : AmetrixTheme.accent.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(AmetrixTheme.accent.opacity(prominent ? 0 : 0.28))
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

/// Hosts the existing AppKit `MatrixRainView` so the settings window shows a live
/// preview that updates in place as the user edits.
struct RainPreview: NSViewRepresentable {
    let configuration: AmetrixConfiguration

    func makeNSView(context: Context) -> MatrixRainView {
        MatrixRainView(
            frame: NSRect(x: 0, y: 0, width: 460, height: 200),
            configuration: configuration
        )
    }

    func updateNSView(_ nsView: MatrixRainView, context: Context) {
        nsView.update(configuration: configuration)
    }
}
