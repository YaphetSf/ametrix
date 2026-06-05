import AppKit
import Darwin
import Foundation

struct AmetrixConfiguration {
    struct LoadResult {
        var configuration: AmetrixConfiguration
        var sourceURL: URL?
        var searchedURLs: [URL]
    }

    struct SpeedRange {
        var min: Double
        var max: Double
    }

    struct TrailRange {
        var min: Int
        var max: Int
        var rowMultiplier: Double
    }

    var frameRate: Double
    var preset: String
    var density: Double
    var fontName: String
    var fontSize: CGFloat
    var backgroundColor: NSColor
    var headColor: NSColor
    var tailColor: NSColor
    var minimumTailAlpha: CGFloat
    var speed: SpeedRange
    var trail: TrailRange
    var characters: String

    static let `default` = AmetrixConfiguration(
        frameRate: 60,
        preset: "classic",
        density: 1.0,
        fontName: "Menlo",
        fontSize: 16,
        backgroundColor: .black,
        headColor: NSColor(calibratedRed: 0.85, green: 1.0, blue: 0.85, alpha: 1.0),
        tailColor: NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.255, alpha: 1.0),
        minimumTailAlpha: 0.08,
        speed: SpeedRange(min: 18, max: 38),
        trail: TrailRange(min: 14, max: 48, rowMultiplier: 0.75),
        characters: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン@#$%&*+-=<>"
    )

    static func load() -> AmetrixConfiguration {
        loadWithSource().configuration
    }

    static func loadWithSource() -> LoadResult {
        let tomlURLs = tomlConfigurationURLs()
        for url in tomlURLs {
            if let raw = RawConfiguration(tomlURL: url) {
                return LoadResult(
                    configuration: raw.resolved(),
                    sourceURL: url,
                    searchedURLs: tomlURLs
                )
            }
        }

        let jsonURLs = jsonConfigurationURLs()
        for url in jsonURLs {
            guard let data = try? Data(contentsOf: url),
                  let raw = try? JSONDecoder().decode(RawConfiguration.self, from: data) else {
                continue
            }

            return LoadResult(
                configuration: raw.resolved(),
                sourceURL: url,
                searchedURLs: tomlURLs + jsonURLs
            )
        }

        return LoadResult(
            configuration: .default,
            sourceURL: nil,
            searchedURLs: tomlURLs + jsonURLs
        )
    }

    static func tomlConfigurationURL() -> URL {
        tomlConfigurationURLs()[0]
    }

    static func tomlConfigurationURLs() -> [URL] {
        configurationURLs(fileName: "config.toml")
    }

    static func jsonConfigurationURL() -> URL {
        jsonConfigurationURLs()[0]
    }

    static func jsonConfigurationURLs() -> [URL] {
        configurationURLs(fileName: "config.json")
    }

    private static func configurationURLs(fileName: String) -> [URL] {
        let homes = homeDirectoryCandidates()
        let applicationSupport = homes.map {
            $0
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("Ametrix", isDirectory: true)
                .appendingPathComponent(fileName, isDirectory: false)
        }
        let dotConfig = homes.map {
            $0
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("ametrix", isDirectory: true)
                .appendingPathComponent(fileName, isDirectory: false)
        }

        return deduplicatedURLs(applicationSupport + dotConfig)
    }

    static func screenSaverContainerConfigurationURL(fileName: String = "config.toml") -> URL? {
        guard let home = realUserHomeDirectory() else {
            return nil
        }

        return screenSaverContainerHomeDirectory(realHome: home)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Ametrix", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private static func homeDirectoryCandidates() -> [URL] {
        var homes: [URL] = []

        if let realHome = realUserHomeDirectory() {
            homes.append(realHome)
            homes.append(screenSaverContainerHomeDirectory(realHome: realHome))
        }

        homes.append(FileManager.default.homeDirectoryForCurrentUser)

        return deduplicatedURLs(homes)
    }

    private static func realUserHomeDirectory() -> URL? {
        guard let passwd = getpwuid(getuid()),
              let directory = passwd.pointee.pw_dir else {
            return nil
        }

        return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    }

    private static func screenSaverContainerHomeDirectory(realHome: URL) -> URL {
        realHome
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent("com.apple.ScreenSaver.Engine.legacyScreenSaver", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
    }

    private static func deduplicatedURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var result: [URL] = []

        for url in urls {
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted {
                result.append(url)
            }
        }

        return result
    }
}

private struct RawConfiguration: Decodable {
    struct RawSpeedRange: Decodable {
        var min: Double?
        var max: Double?
    }

    struct RawTrailRange: Decodable {
        var min: Int?
        var max: Int?
        var rowMultiplier: Double?
    }

    var frameRate: Double?
    var preset: String?
    var density: Double?
    var fontName: String?
    var fontSize: Double?
    var backgroundColor: String?
    var headColor: String?
    var tailColor: String?
    var minimumTailAlpha: Double?
    var speed: RawSpeedRange?
    var trail: RawTrailRange?
    var characters: String?

    init(
        frameRate: Double? = nil,
        preset: String? = nil,
        density: Double? = nil,
        fontName: String? = nil,
        fontSize: Double? = nil,
        backgroundColor: String? = nil,
        headColor: String? = nil,
        tailColor: String? = nil,
        minimumTailAlpha: Double? = nil,
        speed: RawSpeedRange? = nil,
        trail: RawTrailRange? = nil,
        characters: String? = nil
    ) {
        self.frameRate = frameRate
        self.preset = preset
        self.density = density
        self.fontName = fontName
        self.fontSize = fontSize
        self.backgroundColor = backgroundColor
        self.headColor = headColor
        self.tailColor = tailColor
        self.minimumTailAlpha = minimumTailAlpha
        self.speed = speed
        self.trail = trail
        self.characters = characters
    }

    init?(tomlURL: URL) {
        guard let text = try? String(contentsOf: tomlURL, encoding: .utf8) else {
            return nil
        }

        self.init()
        var section = ""

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.removingTomlComment().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            let parts = line.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2 else {
                continue
            }

            setTomlValue(key: parts[0], value: parts[1], section: section)
        }
    }

    func resolved() -> AmetrixConfiguration {
        var configuration = AmetrixConfiguration.default

        if let preset {
            configuration.applyPreset(preset)
        }

        if let frameRate, frameRate >= 15, frameRate <= 120 {
            configuration.frameRate = frameRate
        }

        if let density, density >= 0.2, density <= 3.0 {
            configuration.density = density
        }

        if let fontName, !fontName.isEmpty {
            configuration.fontName = fontName
        }

        if let fontSize, fontSize >= 8, fontSize <= 48 {
            configuration.fontSize = CGFloat(fontSize)
        }

        if let backgroundColor = NSColor(hexString: backgroundColor) {
            configuration.backgroundColor = backgroundColor
        }

        if let headColor = NSColor(hexString: headColor) {
            configuration.headColor = headColor
        }

        if let tailColor = NSColor(hexString: tailColor) {
            configuration.tailColor = tailColor
        }

        if let minimumTailAlpha, minimumTailAlpha >= 0, minimumTailAlpha <= 1 {
            configuration.minimumTailAlpha = CGFloat(minimumTailAlpha)
        }

        if let speed {
            let minSpeed = speed.min ?? configuration.speed.min
            let maxSpeed = speed.max ?? configuration.speed.max
            if minSpeed > 0, maxSpeed >= minSpeed, maxSpeed <= 120 {
                configuration.speed = AmetrixConfiguration.SpeedRange(min: minSpeed, max: maxSpeed)
            }
        }

        if let trail {
            let minTrail = trail.min ?? configuration.trail.min
            let maxTrail = trail.max ?? configuration.trail.max
            let rowMultiplier = trail.rowMultiplier ?? configuration.trail.rowMultiplier
            if minTrail > 0, maxTrail >= minTrail, rowMultiplier > 0, rowMultiplier <= 2 {
                configuration.trail = AmetrixConfiguration.TrailRange(
                    min: minTrail,
                    max: maxTrail,
                    rowMultiplier: rowMultiplier
                )
            }
        }

        if let characters, !characters.isEmpty {
            configuration.characters = characters
        }

        return configuration
    }

    private mutating func setTomlValue(key: String, value: String, section: String) {
        switch (section, key) {
        case ("", "frameRate"):
            frameRate = Double(value)
        case ("", "preset"):
            preset = value.tomlStringValue
        case ("", "density"):
            density = Double(value)
        case ("", "fontName"):
            fontName = value.tomlStringValue
        case ("", "fontSize"):
            fontSize = Double(value)
        case ("", "backgroundColor"):
            backgroundColor = value.tomlStringValue
        case ("", "headColor"):
            headColor = value.tomlStringValue
        case ("", "tailColor"):
            tailColor = value.tomlStringValue
        case ("", "minimumTailAlpha"):
            minimumTailAlpha = Double(value)
        case ("", "characters"):
            characters = value.tomlStringValue
        case ("speed", "min"):
            speed = RawSpeedRange(min: Double(value), max: speed?.max)
        case ("speed", "max"):
            speed = RawSpeedRange(min: speed?.min, max: Double(value))
        case ("trail", "min"):
            trail = RawTrailRange(min: Int(value), max: trail?.max, rowMultiplier: trail?.rowMultiplier)
        case ("trail", "max"):
            trail = RawTrailRange(min: trail?.min, max: Int(value), rowMultiplier: trail?.rowMultiplier)
        case ("trail", "rowMultiplier"):
            trail = RawTrailRange(min: trail?.min, max: trail?.max, rowMultiplier: Double(value))
        default:
            return
        }
    }
}

private extension AmetrixConfiguration {
    mutating func applyPreset(_ preset: String) {
        switch preset.lowercased() {
        case "classic":
            self.preset = "classic"
            backgroundColor = .black
            headColor = NSColor(calibratedRed: 0.85, green: 1.0, blue: 0.85, alpha: 1.0)
            tailColor = NSColor(calibratedRed: 0.0, green: 1.0, blue: 0.255, alpha: 1.0)
        case "amber":
            self.preset = "amber"
            backgroundColor = .black
            headColor = NSColor(calibratedRed: 1.0, green: 0.91, blue: 0.62, alpha: 1.0)
            tailColor = NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.12, alpha: 1.0)
        case "cyan":
            self.preset = "cyan"
            backgroundColor = .black
            headColor = NSColor(calibratedRed: 0.82, green: 1.0, blue: 1.0, alpha: 1.0)
            tailColor = NSColor(calibratedRed: 0.0, green: 0.86, blue: 1.0, alpha: 1.0)
        case "white":
            self.preset = "white"
            backgroundColor = .black
            headColor = NSColor(calibratedWhite: 1.0, alpha: 1.0)
            tailColor = NSColor(calibratedWhite: 0.78, alpha: 1.0)
        case "violet":
            self.preset = "violet"
            backgroundColor = .black
            headColor = NSColor(calibratedRed: 0.96, green: 0.86, blue: 1.0, alpha: 1.0)
            tailColor = NSColor(calibratedRed: 0.72, green: 0.25, blue: 1.0, alpha: 1.0)
        default:
            return
        }
    }
}

private extension String {
    var tomlStringValue: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2,
              value.first == "\"",
              value.last == "\"" else {
            return nil
        }

        return String(value.dropFirst().dropLast())
    }

    func removingTomlComment() -> String {
        var isInString = false
        var result = ""

        for character in self {
            if character == "\"" {
                isInString.toggle()
            }

            if character == "#", !isInString {
                break
            }

            result.append(character)
        }

        return result
    }
}

extension NSColor {
    var ametrixHexString: String {
        let color = usingColorSpace(.deviceRGB) ?? self
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    convenience init?(hexString: String?) {
        guard let hexString else {
            return nil
        }

        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        guard value.count == 6,
              let integer = Int(value, radix: 16) else {
            return nil
        }

        let red = CGFloat((integer >> 16) & 0xff) / 255.0
        let green = CGFloat((integer >> 8) & 0xff) / 255.0
        let blue = CGFloat(integer & 0xff) / 255.0
        self.init(calibratedRed: red, green: green, blue: blue, alpha: 1.0)
    }
}
