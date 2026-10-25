//
//  WidgetInputs.swift
//  MoonLume
//
//  Everything widgets send to the host, with a record of what each widget is holding, so a
//  widget can always be let go of: when it's lifted, deleted or collapsed into a folder, when
//  the layout editor opens, when the app leaves the foreground and when the stream ends.
//  Two widgets holding the same key keep it down until both let go.
//

import Foundation

final class WidgetInputs {
    /// Inputs each widget holds (a widget can hold the same input twice: macro plus finger)
    private var held: [String: [WidgetInput]] = [:]
    private var counts: [WidgetInput: Int] = [:]
    /// Analog values each widget is driving
    private var sticks: [String: (right: Bool, x: Int16, y: Int16)] = [:]
    private var triggers: [String: (right: Bool, value: UInt8)] = [:]

    // MARK: Buttons and keys

    func press(_ input: WidgetInput, by holder: String) {
        held[holder, default: []].append(input)
        counts[input, default: 0] += 1
        if case .wheel(let d) = input {
            // A notch per press; nothing to hold
            switch d {
            case .up: MNInput.scroll(120)
            case .down: MNInput.scroll(-120)
            case .right: MNInput.hscroll(120)
            case .left: MNInput.hscroll(-120)
            }
        }
        else if counts[input] == 1 {
            send(input, down: true)
        }
    }

    func release(_ input: WidgetInput, by holder: String) {
        guard var list = held[holder], let i = list.lastIndex(of: input) else { return }
        list.remove(at: i)
        held[holder] = list.isEmpty ? nil : list
        let n = (counts[input] ?? 1) - 1
        counts[input] = n > 0 ? n : nil
        if n <= 0, !isWheel(input) {
            send(input, down: false)
        }
    }

    func press(_ inputs: [WidgetInput], by holder: String) {
        for input in inputs { press(input, by: holder) }
    }

    /// Chords let go in reverse, modifiers last
    func release(_ inputs: [WidgetInput], by holder: String) {
        for input in inputs.reversed() { release(input, by: holder) }
    }

    func isHolding(_ holder: String) -> Bool { held[holder] != nil || sticks[holder] != nil || triggers[holder] != nil }

    /// Lets go of everything a widget holds, analog values included
    func releaseAll(by holder: String) {
        if let list = held[holder] {
            for input in list.reversed() { release(input, by: holder) }
        }
        if let stick = sticks.removeValue(forKey: holder) {
            sendStick(right: stick.right, x: 0, y: 0)
        }
        if let trigger = triggers.removeValue(forKey: holder) {
            sendTrigger(right: trigger.right, value: 0)
        }
    }

    func releaseEverything() {
        for holder in Set(held.keys).union(sticks.keys).union(triggers.keys) {
            releaseAll(by: holder)
        }
    }

    // MARK: Analog

    func setStick(right: Bool, x: Double, y: Double, by holder: String) {
        let sx = Int16(clamping: Int((min(max(x, -1), 1) * 32767).rounded()))
        let sy = Int16(clamping: Int((min(max(y, -1), 1) * 32767).rounded()))
        if let last = sticks[holder], last.right == right, last.x == sx, last.y == sy { return }
        if let last = sticks[holder], last.right != right { sendStick(right: last.right, x: 0, y: 0) }
        sticks[holder] = (right, sx, sy)
        sendStick(right: right, x: sx, y: sy)
    }

    func setTrigger(right: Bool, value: Double, by holder: String) {
        let v = UInt8(clamping: Int((min(max(value, 0), 1) * 255).rounded()))
        if let last = triggers[holder], last.right == right, last.value == v { return }
        triggers[holder] = (right, v)
        sendTrigger(right: right, value: v)
    }

    // MARK: Sending

    private func isWheel(_ input: WidgetInput) -> Bool {
        if case .wheel = input { return true }
        return false
    }

    /// Modifier keys held by any widget, for the modifier byte of key events
    private var modifiers: MNKeyModifiers {
        var bits: UInt8 = 0
        for (input, _) in counts {
            if case .key(let vk) = input { bits |= WidgetCatalog.modifierBit(vk) }
        }
        return MNKeyModifiers(rawValue: bits)
    }

    private func send(_ input: WidgetInput, down: Bool) {
        switch input {
        case .pad(let flag): MNInput.gamepadButton(Int32(flag), down: down)
        case .leftTrigger: MNInput.gamepadLeftTrigger(down ? 255 : 0)
        case .rightTrigger: MNInput.gamepadRightTrigger(down ? 255 : 0)
        case .key(let vk):
            // counts already include (or exclude) this key, like a real keyboard's report
            if down { MNInput.keyDown(Int16(vk), modifiers: modifiers) }
            else { MNInput.keyUp(Int16(vk), modifiers: modifiers) }
        case .mouse(let b):
            MNInput.mouseButton(MNMouseButton(rawValue: Int32(b)) ?? .left, down: down)
        case .wheel:
            break
        }
    }

    private func sendStick(right: Bool, x: Int16, y: Int16) {
        if right { MNInput.gamepadRightStickX(x, y: y) } else { MNInput.gamepadLeftStickX(x, y: y) }
    }

    private func sendTrigger(right: Bool, value: UInt8) {
        if right { MNInput.gamepadRightTrigger(value) } else { MNInput.gamepadLeftTrigger(value) }
    }
}
