import AppKit
import CoreText
import Foundation
import MetalKit
import simd

/// GPU-composited Matrix digital rain.
///
/// All glyph rasterisation happens once, when the glyph atlas texture is baked.
/// Every frame the CPU only advances the column heads and writes a small array
/// of per-glyph instances (position + atlas UV + colour); the GPU expands those
/// into textured quads and composites them. This keeps CPU cost flat and low
/// even at high frame rates and densities, where the previous CoreText
/// full-screen redraw scaled linearly with `fps × columns × trail`.
final class MatrixRainView: MTKView {
    private struct RainColumn {
        var head: Double
        var speed: Double
        var trailLength: Int
        var glyphOffset: Int
    }

    /// Mirrors the Metal `Instance` struct (matching field order and layout).
    private struct GlyphInstance {
        var cellOrigin: SIMD2<Float>
        var cellSize: SIMD2<Float>
        var uvOrigin: SIMD2<Float>
        var uvSize: SIMD2<Float>
        var color: SIMD4<Float>
    }

    private static let inFlightFrames = 3
    private static let atlasPadding: CGFloat = 1

    private var configuration: AmetrixConfiguration
    private var rainFont: NSFont
    private var ctFont: CTFont
    private var glyphPalette: [CGGlyph] = []

    private var columns: [RainColumn] = []
    private var visibleColumnCount = 0
    private var columnCount = 0
    private var rowCount = 0
    private var cellWidth: CGFloat = 10
    private var cellHeight: CGFloat = 18
    private var atlasScale: CGFloat = 2

    // Precomputed colours; tail alpha is applied per instance.
    private var headColor: SIMD4<Float> = .init(1, 1, 1, 1)
    private var tailRGB: SIMD3<Float> = .init(0, 1, 0)

    // Metal objects.
    private let commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?
    private var atlasTexture: MTLTexture?
    private var glyphUVOrigins: [SIMD2<Float>] = []
    private var glyphUVSizes: [SIMD2<Float>] = []
    private var instanceBuffers: [MTLBuffer] = []
    private var instanceCapacity = 0
    private var bufferIndex = 0
    private let frameSemaphore = DispatchSemaphore(value: inFlightFrames)

    private var lastTimestamp: CFTimeInterval?
    private let metalAvailable: Bool

    init(frame frameRect: NSRect, configuration: AmetrixConfiguration = .load()) {
        self.configuration = configuration
        let selectedFont = NSFont(name: configuration.fontName, size: configuration.fontSize)
            ?? .monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
        self.rainFont = selectedFont
        self.ctFont = selectedFont as CTFont

        let device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()
        self.metalAvailable = device != nil

        super.init(frame: frameRect, device: device)

        configureMetalView()
        applyColors()
        calculateCellMetrics()
        glyphPalette = MatrixRainView.makeGlyphPalette(font: ctFont, characters: configuration.characters)
        buildPipeline()
        rebuildColumns()
        rebuildAtlas()
    }

    required init(coder: NSCoder) {
        let configuration = AmetrixConfiguration.load()
        self.configuration = configuration
        let selectedFont = NSFont(name: configuration.fontName, size: configuration.fontSize)
            ?? .monospacedSystemFont(ofSize: configuration.fontSize, weight: .regular)
        self.rainFont = selectedFont
        self.ctFont = selectedFont as CTFont

        let device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()
        self.metalAvailable = device != nil

        super.init(coder: coder)
        self.device = device

        configureMetalView()
        applyColors()
        calculateCellMetrics()
        glyphPalette = MatrixRainView.makeGlyphPalette(font: ctFont, characters: configuration.characters)
        buildPipeline()
        rebuildColumns()
        rebuildAtlas()
    }

    private func configureMetalView() {
        wantsLayer = true
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        autoResizeDrawable = true
        enableSetNeedsDisplay = false
        isPaused = !metalAvailable
        preferredFramesPerSecond = max(15, min(120, Int(configuration.frameRate.rounded())))
        clearColor = clearColorFromConfiguration()
        layer?.backgroundColor = configuration.backgroundColor.cgColor
    }

    /// Applies a new configuration in place, rebaking only the parts affected by
    /// the change (atlas, columns, frame rate) so live edits stay cheap.
    func update(configuration newConfiguration: AmetrixConfiguration) {
        let previous = configuration
        configuration = newConfiguration

        let fontChanged = newConfiguration.fontName != previous.fontName
            || newConfiguration.fontSize != previous.fontSize
        if fontChanged {
            let selectedFont = NSFont(name: newConfiguration.fontName, size: newConfiguration.fontSize)
                ?? .monospacedSystemFont(ofSize: newConfiguration.fontSize, weight: .regular)
            rainFont = selectedFont
            ctFont = selectedFont as CTFont
        }

        let charactersChanged = newConfiguration.characters != previous.characters
        if fontChanged || charactersChanged {
            glyphPalette = MatrixRainView.makeGlyphPalette(font: ctFont, characters: newConfiguration.characters)
        }

        applyColors()
        clearColor = clearColorFromConfiguration()
        layer?.backgroundColor = newConfiguration.backgroundColor.cgColor

        if newConfiguration.frameRate != previous.frameRate {
            preferredFramesPerSecond = max(15, min(120, Int(newConfiguration.frameRate.rounded())))
        }

        if fontChanged || newConfiguration.density != previous.density {
            calculateCellMetrics()
            rebuildColumns()
            rebuildAtlas()
        } else if fontChanged || charactersChanged {
            rebuildAtlas()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        isPaused = !metalAvailable || window == nil

        let scale = window?.backingScaleFactor ?? atlasScale
        if scale != atlasScale {
            atlasScale = scale
            rebuildAtlas()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        super.setFrameSize(newSize)
        if oldSize != newSize {
            rebuildColumns()
        }
    }

    // MARK: - Render loop

    override func draw(_ dirtyRect: NSRect) {
        guard metalAvailable,
              let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let pipelineState,
              let samplerState,
              let atlasTexture,
              let commandQueue,
              !instanceBuffers.isEmpty,
              bounds.width > 0, bounds.height > 0 else {
            return
        }

        advanceSimulation()

        frameSemaphore.wait()
        bufferIndex = (bufferIndex + 1) % MatrixRainView.inFlightFrames
        let buffer = instanceBuffers[bufferIndex]
        let instanceCount = writeInstances(into: buffer)

        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = clearColorFromConfiguration()

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            frameSemaphore.signal()
            return
        }

        if instanceCount > 0 {
            var viewport = SIMD2<Float>(Float(bounds.width), Float(bounds.height))
            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&viewport, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            encoder.setFragmentTexture(atlasTexture, index: 0)
            encoder.setFragmentSamplerState(samplerState, index: 0)
            encoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4,
                instanceCount: instanceCount
            )
        }
        encoder.endEncoding()

        commandBuffer.addCompletedHandler { [frameSemaphore] _ in
            frameSemaphore.signal()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func advanceSimulation() {
        let now = CACurrentMediaTime()
        let delta = min(now - (lastTimestamp ?? now), 1.0 / 15.0)
        lastTimestamp = now

        guard rowCount > 0 else { return }

        for index in columns.indices {
            columns[index].head += columns[index].speed * delta
            if columns[index].head - Double(columns[index].trailLength) > Double(rowCount + 4) {
                columns[index] = makeColumn(warm: false)
            }
        }
    }

    /// Fills the instance buffer with one entry per visible glyph and returns the count.
    private func writeInstances(into buffer: MTLBuffer) -> Int {
        guard rowCount > 0, !glyphPalette.isEmpty, instanceCapacity > 0 else {
            return 0
        }

        let pointer = buffer.contents().bindMemory(to: GlyphInstance.self, capacity: instanceCapacity)
        let cellSize = SIMD2<Float>(Float(cellWidth), Float(cellHeight))
        let height = Float(bounds.height)
        var count = 0

        for index in columns.indices {
            let column = columns[index]
            let headRow = Int(column.head)
            let x = Float(xPosition(for: index))
            let trail = column.trailLength

            for segment in 0..<trail {
                let row = headRow - segment
                guard row >= 0 && row < rowCount, count < instanceCapacity else {
                    continue
                }

                let paletteIndex = glyphIndexFor(column: column, row: row, segment: segment)

                let color: SIMD4<Float>
                if segment == 0 {
                    color = headColor
                } else {
                    let fade = 1.0 - (Float(segment) / Float(max(trail, 1)))
                    let alpha = max(Float(configuration.minimumTailAlpha), fade * fade)
                    color = SIMD4<Float>(tailRGB, alpha)
                }

                pointer[count] = GlyphInstance(
                    cellOrigin: SIMD2<Float>(x, height - Float(row + 1) * Float(cellHeight)),
                    cellSize: cellSize,
                    uvOrigin: glyphUVOrigins[paletteIndex],
                    uvSize: glyphUVSizes[paletteIndex],
                    color: color
                )
                count += 1
            }
        }

        return count
    }

    // MARK: - Pipeline / atlas

    private func buildPipeline() {
        guard let device else { return }

        do {
            let library = try device.makeLibrary(source: MatrixRainView.shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "rain_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: "rain_fragment")
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat

            // Premultiplied alpha over the cleared background.
            let attachment = descriptor.colorAttachments[0]!
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("MatrixRainView: failed to build Metal pipeline: \(error)")
            pipelineState = nil
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }

    /// Renders every palette glyph (white, transparent background) into a single
    /// atlas texture and records each glyph's normalised UV rect.
    private func rebuildAtlas() {
        guard let device, !glyphPalette.isEmpty else {
            atlasTexture = nil
            return
        }

        let scale = max(1, atlasScale)
        let pad = MatrixRainView.atlasPadding
        let slotW = cellWidth + 2 * pad
        let slotH = cellHeight + 2 * pad
        let count = glyphPalette.count
        let cols = max(1, Int(ceil(Double(count).squareRoot())))
        let rows = max(1, Int(ceil(Double(count) / Double(cols))))

        let atlasWpt = CGFloat(cols) * slotW
        let atlasHpt = CGFloat(rows) * slotH
        let pixelWidth = max(1, Int(ceil(atlasWpt * scale)))
        let pixelHeight = max(1, Int(ceil(atlasHpt * scale)))

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return
        }

        context.scaleBy(x: scale, y: scale)
        context.setFillColor(NSColor.white.cgColor)

        var origins = [SIMD2<Float>](repeating: .zero, count: count)
        var sizes = [SIMD2<Float>](repeating: .zero, count: count)

        for k in 0..<count {
            let col = k % cols
            let row = k / cols
            let slotBottom = atlasHpt - CGFloat(row + 1) * slotH
            let cellLeft = CGFloat(col) * slotW + pad

            var glyph = glyphPalette[k]
            var position = CGPoint(x: cellLeft, y: slotBottom + pad - rainFont.descender)
            CTFontDrawGlyphs(ctFont, &glyph, &position, 1, context)

            // UV rect of the cell region (v measured from the top of the atlas).
            let cellTopFromTop = CGFloat(row) * slotH + pad
            origins[k] = SIMD2<Float>(
                Float(cellLeft / atlasWpt),
                Float(cellTopFromTop / atlasHpt)
            )
            sizes[k] = SIMD2<Float>(
                Float(cellWidth / atlasWpt),
                Float(cellHeight / atlasHpt)
            )
        }

        glyphUVOrigins = origins
        glyphUVSizes = sizes

        guard let image = context.makeImage() else { return }
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
        ]
        atlasTexture = try? loader.newTexture(cgImage: image, options: options)
    }

    private func ensureInstanceBuffers(capacity: Int) {
        guard let device, capacity > instanceCapacity else { return }

        // Wait for in-flight frames so we can safely replace the buffers.
        for _ in 0..<MatrixRainView.inFlightFrames {
            frameSemaphore.wait()
        }
        defer {
            for _ in 0..<MatrixRainView.inFlightFrames {
                frameSemaphore.signal()
            }
        }

        let length = capacity * MemoryLayout<GlyphInstance>.stride
        instanceBuffers = (0..<MatrixRainView.inFlightFrames).compactMap {
            _ in device.makeBuffer(length: length, options: .storageModeShared)
        }
        instanceCapacity = instanceBuffers.count == MatrixRainView.inFlightFrames ? capacity : 0
    }

    // MARK: - Layout / model

    private func calculateCellMetrics() {
        let sample = "M" as NSString
        let sampleSize = sample.size(withAttributes: [.font: rainFont])
        cellWidth = max(6, ceil(sampleSize.width))
        cellHeight = max(12, ceil(rainFont.ascender - rainFont.descender + rainFont.leading + 1))
    }

    private func rebuildColumns() {
        calculateCellMetrics()

        let newVisibleColumnCount = max(1, Int(ceil(bounds.width / cellWidth)))
        let newRowCount = max(1, Int(ceil(bounds.height / cellHeight)))
        let newColumnCount = max(1, Int(ceil(Double(newVisibleColumnCount) * configuration.density)))
        guard newColumnCount != columnCount ||
            newVisibleColumnCount != visibleColumnCount ||
            newRowCount != rowCount else {
            return
        }

        visibleColumnCount = newVisibleColumnCount
        columnCount = newColumnCount
        rowCount = newRowCount
        columns = (0..<columnCount).map { _ in makeColumn(warm: true) }

        let maxTrail = min(configuration.trail.max, rowCount) + 2
        ensureInstanceBuffers(capacity: columnCount * maxTrail)
    }

    private func xPosition(for index: Int) -> CGFloat {
        guard columnCount > 1 else { return 0 }
        let maxX = max(0, CGFloat(visibleColumnCount - 1) * cellWidth)
        let progress = CGFloat(index) / CGFloat(columnCount - 1)
        return progress * maxX
    }

    private func glyphIndexFor(column: RainColumn, row: Int, segment: Int) -> Int {
        abs((column.glyphOffset &* 31) &+ (row &* 17) &+ (segment &* 7)) % glyphPalette.count
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

    private func applyColors() {
        headColor = MatrixRainView.rgba(configuration.headColor)
        let tail = MatrixRainView.rgba(configuration.tailColor)
        tailRGB = SIMD3<Float>(tail.x, tail.y, tail.z)
    }

    private func clearColorFromConfiguration() -> MTLClearColor {
        let bg = MatrixRainView.rgba(configuration.backgroundColor)
        return MTLClearColor(red: Double(bg.x), green: Double(bg.y), blue: Double(bg.z), alpha: 1)
    }

    private static func rgba(_ color: NSColor) -> SIMD4<Float> {
        let resolved = color.usingColorSpace(.sRGB) ?? color
        return SIMD4<Float>(
            Float(resolved.redComponent),
            Float(resolved.greenComponent),
            Float(resolved.blueComponent),
            Float(resolved.alphaComponent)
        )
    }

    private static func makeGlyphPalette(font: CTFont, characters: String) -> [CGGlyph] {
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

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Instance {
        float2 cellOrigin;
        float2 cellSize;
        float2 uvOrigin;
        float2 uvSize;
        float4 color;
    };

    struct VSOut {
        float4 position [[position]];
        float2 uv;
        float4 color;
    };

    vertex VSOut rain_vertex(uint vid [[vertex_id]],
                             uint iid [[instance_id]],
                             const device Instance *instances [[buffer(0)]],
                             constant float2 &viewport [[buffer(1)]]) {
        // Triangle-strip unit quad: (0,0) (1,0) (0,1) (1,1).
        float2 corner = float2(float(vid & 1), float(vid >> 1));
        Instance inst = instances[iid];

        float2 point = inst.cellOrigin + corner * inst.cellSize;
        float2 ndc = (point / viewport) * 2.0 - 1.0;

        VSOut out;
        out.position = float4(ndc, 0.0, 1.0);
        // Atlas v grows downward; quad corner y grows upward, so flip.
        out.uv = float2(inst.uvOrigin.x + corner.x * inst.uvSize.x,
                        inst.uvOrigin.y + (1.0 - corner.y) * inst.uvSize.y);
        out.color = inst.color;
        return out;
    }

    fragment float4 rain_fragment(VSOut in [[stage_in]],
                                  texture2d<float> atlas [[texture(0)]],
                                  sampler s [[sampler(0)]]) {
        float coverage = atlas.sample(s, in.uv).a;
        float alpha = in.color.a * coverage;
        return float4(in.color.rgb * alpha, alpha);
    }
    """
}
