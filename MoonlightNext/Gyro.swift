//
//  Gyro.swift
//  MoonLume
//
//  Gyro aiming: the phone's own motion drives the host's mouse or right stick, the way the
//  VoidLink fork does it. Horizontal aim is rotation about the world's vertical (taken from
//  gravity), so it doesn't matter how the phone is tilted; vertical aim is rotation about the
//  screen's horizontal axis, which on an iPhone Duo is the hinge line, so the angle between
//  the halves in the DS pose doesn't mix the axes.
//

import CoreMotion
import GameController
import UIKit

enum GyroSettings {
    enum Mode: Int { case off = 0, mouse = 1, rightStick = 2 }
    enum Activation: Int { case always = 0, whileAiming = 1 }

    static let modeKey = "mnGyroMode"
    static let activationKey = "mnGyroActivation"
    static let sensitivityKey = "mnGyroSensitivity"
    static let invertYKey = "mnGyroInvertY"
    static let pausedKey = "mnGyroPaused"

    static var mode: Mode { Mode(rawValue: UserDefaults.standard.integer(forKey: modeKey)) ?? .off }
    static var activation: Activation { Activation(rawValue: UserDefaults.standard.integer(forKey: activationKey)) ?? .always }
    static var sensitivity: Double { UserDefaults.standard.object(forKey: sensitivityKey) as? Double ?? 1.5 }
    static var invertY: Bool { UserDefaults.standard.bool(forKey: invertYKey) }
}

/// Started and stopped by StreamFrameViewController around a stream.
@objc final class MNGyro: NSObject {
    @objc static let shared = MNGyro()

    /// Host mouse pixels per radian at sensitivity 1.
    private let mousePixelsPerRadian = 800.0
    /// Stick deflection per rad/s at sensitivity 1 (full deflection at ~1.2 rad/s ≈ 70°/s).
    private let stickPerRadianPerSecond = 0.8
    /// Below this rate the phone is treated as still, so hand tremor doesn't drift the aim.
    private let deadZone = 0.015

    private let motion = CMMotionManager()
    private weak var view: UIView?
    private var remainder = (x: 0.0, y: 0.0)
    private var stickActive = false

    /// Shown in the stream menu only when gyro is set up in Settings.
    @objc static var isConfigured: Bool { GyroSettings.mode != .off }

    @objc static var isPaused: Bool {
        get { UserDefaults.standard.bool(forKey: GyroSettings.pausedKey) }
        set { UserDefaults.standard.set(newValue, forKey: GyroSettings.pausedKey) }
    }

    @objc func start(in view: UIView) {
        self.view = view
        guard GyroSettings.mode != .off, motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 120.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] sample, _ in
            guard let self, let sample else { return }
            self.handle(sample)
        }
    }

    @objc func stop() {
        motion.stopDeviceMotionUpdates()
        releaseStick()
        remainder = (0, 0)
    }

    private func handle(_ sample: CMDeviceMotion) {
        let mode = GyroSettings.mode
        guard mode != .off, !MNGyro.isPaused, isActive() else {
            releaseStick()
            return
        }

        let r = sample.rotationRate
        let g = sample.gravity
        let gLength = max((g.x * g.x + g.y * g.y + g.z * g.z).squareRoot(), 0.0001)
        // Rotation about world up (-gravity): positive is turning left, so negate for "right"
        var horizontal = -(r.x * -g.x + r.y * -g.y + r.z * -g.z) / gLength
        // Rotation about the screen's right-pointing axis: positive tips the top edge toward
        // the player, which aims down (screen y grows downward)
        let axis = screenRightAxis()
        var vertical = r.x * axis.x + r.y * axis.y
        if GyroSettings.invertY { vertical = -vertical }
        if abs(horizontal) < deadZone { horizontal = 0 }
        if abs(vertical) < deadZone { vertical = 0 }

        let sensitivity = GyroSettings.sensitivity
        switch mode {
        case .mouse:
            let dt = motion.deviceMotionUpdateInterval
            let dx = horizontal * dt * mousePixelsPerRadian * sensitivity + remainder.x
            let dy = vertical * dt * mousePixelsPerRadian * sensitivity + remainder.y
            let sx = dx.rounded(.towardZero), sy = dy.rounded(.towardZero)
            remainder = (dx - sx, dy - sy)
            MNInput.mouseMoveX(Int16(clamping: Int(sx)), y: Int16(clamping: Int(sy)))
        case .rightStick:
            let k = stickPerRadianPerSecond * sensitivity
            let x = max(-1, min(1, horizontal * k))
            let y = max(-1, min(1, -vertical * k)) // stick y is up-positive
            MNInput.gamepadRightStickX(Int16(x * 32767), y: Int16(y * 32767))
            stickActive = true
        case .off:
            break
        }
    }

    /// "While aiming": L2 / left trigger held on the on-screen controls, the deck or a
    /// connected controller.
    private func isActive() -> Bool {
        guard GyroSettings.activation == .whileAiming else { return true }
        if MNInput.aimTriggerHeld() { return true }
        return GCController.controllers().contains { $0.extendedGamepad?.leftTrigger.isPressed == true }
    }

    private func releaseStick() {
        guard stickActive else { return }
        stickActive = false
        MNInput.gamepadRightStickX(0, y: 0)
    }

    /// The screen's rightward direction in the device's own (portrait) axes.
    private func screenRightAxis() -> (x: Double, y: Double) {
        // UIInterfaceOrientation.landscapeLeft has the home edge on the left, so the device's
        // top (+y) points right; landscapeRight is the reverse
        switch view?.window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: return (0, 1)
        case .landscapeRight: return (0, -1)
        case .portraitUpsideDown: return (-1, 0)
        default: return (1, 0)
        }
    }
}
