import Metal
import QuartzCore
import UIKit

final class MPVNativeMetalLayer: CAMetalLayer {
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
                super.wantsExtendedDynamicRangeContent = newValue
            } else {
                DispatchQueue.main.sync {
                    super.wantsExtendedDynamicRangeContent = newValue
                }
            }
        }
    }
}

final class MPVNativeMetalLayerView: UIView {
    override class var layerClass: AnyClass {
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
        // Use rgba16Float for HDR passthrough capability.
        // Falls back gracefully on devices that don't support EDR.
        metalLayer.pixelFormat = .rgba16Float
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = traitCollection.displayScale
        metalLayer.wantsExtendedDynamicRangeContent = true
    }
}
