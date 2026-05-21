import AVFoundation
import SwiftUI
import UIKit

final class AVReferencePlayerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        // swiftlint:disable:next force_cast
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    func configure(player: AVPlayer?) {
        if playerLayer.player !== player {
            playerLayer.player = player
        }
    }

    private func configureLayer() {
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = UIColor.black.cgColor
    }
}

struct AppleReferenceVideoSurface: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> AVReferencePlayerView {
        let view = AVReferencePlayerView()
        view.configure(player: player)
        return view
    }

    func updateUIView(_ view: AVReferencePlayerView, context: Context) {
        view.configure(player: player)
    }
}
