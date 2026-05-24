import Metal
import QuartzCore
import UIKit

nonisolated final class MPVNativeMetalLayer: CAMetalLayer {
    /// The most recently vended drawable. The bridge reads the rendered
    /// texture from this drawable instead of calling `nextDrawable()` itself,
    /// which would steal a blank drawable from the pool.
    var lastVendedDrawable: (any CAMetalDrawable)? {
        drawableLock.withLock { storedLastVendedDrawable }
    }

    /// A prior vended drawable reserved for diagnostics. HDR probe readback
    /// uses this instead of the current vended drawable to avoid sampling an
    /// in-flight render target.
    var lastProbeDrawable: (any CAMetalDrawable)? {
        drawableLock.withLock { storedLastProbeDrawable }
    }

    private let drawableLock = NSLock()
    private var storedLastVendedDrawable: (any CAMetalDrawable)?
    private var storedLastProbeDrawable: (any CAMetalDrawable)?

    // Work around MoltenVK temporary 1x1 drawable resizing.
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1, Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }

    // Match MPVKit's EDR activation workaround: screen HDR mode only flips
    // reliably when this property is updated on the main thread.
    override var wantsExtendedDynamicRangeContent: Bool {
        get { super.wantsExtendedDynamicRangeContent }
        set {
            if Thread.isMainThread {
                applyWantsExtendedDynamicRangeContent(newValue)
            } else {
                performSelector(
                    onMainThread: #selector(applyWantsExtendedDynamicRangeContentBoxed(_:)),
                    with: NSNumber(value: newValue),
                    waitUntilDone: true
                )
            }
        }
    }

    private func applyWantsExtendedDynamicRangeContent(_ newValue: Bool) {
        super.wantsExtendedDynamicRangeContent = newValue
    }

    @objc private func applyWantsExtendedDynamicRangeContentBoxed(_ value: NSNumber) {
        applyWantsExtendedDynamicRangeContent(value.boolValue)
    }

    override func nextDrawable() -> (any CAMetalDrawable)? {
        let drawable = super.nextDrawable()
        recordVendedDrawable(drawable)
        return drawable
    }

    private func recordVendedDrawable(_ drawable: (any CAMetalDrawable)?) {
        drawableLock.withLock {
            storedLastProbeDrawable = storedLastVendedDrawable
            storedLastVendedDrawable = drawable
        }
    }
}

final class MPVNativeMetalLayerView: UIView {
    override static var layerClass: AnyClass {
        MPVNativeMetalLayer.self
    }

    var metalLayer: CAMetalLayer {
        // swiftlint:disable:next force_cast
        layer as! CAMetalLayer  // 安全：layerClass 已声明返回 MPVNativeMetalLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.contentsScale = traitCollection.displayScale
        metalLayer.frame = bounds
        metalLayer.drawableSize = CGSize(
            width: bounds.width * contentScaleFactor,
            height: bounds.height * contentScaleFactor
        )
    }

    private func configureLayer() {
        backgroundColor = .black
        metalLayer.device = MTLCreateSystemDefaultDevice()
        // Phase-1 HDR diagnostics use an extended-linear EDR contract:
        // rgba16Float + extendedLinearDisplayP3 + wantsEDR.
        metalLayer.pixelFormat = .rgba16Float
        // Allow reading from drawable textures for panorama bridge Blit copy.
        metalLayer.framebufferOnly = false
        metalLayer.contentsScale = traitCollection.displayScale
        metalLayer.wantsExtendedDynamicRangeContent = true
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
    }
}
