//
//  PalmRejection.swift
//  MoonLume
//
//  Palm rejection for the tabletop input deck. Held like a Nintendo DS, the base of each palm
//  rests on the lower half's edges and lands on keys, click buttons and the trackpad. Three
//  rules, the same ideas laptop trackpads use:
//  - Contact size: a touch wider than a thumb is a palm (UITouch.majorRadius).
//  - Near a palm: a palm often registers as several touches, so fresh touches right next to an
//    active palm are palms too.
//  - Typing: right after a key press, new trackpad touches are ignored.
//  Strict also holds each key for a moment before sending it, and drops it if the touch grows
//  into a palm in that time (palms land small and spread).
//

import UIKit
import os

enum PalmRejection: Int, CaseIterable {
    case off = 0, normal = 1, strict = 2

    static let key = "mnPalmRejection"
    static var level: PalmRejection {
        PalmRejection(rawValue: UserDefaults.standard.object(forKey: key) as? Int ?? PalmRejection.normal.rawValue) ?? .normal
    }

    var label: String {
        switch self {
        case .off: return "Off"
        case .normal: return "Normal"
        case .strict: return "Strict"
        }
    }

    /// Contact radius (points) above which a touch counts as a palm.
    // ponytail: first guesses; tune from the "deck touch" log lines on the Duo
    var maxRadius: CGFloat {
        switch self {
        case .off: return .greatestFiniteMagnitude
        case .normal: return 36
        case .strict: return 28
        }
    }

    /// How long a key waits before sending, so a touch that grows into a palm can be dropped.
    var confirmDelay: TimeInterval { self == .strict ? 0.05 : 0 }

    /// After a key press, new trackpad touches are ignored for this long.
    var typingQuiet: TimeInterval { self == .off ? 0 : 0.3 }
}

/// Shared by the deck's keys, click buttons and trackpad.
final class PalmGuard {
    static let shared = PalmGuard()

    private static let log = Logger(subsystem: "com.doombadroid.moonlightnext", category: "deck")
    /// Touches judged to be palms. Weak, so a touch whose end never reached us can't linger.
    private var palms: [WeakTouch] = []
    private struct WeakTouch { weak var touch: UITouch? }
    private var lastKeyTime: CFTimeInterval = 0
    /// Fresh touches this close to an active palm are part of it
    private let palmReach: CGFloat = 60

    /// Judge a touch as it lands (and again as it moves: palms spread after landing).
    /// Once a palm, always a palm until it lifts.
    func isPalm(_ touch: UITouch, landing: Bool = false) -> Bool {
        let point = touch.location(in: nil)
        palms.removeAll { $0.touch == nil || $0.touch!.phase == .ended || $0.touch!.phase == .cancelled }
        if palms.contains(where: { $0.touch === touch }) {
            return true
        }
        let level = PalmRejection.level
        if landing {
            Self.log.notice("deck touch r=\(Double(touch.majorRadius), format: .fixed(precision: 1), privacy: .public) tol=\(Double(touch.majorRadiusTolerance), format: .fixed(precision: 1), privacy: .public) at=(\(Int(point.x), privacy: .public),\(Int(point.y), privacy: .public)) level=\(level.rawValue, privacy: .public)")
        }
        guard level != .off else { return false }
        var palm = touch.majorRadius > level.maxRadius
        if !palm && landing {
            palm = palms.contains { entry in
                guard let p = entry.touch?.location(in: nil) else { return false }
                return hypot(p.x - point.x, p.y - point.y) < palmReach
            }
        }
        if palm {
            palms.append(WeakTouch(touch: touch))
            Self.log.notice("deck palm rejected r=\(Double(touch.majorRadius), format: .fixed(precision: 1), privacy: .public)")
        }
        return palm
    }

    func touchLifted(_ touch: UITouch) {
        palms.removeAll { $0.touch == nil || $0.touch === touch }
    }

    func noteKeyPress() {
        lastKeyTime = CACurrentMediaTime()
    }

    /// The trackpad ignores new touches while the user is typing.
    var typingRecently: Bool {
        CACurrentMediaTime() - lastKeyTime < PalmRejection.level.typingQuiet
    }
}

/// One UIKit view over a grid of keys: maps each touch to the key under it and runs it past
/// the palm guard. SwiftUI's per-key gestures can't see a touch's contact size.
final class KeyTouchView: UIView {
    /// Rows of key weights, laid out like KeyGrid: rows `keyHeight` tall with 6 pt between rows,
    /// keys sharing the width by weight with 5 pt between keys.
    var rows: [[CGFloat]] = []
    var keyHeight: CGFloat = 54
    var onDown: (_ row: Int, _ index: Int) -> Void = { _, _ in }
    var onUp: (_ row: Int, _ index: Int) -> Void = { _, _ in }

    private struct Held { let row: Int; let index: Int; let start: CGPoint; var sent: Bool }
    private var held: [ObjectIdentifier: Held] = [:]
    /// A finger that drifts this far from where it landed lets go of its key
    private let maxDrift: CGFloat = 60

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func key(at p: CGPoint) -> (Int, Int)? {
        var y: CGFloat = 0
        for (r, weights) in rows.enumerated() {
            if p.y >= y - 3 && p.y < y + keyHeight + 3 {
                let unit = (bounds.width - CGFloat(weights.count - 1) * 5) / weights.reduce(0, +)
                var x: CGFloat = 0
                for (i, w) in weights.enumerated() {
                    // Gaps belong to the nearer key, so a touch between keys still lands somewhere
                    let width = unit * w
                    if p.x < x + width + 2.5 || i == weights.count - 1 { return (r, i) }
                    x += width + 5
                }
            }
            y += keyHeight + 6
        }
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let delay = PalmRejection.level.confirmDelay
        for touch in touches {
            guard !PalmGuard.shared.isPalm(touch, landing: true), let (r, i) = key(at: touch.location(in: self)) else { continue }
            // A second finger on a key that's already down adds nothing (both thumbs on space)
            if held.values.contains(where: { $0.row == r && $0.index == i }) { continue }
            let id = ObjectIdentifier(touch)
            held[id] = Held(row: r, index: i, start: touch.location(in: self), sent: delay == 0)
            if delay == 0 {
                press(r, i)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, var h = self.held[id], !h.sent else { return }
                    h.sent = true
                    self.held[id] = h
                    self.press(h.row, h.index)
                }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let h = held[id] else { continue }
            let p = touch.location(in: self)
            if PalmGuard.shared.isPalm(touch) || hypot(p.x - h.start.x, p.y - h.start.y) > maxDrift {
                // Grew into a palm or slid away: let go (a key still waiting never sends)
                held.removeValue(forKey: id)
                if h.sent { onUp(h.row, h.index) }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

    private func lift(_ touches: Set<UITouch>) {
        for touch in touches {
            PalmGuard.shared.touchLifted(touch)
            guard let h = held.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            // A quick tap that lifted inside the confirm window still types
            if !h.sent { press(h.row, h.index) }
            onUp(h.row, h.index)
        }
    }

    private func press(_ r: Int, _ i: Int) {
        PalmGuard.shared.noteKeyPress()
        onDown(r, i)
    }

    /// Let go of every held key (SwiftUI is tearing the grid down).
    func releaseAll() {
        for h in held.values where h.sent { onUp(h.row, h.index) }
        held.removeAll()
    }

}

/// A press-and-hold surface for a single button (the deck's click buttons), palm-guarded.
final class PressTouchView: UIView {
    var onChange: (_ down: Bool) -> Void = { _ in }
    private var touch: ObjectIdentifier?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        // Otherwise UIKit sends only the first touch, and a rejected palm would block the thumb
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touch == nil, let t = touches.first(where: { !PalmGuard.shared.isPalm($0, landing: true) }) else { return }
        touch = ObjectIdentifier(t)
        onChange(true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches where ObjectIdentifier(t) == touch && PalmGuard.shared.isPalm(t) {
            touch = nil
            onChange(false)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

    private func lift(_ touches: Set<UITouch>) {
        for t in touches {
            PalmGuard.shared.touchLifted(t)
            if ObjectIdentifier(t) == touch {
                touch = nil
                onChange(false)
            }
        }
    }

    /// Let go if held (SwiftUI is tearing the button down).
    func release() {
        if touch != nil { onChange(false) }
        touch = nil
    }
}
