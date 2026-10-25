//
//  AdaptiveTriggers.swift
//  MoonLume
//
//  A game's DualSense trigger effects, played on a real DualSense. The host sends them when it
//  emulates a DualSense (stock Sunshine does on Linux): one effect type byte and 10 bytes of
//  parameters per trigger, in the DualSense's own output-report format. GameController exposes
//  the same effects at a higher level, so each one is decoded and replayed through it.
//
//  Effect decoding adapted from VoidLink (GPLv3), ControllerUtil.swift (contributed there by
//  sirius128).
//

import GameController

@objc final class MNAdaptiveTriggers: NSObject {
    static let enabledKey = "mnAdaptiveTriggers"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    private enum Effect: Equatable {
        case off
        case feedback(start: Float, strength: Float)
        case weapon(start: Float, end: Float, strength: Float)
        case vibration(start: Float, amplitude: Float, frequency: Float)
        case slope(start: Float, end: Float, startStrength: Float, endStrength: Float)
        /// Per-zone strengths, 10 zones along the trigger's travel
        case zonedFeedback([Float])
        case zonedVibration([Float], frequency: Float)
    }

    /// Main thread. Payloads are nil for the trigger the host didn't change.
    @objc static func apply(to controller: GCController, leftType: UInt8, left: Data?, rightType: UInt8, right: Data?) {
        guard enabled, let pad = controller.extendedGamepad as? GCDualSenseGamepad else { return }
        if let left { play(decode(leftType, [UInt8](left)), on: pad.leftTrigger) }
        if let right { play(decode(rightType, [UInt8](right)), on: pad.rightTrigger) }
    }

    /// Back to plain triggers when the stream ends.
    @objc static func reset(for controller: GCController) {
        guard let pad = controller.extendedGamepad as? GCDualSenseGamepad else { return }
        pad.leftTrigger.setModeOff()
        pad.rightTrigger.setModeOff()
    }

    // MARK: Decoding

    private static func unit(_ v: Float) -> Float { max(0, min(1, v)) }
    /// A 0-255 position or strength
    private static func byte(_ b: UInt8) -> Float { Float(b) / 255 }
    /// Zone n of 10 as a position along the travel
    private static func zone(_ n: Int) -> Float { unit(Float(n) / 9) }
    /// Bits 0-9 of the first two bytes flag the zones an effect covers
    private static func zoneMask(_ b: [UInt8]) -> UInt16 { (UInt16(b[0]) | UInt16(b[1]) << 8) & 0x3FF }
    /// A 3-bit strength field: 0-7 means 1/8...8/8
    private static func eighths(_ v: UInt32) -> Float { Float((v & 7) + 1) / 8 }

    /// First and last flagged zone, kept at least one zone apart (GameController wants end > start)
    private static func span(_ mask: UInt16) -> (Float, Float) {
        let first = mask == 0 ? 0 : mask.trailingZeroBitCount
        let last = mask == 0 ? first + 1 : 15 - mask.leadingZeroBitCount
        let start = min(first, 8)
        return (zone(start), zone(max(start + 1, min(last, 9))))
    }

    /// Ten 3-bit strengths packed little-endian in bytes 2-5, for the flagged zones only.
    private static func zoneStrengths(_ b: [UInt8]) -> [Float] {
        let mask = zoneMask(b)
        let packed = UInt32(b[2]) | UInt32(b[3]) << 8 | UInt32(b[4]) << 16 | UInt32(b[5]) << 24
        return (0..<10).map { mask & (1 << $0) != 0 ? eighths(packed >> (3 * $0)) : 0 }
    }

    private static func decode(_ type: UInt8, _ b: [UInt8]) -> Effect {
        guard b.count >= 10 else { return .off }
        let effect: Effect
        switch type {
        case 0x01: effect = .feedback(start: byte(b[0]), strength: byte(b[1]))
        case 0x11: effect = .feedback(start: byte(b[0]), strength: unit(Float(b[1]) / 10))
        case 0x02, 0x12:
            let start = min(b[0], 254)
            effect = .weapon(start: byte(start), end: byte(max(b[1], start + 1)),
                             strength: type == 0x02 ? byte(b[2]) : unit(Float(b[2]) / 10))
        case 0x06: effect = .vibration(start: byte(b[2]), amplitude: byte(b[1]), frequency: byte(b[0]))
        case 0x21: effect = .zonedFeedback(zoneStrengths(b))
        case 0x22:
            let (start, end) = span(zoneMask(b))
            effect = .slope(start: start, end: end, startStrength: eighths(UInt32(b[2])), endStrength: eighths(UInt32(b[2]) >> 3))
        case 0x25:
            let (start, end) = span(zoneMask(b))
            effect = .weapon(start: start, end: end, strength: eighths(UInt32(b[2])))
        case 0x26: effect = .zonedVibration(zoneStrengths(b), frequency: byte(b[8]))
        case 0x23, 0x27:
            // Bow and galloping have no GameController equivalent: approximate with a vibration
            let mask = zoneMask(b)
            let amplitude = type == 0x23 ? 0.5 : Float(max(b[2] & 7, (b[2] >> 3) & 7)) / 7
            effect = .vibration(start: zone(mask == 0 ? 0 : mask.trailingZeroBitCount), amplitude: amplitude, frequency: byte(b[3]))
        default: effect = .off // 0x00, 0x05 (off) and anything unknown
        }

        // An effect with no force is off
        switch effect {
        case .feedback(_, let s), .weapon(_, _, let s): return s > 0 ? effect : .off
        case .vibration(_, let a, let f): return a > 0 && f > 0 ? effect : .off
        case .slope(_, _, let s, let e): return max(s, e) > 0 ? effect : .off
        case .zonedFeedback(let z): return z.contains { $0 > 0 } ? effect : .off
        case .zonedVibration(let z, let f): return f > 0 && z.contains { $0 > 0 } ? effect : .off
        case .off: return .off
        }
    }

    private static func play(_ effect: Effect, on trigger: GCDualSenseAdaptiveTrigger) {
        switch effect {
        case .off:
            trigger.setModeOff()
        case .feedback(let start, let strength):
            trigger.setModeFeedbackWithStartPosition(start, resistiveStrength: strength)
        case .weapon(let start, let end, let strength):
            trigger.setModeWeaponWithStartPosition(start, endPosition: end, resistiveStrength: strength)
        case .vibration(let start, let amplitude, let frequency):
            trigger.setModeVibrationWithStartPosition(start, amplitude: amplitude, frequency: frequency)
        case .slope(let start, let end, let startStrength, let endStrength):
            trigger.setModeSlopeFeedback(startPosition: start, endPosition: end, startStrength: startStrength, endStrength: endStrength)
        case .zonedFeedback(let z):
            trigger.setModeFeedback(resistiveStrengths: .init(values: (z[0], z[1], z[2], z[3], z[4], z[5], z[6], z[7], z[8], z[9])))
        case .zonedVibration(let z, let frequency):
            trigger.setModeVibration(amplitudes: .init(values: (z[0], z[1], z[2], z[3], z[4], z[5], z[6], z[7], z[8], z[9])), frequency: frequency)
        }
    }
}
