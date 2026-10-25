//
//  PictureInPicture.swift
//  MoonLume
//
//  Picture in picture for a running stream. The decoder's AVSampleBufferDisplayLayer is the
//  PiP source, so leaving the app (home swipe, app switch) floats the stream instead of
//  ending it. While PiP is up the app is in the background, where the display link that
//  normally pulls frames stops firing, so a timer pulls them instead. Closing the PiP window
//  from the background ends the stream; the restore button brings the full view back.
//

import AVKit
import UIKit
import os

@objc final class MNPictureInPicture: NSObject {
    @objc static let shared = MNPictureInPicture()

    /// Settings › Video › Picture in picture (on unless turned off)
    @objc static var enabled: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
            && (UserDefaults.standard.object(forKey: "mnPictureInPicture") as? Bool ?? true)
    }

    /// Pulls pending frames into the display layer; set by the renderer.
    @objc var pump: (() -> Void)?
    /// Called on the main thread when PiP is closed while the app is in the background. Set and
    /// cleared by the stream on the main thread.
    @objc var onClosedInBackground: (() -> Void)?
    /// Called on the main thread when PiP fails to start while the app is in the background.
    @objc var onFailedInBackground: (() -> Void)?

    /// True from the moment PiP starts opening until it has fully closed.
    @objc private(set) var isActive = false

    private var controller: AVPictureInPictureController?
    private weak var layer: AVSampleBufferDisplayLayer?
    private var pumpTimer: Timer?
    private var restoring = false
    private var possibleObservation: NSKeyValueObservation?
    private let log = Logger(subsystem: "com.doombadroid.moonlume", category: "pip")

    /// Called whenever the renderer creates a display layer (the first one and any replacement).
    /// The renderer calls in from stream threads, so the work hops to the main thread.
    @objc func attach(_ layer: AVSampleBufferDisplayLayer, frameRate: Int) {
        DispatchQueue.main.async { self.attachOnMain(layer, frameRate: frameRate) }
    }

    private func attachOnMain(_ layer: AVSampleBufferDisplayLayer, frameRate: Int) {
        guard MNPictureInPicture.enabled, layer !== self.layer else { return }
        self.layer = layer
        self.frameRate = max(frameRate, 30)
        if let controller {
            controller.contentSource = .init(sampleBufferDisplayLayer: layer, playbackDelegate: self)
        } else {
            let controller = AVPictureInPictureController(contentSource: .init(sampleBufferDisplayLayer: layer, playbackDelegate: self))
            controller.delegate = self
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            controller.requiresLinearPlayback = true
            possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [log] c, _ in
                log.info("PiP possible: \(c.isPictureInPicturePossible)")
            }
            self.controller = controller
        }
    }
    private var frameRate = 60

    /// True when the stream menu can open picture in picture by hand.
    @objc var canStart: Bool { controller?.isPictureInPicturePossible == true && !isActive }

    /// Opens picture in picture from the stream menu. Works with "Let other apps keep playing"
    /// on too, where iOS won't start it automatically on leaving the app.
    @objc func start() {
        controller?.startPictureInPicture()
    }

    /// Settings › Picture in picture changed mid-stream: arm or disarm the automatic start.
    @objc func settingChanged() {
        controller?.canStartPictureInPictureAutomaticallyFromInline = MNPictureInPicture.enabled
    }

    /// Called when the stream ends.
    @objc func detach() {
        DispatchQueue.main.async { self.detachOnMain() }
    }

    private func detachOnMain() {
        controller?.stopPictureInPicture()
        stopPump()
        possibleObservation = nil
        controller = nil
        layer = nil
        isActive = false
        restoring = false
    }

    private func startPump() {
        guard pumpTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / Double(frameRate), repeats: true) { [weak self] _ in self?.pump?() }
        RunLoop.main.add(timer, forMode: .common)
        pumpTimer = timer
    }

    private func stopPump() {
        pumpTimer?.invalidate()
        pumpTimer = nil
    }
}

extension MNPictureInPicture: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ c: AVPictureInPictureController) {
        // A controller detached with an earlier stream may still report in
        guard c === controller else { return }
        log.info("PiP starting")
        isActive = true
        restoring = false
        startPump()
    }

    func pictureInPictureController(_ c: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        guard c === controller else { return }
        log.error("PiP failed: \(error.localizedDescription)")
        isActive = false
        stopPump()
        if UIApplication.shared.applicationState == .background { onFailedInBackground?() }
    }

    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void) {
        restoring = true
        completion(true)
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        guard c === controller else { return }
        log.info("PiP stopped, restoring: \(self.restoring)")
        isActive = false
        stopPump()
        if !restoring, UIApplication.shared.applicationState == .background { onClosedInBackground?() }
        restoring = false
    }
}

extension MNPictureInPicture: AVPictureInPictureSampleBufferPlaybackDelegate {
    // A live stream: always playing, no seeking, no timeline
    func pictureInPictureController(_ c: AVPictureInPictureController, setPlaying playing: Bool) {}
    func pictureInPictureControllerTimeRangeForPlayback(_ c: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(_ c: AVPictureInPictureController) -> Bool { false }
    func pictureInPictureController(_ c: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    func pictureInPictureController(_ c: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                    completion completionHandler: @escaping () -> Void) { completionHandler() }
}
