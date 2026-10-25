//
//  ControllerMouse.swift
//  MoonLume
//
//  Controller mouse mode: a physical controller drives the host's pointer, for launchers and the
//  desktop. One stick moves the pointer, the other scrolls, two chosen buttons click. While it's
//  on, ControllerSupport keeps the pad's input from the game. Toggled by Select + R3 or the
//  stream menu.
//

import GameController
import QuartzCore

enum ControllerMouseSettings {
    enum Clicks: Int { case faceButtons = 0, shoulders = 1, triggers = 2 }

    static let chordKey = "mnControllerMouseChord"
    static let leftStickKey = "mnControllerMouseLeftStick"
    static let clicksKey = "mnControllerMouseClicks"
    static let speedKey = "mnControllerMouseSpeed"

    static var chordEnabled: Bool { UserDefaults.standard.object(forKey: chordKey) as? Bool ?? true }
    /// The pointer is on the right stick unless this is set
    static var pointerOnLeftStick: Bool { UserDefaults.standard.bool(forKey: leftStickKey) }
    static var clicks: Clicks { Clicks(rawValue: UserDefaults.standard.integer(forKey: clicksKey)) ?? .faceButtons }
    static var speed: Double { UserDefaults.standard.object(forKey: speedKey) as? Double ?? 1 }
}

@objc final class MNControllerMouse: NSObject {
    @objc static let shared = MNControllerMouse()

    /// Pointer pixels per second at full deflection, speed 1
    private let pixelsPerSecond = 1400.0
    /// Scroll per second at full deflection: 12 notches
    private let scrollPerSecond = 12.0 * 120
    private let deadZone = 0.12
    /// Response curve: small deflections move slowly for precise aiming at buttons
    private let exponent = 1.7

    @objc private(set) var isOn = false
    private weak var pad: GCExtendedGamepad?
    private var timer: Timer?
    private var lastTick = 0.0
    private var remainder = (x: 0.0, y: 0.0, scrollX: 0.0, scrollY: 0.0)
    private var leftDown = false
    private var rightDown = false
    private var chordWasDown = false
    /// After the chord turns mouse mode off, the chord's buttons stay away from the game until released
    private var swallowUntilReleased = false

    /// Shown in the stream menu only with a controller connected.
    @objc static var hasController: Bool { GCController.controllers().contains { $0.extendedGamepad != nil } }

    /// ControllerSupport calls this for every input change on a physical pad, on the main
    /// thread. True means the change belongs to the pointer, not the game.
    @objc func intercept(_ gamepad: GCExtendedGamepad) -> Bool {
        let chordDown = ControllerMouseSettings.chordEnabled
            && gamepad.buttonOptions?.isPressed == true && gamepad.rightThumbstickButton?.isPressed == true
        defer { chordWasDown = chordDown }
        if chordDown && !chordWasDown {
            set(on: !isOn, pad: gamepad)
            if !isOn { swallowUntilReleased = true }
            return true
        }
        if swallowUntilReleased {
            if gamepad.buttonOptions?.isPressed == true || gamepad.rightThumbstickButton?.isPressed == true { return true }
            swallowUntilReleased = false
        }
        return isOn && gamepad === pad
    }

    /// Stream menu: toggle on the first connected controller.
    @objc func toggle() {
        set(on: !isOn, pad: GCController.controllers().lazy.compactMap(\.extendedGamepad).first)
    }

    @objc func stop() {
        set(on: false, pad: nil)
    }

    private func set(on: Bool, pad: GCExtendedGamepad?) {
        let on = on && pad != nil
        if on == isOn { return }
        isOn = on
        self.pad = pad
        timer?.invalidate()
        timer = nil
        releaseButtons()
        remainder = (0, 0, 0, 0)
        if on {
            lastTick = 0
            let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func tick() {
        guard let pad else {
            stop()
            return
        }
        let now = CACurrentMediaTime()
        let dt = lastTick > 0 ? min(now - lastTick, 0.05) : 0
        lastTick = now

        let leftPointer = ControllerMouseSettings.pointerOnLeftStick
        let pointer = leftPointer ? pad.leftThumbstick : pad.rightThumbstick
        let wheel = leftPointer ? pad.rightThumbstick : pad.leftThumbstick

        // Pointer: stick y is up-positive, screen y grows downward
        let move = curve(Double(pointer.xAxis.value), -Double(pointer.yAxis.value))
        let speed = pixelsPerSecond * ControllerMouseSettings.speed * dt
        let dx = move.x * speed + remainder.x, dy = move.y * speed + remainder.y
        let sx = dx.rounded(.towardZero), sy = dy.rounded(.towardZero)
        remainder.x = dx - sx
        remainder.y = dy - sy
        MNInput.mouseMoveX(Int16(clamping: Int(sx)), y: Int16(clamping: Int(sy)))

        // Wheel: the dominant axis scrolls, so a diagonal push doesn't scroll both ways
        let scroll = curve(Double(wheel.xAxis.value), Double(wheel.yAxis.value))
        if abs(scroll.y) >= abs(scroll.x) {
            let amount = scroll.y * scrollPerSecond * dt + remainder.scrollY
            let whole = amount.rounded(.towardZero)
            remainder.scrollY = amount - whole
            MNInput.scroll(Int16(clamping: Int(whole)))
        } else {
            let amount = scroll.x * scrollPerSecond * dt + remainder.scrollX
            let whole = amount.rounded(.towardZero)
            remainder.scrollX = amount - whole
            MNInput.horizontalScroll(Int16(clamping: Int(whole)))
        }

        let (left, right): (GCControllerButtonInput, GCControllerButtonInput)
        switch ControllerMouseSettings.clicks {
        case .faceButtons: (left, right) = (pad.buttonA, pad.buttonB)
        case .shoulders: (left, right) = (pad.rightShoulder, pad.leftShoulder)
        case .triggers: (left, right) = (pad.rightTrigger, pad.leftTrigger)
        }
        if left.isPressed != leftDown {
            leftDown = left.isPressed
            MNInput.mouseButton(.left, down: leftDown)
        }
        if right.isPressed != rightDown {
            rightDown = right.isPressed
            MNInput.mouseButton(.right, down: rightDown)
        }
    }

    /// Radial deadzone, then an exponential curve; returns -1...1 per axis.
    private func curve(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
        let length = (x * x + y * y).squareRoot()
        guard length > deadZone else { return (0, 0) }
        let scaled = pow((min(length, 1) - deadZone) / (1 - deadZone), exponent)
        return (x / length * scaled, y / length * scaled)
    }

    private func releaseButtons() {
        if leftDown { MNInput.mouseButton(.left, down: false) }
        if rightDown { MNInput.mouseButton(.right, down: false) }
        leftDown = false
        rightDown = false
    }
}
