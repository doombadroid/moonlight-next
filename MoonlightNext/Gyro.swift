//
//  Gyro.swift
//  MoonLume
//
//  The phone's motion sensors during a stream, from one CMMotionManager:
//  - Gyro aiming: the phone (or a controller's gyro) drives the host's mouse or right stick.
//    Horizontal aim is rotation about the world's vertical (taken from gravity), so it doesn't
//    matter how the phone is tilted; vertical aim is rotation about the screen's horizontal axis,
//    which on an iPhone Duo is the hinge line, so the angle between the halves in the DS pose
//    doesn't mix the axes.
//  - Tilt to steer: the phone's roll, like a steering wheel, drives the left stick.
//  - Host motion: when player 1 is reported as a PlayStation pad, the host asks for gyro and
//    accelerometer samples and gets the phone's, turned into the controller's axes.
//

import CoreMotion
import GameController
import UIKit

enum GyroSettings {
    enum Mode: Int { case off = 0, mouse = 1, rightStick = 2 }
    enum Activation: Int { case always = 0, whileAiming = 1 }
    enum Source: Int { case phone = 0, controller = 1 }
    enum Button: Int, CaseIterable {
        case none = 0, leftShoulder, rightShoulder, leftStick, rightStick, touchpad, paddle

        var label: String {
            switch self {
            case .none: return "None"
            case .leftShoulder: return "L1 / LB"
            case .rightShoulder: return "R1 / RB"
            case .leftStick: return "L3"
            case .rightStick: return "R3"
            case .touchpad: return "Touchpad click"
            case .paddle: return "Back paddle 1"
            }
        }

        func input(on pad: GCExtendedGamepad) -> GCControllerButtonInput? {
            switch self {
            case .none: return nil
            case .leftShoulder: return pad.leftShoulder
            case .rightShoulder: return pad.rightShoulder
            case .leftStick: return pad.leftThumbstickButton
            case .rightStick: return pad.rightThumbstickButton
            case .touchpad: return (pad as? GCDualSenseGamepad)?.touchpadButton ?? (pad as? GCDualShockGamepad)?.touchpadButton
            case .paddle: return (pad as? GCXboxGamepad)?.paddleButton1
            }
        }
    }
    enum ButtonMode: Int { case hold = 0, toggle = 1, holdToPause = 2 }

    static let modeKey = "mnGyroMode"
    static let activationKey = "mnGyroActivation"
    static let sensitivityKey = "mnGyroSensitivity"
    static let invertYKey = "mnGyroInvertY"
    static let pausedKey = "mnGyroPaused"
    static let sourceKey = "mnGyroSource"
    static let sensitivityXKey = "mnGyroSensitivityX"
    static let sensitivityYKey = "mnGyroSensitivityY"
    static let minStickKey = "mnGyroMinStick"
    static let steeringKey = "mnGyroSteering"
    static let steeringSensitivityKey = "mnGyroSteeringSensitivity"
    static let buttonKey = "mnGyroButton"
    static let buttonModeKey = "mnGyroButtonMode"
    static let phoneBiasKey = "mnGyroPhoneBias"
    static let controllerBiasKey = "mnGyroControllerBias"

    private static var defaults: UserDefaults { .standard }
    private static func double(_ key: String, _ fallback: Double) -> Double { defaults.object(forKey: key) as? Double ?? fallback }

    static var mode: Mode { Mode(rawValue: defaults.integer(forKey: modeKey)) ?? .off }
    static var activation: Activation { Activation(rawValue: defaults.integer(forKey: activationKey)) ?? .always }
    static var source: Source { Source(rawValue: defaults.integer(forKey: sourceKey)) ?? .phone }
    static var sensitivity: Double { double(sensitivityKey, 1.5) }
    static var sensitivityX: Double { double(sensitivityXKey, 1) }
    static var sensitivityY: Double { double(sensitivityYKey, 1) }
    static var invertY: Bool { defaults.bool(forKey: invertYKey) }
    /// Anti-deadzone: smallest stick deflection gyro sends, so tiny turns get past a game's deadzone (0...0.5)
    static var minStick: Double { double(minStickKey, 0) }
    static var steering: Bool { defaults.bool(forKey: steeringKey) }
    static var steeringSensitivity: Double { double(steeringSensitivityKey, 1) }
    static var button: Button { Button(rawValue: defaults.integer(forKey: buttonKey)) ?? .none }
    static var buttonMode: ButtonMode { ButtonMode(rawValue: defaults.integer(forKey: buttonModeKey)) ?? .hold }

    /// Drift measured by "Calibrate", in rad/s on the sensor's own axes
    static func bias(_ key: String) -> (x: Double, y: Double, z: Double) {
        let v = defaults.array(forKey: key) as? [Double] ?? []
        return v.count == 3 ? (v[0], v[1], v[2]) : (0, 0, 0)
    }
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
    /// Roll that turns the left stick fully at steering sensitivity 1.
    private let fullLockRadians = Double.pi / 4

    private let motion = CMMotionManager()
    private var timer: Timer?
    private weak var view: UIView?
    private var streaming = false
    private var calibrating = false
    private var defaultsObserver: NSObjectProtocol?
    private var lastTick = 0.0
    private var remainder = (x: 0.0, y: 0.0)
    private var stickActive = false
    private var steerActive = false
    private var lastSteer: Int16 = 0
    /// Gyro button: last state, and the toggle's current state
    private var buttonWasDown = false
    private var toggledOn = true
    /// Report rate the host asked for, per LI_MOTION_TYPE (1 accel, 2 gyro); 0 = stopped
    private var hostRate: [UInt8: UInt16] = [:]
    private var lastHostSample = 0.0
    /// Samples collected by calibrate()
    private var calibrationPhone: [CMRotationRate] = []
    private var calibrationController: [GCRotationRate] = []

    private static let accelType: UInt8 = 1
    private static let gyroType: UInt8 = 2

    /// Shown in the stream menu ("Pause Gyro") only when something uses the gyro.
    @objc static var isConfigured: Bool {
        GyroSettings.mode != .off || GyroSettings.steering || (shared.hostRate[gyroType] ?? 0) > 0 || shared.aimWidgetShown
    }

    // MARK: On-screen gyro buttons

    /// The layout has a hold-to-aim gyro button: aiming then only runs while it's held.
    var aimWidgetShown = false {
        didSet { if aimWidgetShown != oldValue { refresh() } }
    }
    /// Axis factors of the gyro button being held, nil when none is
    var widgetAim: (x: Double, y: Double)? {
        didSet { refresh() }
    }
    /// Gyro pause buttons held: aim stops so the phone can be re-centred
    var widgetPauses = 0

    /// Aiming target: Settings › Gyro, or the right stick when only a gyro button turns it on
    private var aimMode: GyroSettings.Mode {
        GyroSettings.mode != .off ? GyroSettings.mode : (aimWidgetShown ? .rightStick : .off)
    }

    @objc static var isPaused: Bool {
        get { UserDefaults.standard.bool(forKey: GyroSettings.pausedKey) }
        set { UserDefaults.standard.set(newValue, forKey: GyroSettings.pausedKey) }
    }

    /// Gyro aiming reads a controller's own gyro, so ControllerSupport must leave its sensors on.
    @objc static var wantsControllerSensors: Bool {
        shared.streaming && shared.aimMode != .off && GyroSettings.source == .controller
    }

    @objc func start(in view: UIView) {
        self.view = view
        streaming = true
        toggledOn = true
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    @objc func stop() {
        streaming = false
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        defaultsObserver = nil
        hostRate = [:]
        refresh()
        remainder = (0, 0)
    }

    /// The host started (rate > 0) or stopped motion reports for player 1, which ControllerSupport
    /// backs with the phone's sensors. Called on the connection's thread.
    @objc(setHostMotionWithType:rateHz:) func setHostMotion(type: UInt8, rateHz: UInt16) {
        DispatchQueue.main.async {
            guard self.streaming else { return }
            self.hostRate[type] = rateHz
            self.refresh()
        }
    }

    // MARK: Sensor and timer lifetime

    private var hostWantsMotion: Bool { hostRate.values.contains { $0 > 0 } }

    /// Start or stop the phone's sensors and the sampling timer to match what's in use.
    private func refresh() {
        let aiming = aimMode != .off
        let needsPhone = streaming && ((aiming && GyroSettings.source == .phone) || GyroSettings.steering || hostWantsMotion)
        if (needsPhone || calibrating), motion.isDeviceMotionAvailable {
            if !motion.isDeviceMotionActive {
                motion.deviceMotionUpdateInterval = 1.0 / 120.0
                motion.startDeviceMotionUpdates()
            }
        } else if motion.isDeviceMotionActive {
            motion.stopDeviceMotionUpdates()
        }

        if MNGyro.wantsControllerSensors {
            for controller in GCController.controllers() where controller.motion?.sensorsRequireManualActivation == true {
                controller.motion?.sensorsActive = true
            }
        }

        let needsTick = streaming && (aiming || GyroSettings.steering || hostWantsMotion)
        // Sample at the host's rate when it asks for more than 120 Hz (CoreMotion tops out near 200)
        let interval = 1.0 / Double(min(max(hostRate.values.max() ?? 0, 120), 200))
        if needsTick {
            if timer?.timeInterval != interval {
                timer?.invalidate()
                let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
                RunLoop.main.add(t, forMode: .common)
                timer = t
                lastTick = 0
            }
        } else {
            timer?.invalidate()
            timer = nil
            releaseSticks()
        }
    }

    private func tick() {
        guard UIApplication.shared.applicationState == .active else {
            // In the background (kept alive, picture in picture) the phone moving in a pocket
            // mustn't aim or steer: let go once and wait
            releaseSticks()
            remainder = (0, 0)
            lastTick = 0
            return
        }
        let now = CACurrentMediaTime()
        let dt = lastTick > 0 ? min(now - lastTick, 0.05) : 0
        lastTick = now
        let device = motion.deviceMotion
        let buttonAllows = pollGyroButton()

        if let device, hostWantsMotion {
            sendHostMotion(device, gyroOn: buttonAllows && !MNGyro.isPaused)
        }
        aim(device, dt: dt, buttonAllows: buttonAllows)
        steer(device)
    }

    // MARK: Host motion

    /// The screen's right and down directions in the device's own (portrait) axes.
    private func screenAxes() -> (right: (x: Double, y: Double), down: (x: Double, y: Double)) {
        // UIInterfaceOrientation.landscapeLeft has the home edge on the left, so the device's
        // top (+y) points right; landscapeRight is the reverse
        let right: (x: Double, y: Double)
        switch view?.window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: right = (0, 1)
        case .landscapeRight: right = (0, -1)
        case .portraitUpsideDown: right = (-1, 0)
        default: right = (1, 0)
        }
        // down = right × screen normal (+z)
        return (right, (right.y, -right.x))
    }

    /// Host motion follows SDL's controller axes: x to the right, y up out of the pad's face,
    /// z toward the player. Held like a controller, the phone's screen is the pad's face, so
    /// x = screen right, y = out of the screen, z = screen down.
    private func sendHostMotion(_ sample: CMDeviceMotion, gyroOn: Bool) {
        guard sample.timestamp != lastHostSample else { return }
        lastHostSample = sample.timestamp
        let axes = screenAxes()
        func toPad(_ x: Double, _ y: Double, _ z: Double, scale: Double) -> (Float, Float, Float) {
            (Float((x * axes.right.x + y * axes.right.y) * scale),
             Float(z * scale),
             Float((x * axes.down.x + y * axes.down.y) * scale))
        }
        if (hostRate[MNGyro.gyroType] ?? 0) > 0 {
            let r = sample.rotationRate, b = GyroSettings.bias(GyroSettings.phoneBiasKey)
            // rad/s to deg/s; paused (or the gyro button released) reads as a still pad
            let v = toPad(r.x - b.x, r.y - b.y, r.z - b.z, scale: gyroOn ? 180 / Double.pi : 0)
            MNInput.controllerMotion(MNGyro.gyroType, x: v.0, y: v.1, z: v.2)
        }
        if (hostRate[MNGyro.accelType] ?? 0) > 0 {
            // CoreMotion's gravity points down; SDL's accelerometer reads +1 g up at rest
            let g = sample.gravity, a = sample.userAcceleration
            let v = toPad(g.x + a.x, g.y + a.y, g.z + a.z, scale: -9.80665)
            MNInput.controllerMotion(MNGyro.accelType, x: v.0, y: v.1, z: v.2)
        }
    }

    // MARK: Aiming

    private func aim(_ device: CMDeviceMotion?, dt: Double, buttonAllows: Bool) {
        let mode = aimMode
        // With a gyro button on screen, holding it is what turns aiming on
        let allowed = aimWidgetShown ? widgetAim != nil : (!MNGyro.isPaused && buttonAllows && triggerAllows())
        guard mode != .off, allowed, widgetPauses == 0, let rates = aimRates(device) else {
            releaseStick()
            return
        }
        var (horizontal, vertical) = rates
        if let factors = widgetAim {
            horizontal *= factors.x
            vertical *= factors.y
        }

        if GyroSettings.invertY { vertical = -vertical }
        if abs(horizontal) < deadZone { horizontal = 0 }
        if abs(vertical) < deadZone { vertical = 0 }
        horizontal *= GyroSettings.sensitivity * GyroSettings.sensitivityX
        vertical *= GyroSettings.sensitivity * GyroSettings.sensitivityY

        switch mode {
        case .mouse:
            let dx = horizontal * dt * mousePixelsPerRadian + remainder.x
            let dy = vertical * dt * mousePixelsPerRadian + remainder.y
            let sx = dx.rounded(.towardZero), sy = dy.rounded(.towardZero)
            remainder = (dx - sx, dy - sy)
            MNInput.mouseMoveX(Int16(clamping: Int(sx)), y: Int16(clamping: Int(sy)))
        case .rightStick:
            // stick y is up-positive
            let stick = MNGyro.shapeStick(x: horizontal * stickPerRadianPerSecond, y: -vertical * stickPerRadianPerSecond, minimum: GyroSettings.minStick)
            MNInput.gamepadGyroStickX(Int16(stick.x * 32767), y: Int16(stick.y * 32767))
            stickActive = true
        case .off:
            break
        }
    }

    /// Turn rates (right-positive, down-positive) in rad/s from the chosen sensor.
    private func aimRates(_ device: CMDeviceMotion?) -> (Double, Double)? {
        switch GyroSettings.source {
        case .phone:
            guard let device else { return nil }
            let b = GyroSettings.bias(GyroSettings.phoneBiasKey)
            let r = (x: device.rotationRate.x - b.x, y: device.rotationRate.y - b.y, z: device.rotationRate.z - b.z)
            let g = device.gravity
            let gLength = max((g.x * g.x + g.y * g.y + g.z * g.z).squareRoot(), 0.0001)
            // Rotation about world up (-gravity): positive is turning left, so negate for "right"
            let horizontal = -(r.x * -g.x + r.y * -g.y + r.z * -g.z) / gLength
            // Rotation about the screen's right-pointing axis: positive tips the top edge toward
            // the player, which aims down (screen y grows downward)
            let right = screenAxes().right
            return (horizontal, r.x * right.x + r.y * right.y)
        case .controller:
            // GameController motion axes: x right, y away from the player, z up. Turning right is
            // negative about z; tipping the front up is positive about x and aims up.
            guard let rate = MNGyro.controllerWithGyro()?.motion?.rotationRate else { return nil }
            let b = GyroSettings.bias(GyroSettings.controllerBiasKey)
            return (-(rate.z - b.z), -(rate.x - b.x))
        }
    }

    /// Gyro aiming drives player 1, so only player 1's pad (ControllerSupport numbers pads from
    /// index 1) gates or aims it; any pad when none has that index (outside a stream).
    private static func player1Pads() -> [GCController] {
        let pads = GCController.controllers()
        let first = pads.filter { $0.playerIndex == .index1 }
        return first.isEmpty ? pads : first
    }

    private static func controllerWithGyro() -> GCController? {
        player1Pads().first { $0.motion?.hasRotationRate == true }
    }

    /// "While aiming": L2 / left trigger held on the on-screen controls, the deck or a
    /// connected controller.
    private func triggerAllows() -> Bool {
        guard GyroSettings.activation == .whileAiming else { return true }
        if MNInput.aimTriggerHeld() { return true }
        return MNGyro.player1Pads().contains { $0.extendedGamepad?.leftTrigger.isPressed == true }
    }

    /// The physical controller's gyro button (Settings › Gyro › Gyro button): hold, toggle or
    /// hold-to-pause. The button still reaches the game.
    private func pollGyroButton() -> Bool {
        let button = GyroSettings.button
        guard button != .none else { return true }
        let down = MNGyro.player1Pads().contains { pad in
            pad.extendedGamepad.flatMap { button.input(on: $0) }?.isPressed == true
        }
        defer { buttonWasDown = down }
        switch GyroSettings.buttonMode {
        case .hold: return down
        case .holdToPause: return !down
        case .toggle:
            if down && !buttonWasDown { toggledOn.toggle() }
            return toggledOn
        }
    }

    // MARK: Steering

    /// Roll the phone like a wheel: the angle between gravity and the screen's down direction,
    /// measured in the screen's plane, drives the left stick's x.
    private func steer(_ device: CMDeviceMotion?) {
        guard GyroSettings.steering, !MNGyro.isPaused, let device else {
            releaseSteer()
            return
        }
        let axes = screenAxes()
        let g = device.gravity
        let alongRight = g.x * axes.right.x + g.y * axes.right.y
        let alongDown = g.x * axes.down.x + g.y * axes.down.y
        var x = 0.0
        // Lying nearly flat, the roll angle is noise: hold the wheel straight
        if (alongRight * alongRight + alongDown * alongDown).squareRoot() > 0.3 {
            // Positive when the right edge dips: steer right
            let angle = atan2(alongRight, alongDown)
            x = MNGyro.shapeStick(x: angle / fullLockRadians * GyroSettings.steeringSensitivity, y: 0, minimum: GyroSettings.minStick, deadZone: 0.03).x
        }
        let value = Int16(x * 32767)
        // Holding a steady angle shouldn't resend the same stick 120 times a second
        if value != lastSteer || !steerActive {
            MNInput.gamepadSteerX(value)
            lastSteer = value
        }
        steerActive = true
    }

    // MARK: Stick helpers

    /// Clamp to the unit circle, drop a small center deadzone, then lift what's left so the
    /// smallest output is `minimum` (anti-deadzone for games with a big stick deadzone).
    static func shapeStick(x: Double, y: Double, minimum: Double, deadZone: Double = 0) -> (x: Double, y: Double) {
        let length = (x * x + y * y).squareRoot()
        guard length > max(deadZone, 0.0001) else { return (0, 0) }
        let clamped = min(length, 1)
        let lifted = minimum + (1 - minimum) * (clamped - deadZone) / (1 - deadZone)
        return (x / length * lifted, y / length * lifted)
    }

    private func releaseSticks() {
        releaseStick()
        releaseSteer()
    }

    private func releaseStick() {
        guard stickActive else { return }
        stickActive = false
        MNInput.gamepadGyroStickX(0, y: 0)
    }

    private func releaseSteer() {
        guard steerActive else { return }
        steerActive = false
        MNInput.gamepadSteerX(0)
    }

    // MARK: Calibration

    /// Average the gyro over two seconds of holding still and save it as drift to subtract:
    /// the phone's always, and the first controller with a gyro when there is one. Calls back on
    /// the main thread with false when the device moved or has no gyro.
    func calibrate(completion: @escaping (Bool) -> Void) {
        guard motion.isDeviceMotionAvailable, !calibrating else { completion(false); return }
        calibrating = true
        refresh()
        let pad = MNGyro.controllerWithGyro()
        let padNeedsActivation = pad?.motion?.sensorsRequireManualActivation == true && pad?.motion?.sensorsActive == false
        if padNeedsActivation { pad?.motion?.sensorsActive = true }

        calibrationPhone = []
        calibrationController = []
        let started = CACurrentMediaTime()
        let t = Timer(timeInterval: 1.0 / 100.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if let r = self.motion.deviceMotion?.rotationRate { self.calibrationPhone.append(r) }
            if let r = pad?.motion?.rotationRate { self.calibrationController.append(r) }
            guard CACurrentMediaTime() - started >= 2 else { return }
            timer.invalidate()
            if padNeedsActivation { pad?.motion?.sensorsActive = false }
            self.calibrating = false
            self.refresh()

            let phone = self.calibrationPhone, controller = self.calibrationController
            // Moving more than ~6°/s at any point means it wasn't held still
            let still = phone.count > 20 && phone.allSatisfy { max(abs($0.x), abs($0.y), abs($0.z)) < 0.1 }
            guard still else { completion(false); return }
            func mean(_ xs: [Double]) -> Double { xs.reduce(0, +) / Double(max(xs.count, 1)) }
            UserDefaults.standard.set([mean(phone.map(\.x)), mean(phone.map(\.y)), mean(phone.map(\.z))], forKey: GyroSettings.phoneBiasKey)
            if !controller.isEmpty {
                UserDefaults.standard.set([mean(controller.map(\.x)), mean(controller.map(\.y)), mean(controller.map(\.z))], forKey: GyroSettings.controllerBiasKey)
            }
            completion(true)
        }
        RunLoop.main.add(t, forMode: .common)
    }
}
