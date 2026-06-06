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

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    var openConfigFile: () -> Void
    var setup: SettingsSetupActions?

    @State private var saverInstalled = false
    @State private var wallpaperRunning = false

    private let presetOptions = AmetrixConfiguration.presetNames + ["custom"]

    var body: some View {
        VStack(spacing: 0) {
            RainPreview(configuration: store.configuration)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .background(Color.black)
                .accessibilityLabel("Live preview")

            Divider()

            Form {
                Section("Colours") {
                    Picker("Preset", selection: presetBinding) {
                        ForEach(presetOptions, id: \.self) { name in
                            Text(name.capitalized).tag(name)
                        }
                    }
                    ColorPicker("Background", selection: colorBinding(\.backgroundColor), supportsOpacity: false)
                    ColorPicker("Head", selection: colorBinding(\.headColor), supportsOpacity: false)
                    ColorPicker("Tail", selection: colorBinding(\.tailColor), supportsOpacity: false)
                }

                Section("Rain") {
                    sliderRow("Density", value: $store.density, range: 0.2...3.0, format: "%.2f")
                    sliderRow("Frame rate", value: $store.frameRate, range: 15...120, format: "%.0f")
                    sliderRow("Font size", value: $store.fontSize, range: 8...48, format: "%.0f")
                    sliderRow("Tail fade floor", value: $store.minimumTailAlpha, range: 0...1, format: "%.2f")
                }

                Section("Motion") {
                    sliderRow("Speed min", value: $store.speedMin, range: 1...120, format: "%.0f")
                    sliderRow("Speed max", value: $store.speedMax, range: 1...120, format: "%.0f")
                    sliderRow("Trail min", value: $store.trailMin, range: 1...80, format: "%.0f")
                    sliderRow("Trail max", value: $store.trailMax, range: 1...120, format: "%.0f")
                    sliderRow("Trail / height", value: $store.trailRowMultiplier, range: 0.1...2.0, format: "%.2f")
                }

                Section("Glyphs") {
                    TextField("Font name", text: $store.fontName)
                    TextField("Characters", text: $store.characters, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let setup {
                    Section("Setup") {
                        Button(saverInstalled ? "Reinstall Screen Saver" : "Install Screen Saver") {
                            setup.reinstallSaver()
                            saverInstalled = setup.saverInstalled()
                        }
                        Button(wallpaperRunning ? "Stop Wallpaper" : "Start Wallpaper") {
                            setup.toggleWallpaper()
                            wallpaperRunning = setup.wallpaperRunning()
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Open Config File…", action: openConfigFile)
                Spacer()
                Button("Reset to Defaults") { store.resetToDefaults() }
            }
            .padding(12)
        }
        .frame(width: 460, height: 720)
        .onAppear {
            saverInstalled = setup?.saverInstalled() ?? false
            wallpaperRunning = setup?.wallpaperRunning() ?? false
        }
    }

    /// Selecting a named preset loads its colours; choosing "custom" just records the label.
    private var presetBinding: Binding<String> {
        Binding(
            get: { store.preset },
            set: { newValue in
                if AmetrixConfiguration.presetNames.contains(newValue) {
                    store.loadPreset(newValue)
                } else {
                    store.preset = newValue
                }
            }
        )
    }

    /// Editing a colour by hand flips the preset to "custom" so the picker stays honest.
    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Color>) -> Binding<Color> {
        Binding(
            get: { store[keyPath: keyPath] },
            set: { newValue in
                store[keyPath: keyPath] = newValue
                store.preset = "custom"
            }
        )
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text(String(format: format, value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
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
