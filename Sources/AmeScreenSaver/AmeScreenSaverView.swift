import AppKit
import ScreenSaver

@objc(AmeScreenSaverView)
final class AmeScreenSaverView: ScreenSaverView {
    private var rainView: MatrixRainView?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setupRainView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupRainView()
    }

    override func startAnimation() {
        super.startAnimation()
        ensureRainView()
    }

    override func stopAnimation() {
        super.stopAnimation()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        rainView?.frame = bounds
    }

    private func setupRainView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 1.0 / 60.0
        ensureRainView()
    }

    private func ensureRainView() {
        guard rainView == nil else {
            return
        }

        let rainView = MatrixRainView(
            frame: bounds,
            configuration: .load()
        )
        rainView.autoresizingMask = [.width, .height]
        addSubview(rainView)
        self.rainView = rainView
    }
}
