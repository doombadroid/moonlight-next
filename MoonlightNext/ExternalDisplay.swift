//
//  ExternalDisplay.swift
//  MoonLume
//
//  "Video on external display": with a USB-C or AirPlay screen connected, the stream's video
//  moves to that screen and the phone keeps the touch input, on-screen controls and the
//  tabletop deck. Only the decoder's display layer moves; StreamView stays on the phone.
//  The external window stays hidden whenever no stream is routed to it, which leaves iOS
//  mirroring the phone as usual.
//  Approach adapted from VoidLink (GPLv3), SceneDelegate.m (external display scene routing).
//

import AVFoundation
import UIKit

@objc final class MNExternalDisplay: NSObject {
    @objc static let shared = MNExternalDisplay()
    static let enabledKey = "mnExternalDisplayOnly"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    private var window: UIWindow?
    private weak var streamView: UIView?
    private var notice: UILabel?
    private var aspectRatio: CGFloat = 16.0 / 9.0

    /// Pixel size of the external screen when the next stream will play there, else .zero.
    /// "Native" resolution uses it so the stream matches the screen it's shown on.
    @objc var targetPixelSize: CGSize {
        guard Self.enabled, let screen = window?.windowScene?.screen else { return .zero }
        return CGSize(width: screen.bounds.width * screen.scale, height: screen.bounds.height * screen.scale)
    }

    fileprivate func sceneConnected(_ scene: UIWindowScene) {
        let window = UIWindow(windowScene: scene)
        window.backgroundColor = .black
        let root = UIViewController()
        root.view = ExternalVideoView()
        window.rootViewController = root
        window.isHidden = true
        self.window = window
        update()
    }

    fileprivate func sceneDisconnected(_ scene: UIScene) {
        guard window?.windowScene === scene else { return }
        route(toExternal: false)
        window = nil
    }

    /// The stream's view, once its display layer exists. Moves the video out if a screen is connected.
    @objc func streamStarted(_ view: UIView, aspectRatio: CGFloat) {
        streamView = view
        self.aspectRatio = aspectRatio
        update()
    }

    @objc func streamEnded() {
        route(toExternal: false)
        streamView = nil
    }

    /// Re-applies the setting (Settings calls this when it changes mid-stream).
    @objc func update() {
        route(toExternal: Self.enabled && window != nil && streamView != nil)
    }

    private func route(toExternal: Bool) {
        defer { window?.isHidden = !toExternal }
        guard let streamView, let host = window?.rootViewController?.view else { return }
        (host as? ExternalVideoView)?.aspectRatio = aspectRatio
        let (from, to) = toExternal ? (streamView.layer, host.layer) : (host.layer, streamView.layer)
        for layer in from.sublayers ?? [] where layer is AVSampleBufferDisplayLayer {
            // Behind everything: on the phone the on-screen controls are sibling layers
            to.insertSublayer(layer, at: 0)
        }
        host.setNeedsLayout()
        streamView.setNeedsLayout()

        if toExternal, notice == nil {
            let label = UILabel()
            label.text = "Playing on the external display"
            label.textColor = UIColor(white: 1, alpha: 0.45)
            label.font = .systemFont(ofSize: 15, weight: .medium)
            label.sizeToFit()
            label.isUserInteractionEnabled = false
            label.center = CGPoint(x: streamView.bounds.midX, y: streamView.bounds.midY)
            label.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin]
            streamView.insertSubview(label, at: 0)
            notice = label
        } else if !toExternal {
            notice?.removeFromSuperview()
            notice = nil
        }
    }
}

/// Keeps the display layer aspect-fit, as StreamView does on the phone.
private final class ExternalVideoView: UIView {
    var aspectRatio: CGFloat = 16.0 / 9.0 { didSet { setNeedsLayout() } }

    override func layoutSubviews() {
        super.layoutSubviews()
        let fit = bounds.width > bounds.height * aspectRatio
            ? CGSize(width: bounds.height * aspectRatio, height: bounds.height)
            : CGSize(width: bounds.width, height: bounds.width / aspectRatio)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layer.sublayers ?? [] where layer is AVSampleBufferDisplayLayer {
            layer.bounds = CGRect(origin: .zero, size: fit)
            layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        CATransaction.commit()
    }
}

/// Scene delegate for the external-display role (Info.plist scene manifest).
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        MNExternalDisplay.shared.sceneConnected(windowScene)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        MNExternalDisplay.shared.sceneDisconnected(scene)
    }
}
