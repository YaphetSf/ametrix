import AppKit
import CoreText
import Foundation

final class MatrixRainView: NSView {
    private struct RainColumn {
        var head: Double
        var speed: Double
        var trailLength: Int
        var glyphOffset: Int
    }

    private let configuration: AmeConfiguration
    private let targetFrameInterval: TimeInterval
    private let font: NSFont
    private let ctFont: CTFont
    private let glyphPalette: [CGGlyph]
    private var columns: [RainColumn] = []
    private var visibleColumnCount = 0
    private var columnCount = 0
    private var rowCount = 0
    private var cellWidth: CGFloat = 10
    private var cellHeight: CGFloat = 18
    private var timer: Timer?
    private var lastFrameTime: TimeInterval?

    override var isFlipped: Bool { false }

    init(frame frameRect: NSRect, configuration: AmeConfiguration = .load()) {
        self.configuration = configuration
        self.targetFrameInterval = 1.0 / configuration.frameRate
        let selectedFont = NSFont(name: configuration.fontName, size: configuration.fontSize)
            ?? .monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
        self.font = selectedFont
        self.ctFont = selectedFont as CTFont
        self.glyphPalette = MatrixRainView.makeGlyphPalette(
            font: selectedFont as CTFont,
            characters: configuration.characters
        )
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = configuration.backgroundColor.cgColor
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        calculateCellMetrics()
        rebuildColumns()
    }

    required init?(coder: NSCoder) {
        let configuration = AmeConfiguration.load()
        self.configuration = configuration
        self.targetFrameInterval = 1.0 / configuration.frameRate
        let selectedFont = NSFont(name: configuration.fontName, size: configuration.fontSize)
            ?? .monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
        self.font = selectedFont
        self.ctFont = selectedFont as CTFont
        self.glyphPalette = MatrixRainView.makeGlyphPalette(
            font: selectedFont as CTFont,
            characters: configuration.characters
        )
        super.init(coder: coder)

        wantsLayer = true
        layer?.backgroundColor = configuration.backgroundColor.cgColor
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        calculateCellMetrics()
        rebuildColumns()
    }

    deinit {
        stopAnimating()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            stopAnimating()
        } else {
            startAnimating()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        super.setFrameSize(newSize)

        if oldSize != newSize {
            rebuildColumns()
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        context.setFillColor(configuration.backgroundColor.cgColor)
        context.fill(bounds)
        context.textMatrix = .identity
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSmoothing(false)

        for columnIndex in columns.indices {
            drawColumn(columns[columnIndex], index: columnIndex, in: context)
        }
    }

    private func startAnimating() {
        guard timer == nil else {
            return
        }

        lastFrameTime = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: targetFrameInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopAnimating() {
        timer?.invalidate()
        timer = nil
        lastFrameTime = nil
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = min(now - (lastFrameTime ?? now), 1.0 / 15.0)
        lastFrameTime = now

        step(delta: delta)
        needsDisplay = true
    }

    private func step(delta: TimeInterval) {
        guard rowCount > 0 else {
            return
        }

        for index in columns.indices {
            columns[index].head += columns[index].speed * delta

            if columns[index].head - Double(columns[index].trailLength) > Double(rowCount + 4) {
                resetColumn(index, warm: false)
            }
        }
    }

    private func drawColumn(_ column: RainColumn, index: Int, in context: CGContext) {
        guard rowCount > 0, !glyphPalette.isEmpty else {
            return
        }

        let headRow = Int(column.head)
        let x = xPosition(for: index)

        for segment in 0..<column.trailLength {
            let row = headRow - segment
            guard row >= 0 && row < rowCount else {
                continue
            }

            let fade = 1.0 - (CGFloat(segment) / CGFloat(max(column.trailLength, 1)))
            let alpha = max(configuration.minimumTailAlpha, fade * fade)
            let color: NSColor
            if segment == 0 {
                color = configuration.headColor
            } else {
                color = configuration.tailColor.withAlphaComponent(alpha)
            }

            var glyph = glyphFor(column: column, row: row, segment: segment)
            var position = CGPoint(
                x: x,
                y: bounds.height - CGFloat(row + 1) * cellHeight - font.descender
            )

            context.setFillColor(color.cgColor)
            CTFontDrawGlyphs(ctFont, &glyph, &position, 1, context)
        }
    }

    private func glyphFor(column: RainColumn, row: Int, segment: Int) -> CGGlyph {
        let paletteIndex = abs((column.glyphOffset &* 31) &+ (row &* 17) &+ (segment &* 7))
            % glyphPalette.count
        return glyphPalette[paletteIndex]
    }

    private func calculateCellMetrics() {
        let sample = "M" as NSString
        let sampleSize = sample.size(withAttributes: [.font: font])
        cellWidth = max(6, ceil(sampleSize.width))
        cellHeight = max(12, ceil(font.ascender - font.descender + font.leading + 1))
    }

    private func rebuildColumns() {
        calculateCellMetrics()

        let newColumnCount = max(1, Int(ceil(bounds.width / cellWidth)))
        let newRowCount = max(1, Int(ceil(bounds.height / cellHeight)))
        let newRainColumnCount = max(1, Int(ceil(Double(newColumnCount) * configuration.density)))
        guard newRainColumnCount != columnCount ||
            newColumnCount != visibleColumnCount ||
            newRowCount != rowCount else {
            return
        }

        visibleColumnCount = newColumnCount
        columnCount = newRainColumnCount
        rowCount = newRowCount
        columns = (0..<columnCount).map { _ in makeColumn(warm: true) }
    }

    private func xPosition(for index: Int) -> CGFloat {
        guard columnCount > 1 else {
            return 0
        }

        let maxX = max(0, CGFloat(visibleColumnCount - 1) * cellWidth)
        let progress = CGFloat(index) / CGFloat(columnCount - 1)
        return progress * maxX
    }

    private func resetColumn(_ index: Int, warm: Bool) {
        guard columns.indices.contains(index) else {
            return
        }

        columns[index] = makeColumn(warm: warm)
    }

    private func makeColumn(warm: Bool) -> RainColumn {
        let maxTrail = max(
            configuration.trail.min,
            min(configuration.trail.max, Int(Double(rowCount) * configuration.trail.rowMultiplier))
        )
        let trail = Int.random(in: configuration.trail.min...maxTrail)
        let speed = Double.random(in: configuration.speed.min...configuration.speed.max)
        let start: Double
        if warm {
            start = Double.random(in: -Double(trail)...Double(rowCount + trail))
        } else {
            start = Double.random(in: -Double(max(4, trail / 3))...0)
        }

        return RainColumn(
            head: start,
            speed: speed,
            trailLength: trail,
            glyphOffset: Int.random(in: 0...10_000)
        )
    }

    private static func makeGlyphPalette(font: CTFont, characters: String) -> [CGGlyph] {
        let characters = Array(characters)
        var glyphs: [CGGlyph] = []

        for character in characters {
            let string = String(character) as NSString
            var unichar = string.character(at: 0)
            var glyph = CGGlyph()
            if CTFontGetGlyphsForCharacters(font, &unichar, &glyph, 1), glyph != 0 {
                glyphs.append(glyph)
            }
        }

        return glyphs
    }
}
