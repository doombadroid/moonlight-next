//
//  TouchInput.swift
//  MoonLume
//
//  The touchpad engine behind both the full-screen touchpad mode (RelativeTouchHandler) and
//  the input deck's trackpad: pointer moves, tap to click, two-finger tap for right click,
//  tap-then-hold to drag, two-finger scroll in both directions with momentum, and pinch sent
//  as Ctrl + wheel so host apps zoom. Plus the touch, mouse and keyboard settings the ObjC
//  stream code reads.
//
//  The gesture set follows VoidLink's touchpad (GPLv3, Input/TouchPadGestureHandler.swift
//  and Input/RelativeTouchHandler.m); the code is MoonLume's own.
//

import QuartzCore
import UIKit

/// What a touch on the stream does.
@objc enum MNTouchMode: Int {
    /// The screen is a laptop touchpad driving the host's pointer
    case touchpad = 0
    /// The pointer jumps to the finger (stored as TemporarySettings.absoluteTouchMode)
    case touchscreen = 1
    /// Real multi-touch points sent to the host (Windows and Linux hosts; stock Sunshine)
    case native = 2
    /// Touches on the stream do nothing; on-screen controls and the ••• menu still work
    case disabled = 3
}

/// Touch, mouse and keyboard settings (SettingsView writes them through @AppStorage).
@objc final class MNTouchPrefs: NSObject {
    static let touchModeKey = "mnTouchMode"
    static let pointerSpeedKey = "mnTouchpadPointerSpeed"
    static let deckSpeedKey = "mnTrackpadSpeed"
    static let scrollSpeedKey = "mnScrollSpeed"
    static let momentumKey = "mnScrollMomentum"
    static let pinchZoomKey = "mnPinchZoom"
    static let reverseScrollKey = "mnReverseScroll"
    static let topDeadZoneKey = "mnTopEdgeDeadZone"
    static let keyboardFingersKey = "mnKeyboardFingers"
    static let edgeSwipeKey = "mnEdgeSwipe"
    static let cursorModeKey = "mnCursorMode"

    enum EdgeSwipe: Int { case disconnect = 0, menu = 1, off = 2 }
    enum CursorMode: Int { case captured = 0, hidden = 1, visible = 2 }

    private static func double(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }

    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    /// Touchscreen lives in the older absoluteTouchMode setting; the rest in mnTouchMode.
    @objc static func touchMode(absolute: Bool) -> MNTouchMode {
        if absolute { return .touchscreen }
        switch MNTouchMode(rawValue: UserDefaults.standard.integer(forKey: touchModeKey)) {
        case .native: return .native
        case .disabled: return .disabled
        default: return .touchpad
        }
    }

    /// Full-screen touchpad pointer speed (1 = the old fixed speed)
    @objc static var pointerSpeed: Double { double(pointerSpeedKey, 1.0) }
    /// Input deck trackpad: host pixels per point of finger travel
    @objc static var deckSpeed: Double { double(deckSpeedKey, 2.0) }
    @objc static var scrollSpeed: Double { double(scrollSpeedKey, 1.0) }
    @objc static var momentum: Bool { bool(momentumKey, true) }
    @objc static var pinchZoom: Bool { bool(pinchZoomKey, true) }
    /// Flips mouse-wheel and two-finger scrolling
    @objc static var reverseScroll: Bool { bool(reverseScrollKey, false) }
    /// Touchpad mode ignores fingers that land along the top edge (Notification Center pulls)
    @objc static var topDeadZone: CGFloat { bool(topDeadZoneKey, true) ? 24 : 0 }
    /// Fingers in the tap that shows the soft keyboard; 0 = off
    @objc static var keyboardFingers: Int { UserDefaults.standard.object(forKey: keyboardFingersKey) as? Int ?? 3 }
    @objc static var edgeSwipeOpensMenu: Bool { UserDefaults.standard.integer(forKey: edgeSwipeKey) == EdgeSwipe.menu.rawValue }
    @objc static var edgeSwipeDisconnects: Bool { UserDefaults.standard.integer(forKey: edgeSwipeKey) == EdgeSwipe.disconnect.rawValue }
}

/// A physical mouse's pointer while streaming. Captured: locked and sent as relative motion
/// (games). Hidden or visible: the host pointer follows the iOS pointer's position.
/// Ctrl+Alt+Shift+M and C flip these for the running stream.
@objc final class MNMouse: NSObject {
    @objc static var captured = true
    @objc static var cursorVisible = false

    /// From Settings, at the start of each stream
    @objc static func reset() {
        let mode = MNTouchPrefs.CursorMode(rawValue: UserDefaults.standard.integer(forKey: MNTouchPrefs.cursorModeKey)) ?? .captured
        captured = mode == .captured
        cursorVisible = mode == .visible
    }
}

/// One touchpad surface. The owner forwards its UIKit touches; everything goes to the host
/// through MNInput.
@objc final class MNTouchpad: NSObject {
    private weak var view: UIView?
    /// Full-screen touchpad mode (stream view) rather than the deck's trackpad
    private let fullScreen: Bool
    /// Called on every click the pad sends (the deck plays a haptic)
    @objc var onClick: (() -> Void)?

    /// Movement past this many points makes a touch a move, not a tap
    private let tapSlop: CGFloat = 6
    /// A second touch this soon after a tap, near it, holds the left button (tap-then-hold drag)
    private let doubleTapWindow: TimeInterval = 0.3
    private let doubleTapDistance: CGFloat = 50
    /// Full-screen mode also starts a drag after a still press this long (the old behavior)
    private let holdToDragDelay: TimeInterval = 0.65

    private var touches: [UITouch] = []        // fingers on the pad, oldest first
    private var ignored = Set<UITouch>()       // landed in the top-edge dead zone
    private var peakCount = 0
    private var moved = false
    private var start = CGPoint.zero
    private var last = CGPoint.zero
    private var remainder = CGPoint.zero
    private var dragging = false
    private var lastTap: (time: TimeInterval, point: CGPoint)?
    private var holdTimer: Timer?
    private let scroller: MNTwoFingerScroll

    @objc init(view: UIView, fullScreen: Bool) {
        self.view = view
        self.fullScreen = fullScreen
        // High-res wheel units (120 = one notch) per point of finger travel
        scroller = MNTwoFingerScroll(unitsPerPoint: fullScreen ? 10 : 4)
        super.init()
    }

    deinit {
        holdTimer?.invalidate()
        scroller.cancel()
        if dragging { MNInput.mouseButton(.left, down: false) }
    }

    private func point(_ touch: UITouch) -> CGPoint { touch.location(in: view) }

    @objc func touchesBegan(_ newTouches: Set<UITouch>) {
        scroller.stopMomentum()
        let wasEmpty = touches.isEmpty
        for touch in newTouches {
            if wasEmpty && touches.isEmpty && fullScreen && point(touch).y < MNTouchPrefs.topDeadZone {
                ignored.insert(touch)
                continue
            }
            touches.append(touch)
        }
        guard !touches.isEmpty else { return }

        if wasEmpty {
            peakCount = touches.count
            moved = false
            start = point(touches[0])
            last = start
            remainder = .zero
            if touches.count == 1 {
                let now = ProcessInfo.processInfo.systemUptime
                if let tap = lastTap, now - tap.time < doubleTapWindow, hypot(start.x - tap.point.x, start.y - tap.point.y) < doubleTapDistance {
                    // Second tap of a double tap: hold the button. Lifting without moving
                    // finishes a double click; moving drags.
                    press()
                }
                else if fullScreen {
                    holdTimer = Timer.scheduledTimer(withTimeInterval: holdToDragDelay, repeats: false) { [weak self] _ in
                        guard let self, !self.moved, self.touches.count == 1, !self.dragging else { return }
                        self.press()
                    }
                }
            }
        }
        else {
            peakCount = max(peakCount, touches.count)
            holdTimer?.invalidate()
        }
        lastTap = nil

        if touches.count == 2 {
            scroller.begin(point(touches[0]), point(touches[1]))
        }
        else if touches.count > 2 {
            scroller.cancel()
        }
    }

    @objc func touchesMoved(_ movedTouches: Set<UITouch>) {
        switch touches.count {
        case 1:
            guard movedTouches.contains(touches[0]) else { return }
            let p = point(touches[0])
            movePointer(dx: p.x - last.x, dy: p.y - last.y)
            last = p
            if hypot(p.x - start.x, p.y - start.y) > tapSlop {
                moved = true
            }
        case 2:
            scroller.update(point(touches[0]), point(touches[1]))
            if scroller.engaged {
                moved = true
            }
        default:
            break
        }
    }

    @objc func touchesEnded(_ endedTouches: Set<UITouch>) {
        lift(endedTouches, cancelled: false)
    }

    @objc func touchesCancelled(_ cancelledTouches: Set<UITouch>) {
        lift(cancelledTouches, cancelled: true)
    }

    private func lift(_ lifted: Set<UITouch>, cancelled: Bool) {
        let before = touches.count
        for touch in lifted {
            ignored.remove(touch)
            touches.removeAll { $0 === touch }
        }
        guard touches.count != before else { return }

        if before == 2 {
            cancelled ? scroller.cancel() : scroller.end()
        }
        if touches.count == 1 {
            // Back to one finger: carry on from where it is, without a jump
            last = point(touches[0])
            start = last
        }
        guard touches.isEmpty else { return }

        holdTimer?.invalidate()
        holdTimer = nil
        if dragging {
            dragging = false
            MNInput.mouseButton(.left, down: false)
        }
        else if !moved && !cancelled {
            if peakCount == 1 {
                click(.left)
                lastTap = (ProcessInfo.processInfo.systemUptime, last)
            }
            else if peakCount == 2 {
                click(.right)
            }
            // Three or more fingers: the soft keyboard gesture, nothing to send
        }
        peakCount = 0
    }

    private func press() {
        dragging = true
        onClick?()
        MNInput.mouseButton(.left, down: true)
    }

    private func click(_ button: MNMouseButton) {
        onClick?()
        MNInput.mouseButton(button, down: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MNInput.mouseButton(button, down: false)
        }
    }

    private func movePointer(dx: CGFloat, dy: CGFloat) {
        let scale: CGFloat
        if fullScreen {
            // Scaled to a 1280-wide reference so the speed doesn't depend on the screen
            let size = view?.bounds.size ?? .zero
            scale = 1280 / max(size.width, size.height, 1) * CGFloat(MNTouchPrefs.pointerSpeed)
        }
        else {
            scale = CGFloat(MNTouchPrefs.deckSpeed)
        }
        let x = dx * scale + remainder.x
        let y = dy * scale + remainder.y
        let sx = x.rounded(.towardZero), sy = y.rounded(.towardZero)
        remainder = CGPoint(x: x - sx, y: y - sy)
        MNInput.mouseMoveX(Int16(clamping: Int(sx)), y: Int16(clamping: Int(sy)))
    }
}

/// Two fingers: scroll (with momentum after a flick) or pinch, whichever the gesture starts as.
/// Also used by the touchscreen mode's two-finger gestures (AbsoluteTouchHandler).
@objc final class MNTwoFingerScroll: NSObject {
    private enum Mode { case undecided, scroll, zoom }

    private let unitsPerPoint: CGFloat
    private var mode = Mode.undecided
    private var startMid = CGPoint.zero, startSpread: CGFloat = 0
    private var lastMid = CGPoint.zero, lastSpread: CGFloat = 0
    private var lastTime: TimeInterval = 0
    private var remainder = CGPoint.zero
    private var zoomRemainder: CGFloat = 0
    /// Points per second, smoothed, for momentum
    private var velocity = CGPoint.zero
    private var link: CADisplayLink?

    private static let ctrl: Int16 = 0xA2

    @objc var engaged: Bool { mode != .undecided }

    @objc init(unitsPerPoint: CGFloat) {
        self.unitsPerPoint = unitsPerPoint
    }

    @objc(begin:and:) func begin(_ a: CGPoint, _ b: CGPoint) {
        stopMomentum()
        cancel()
        startMid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        startSpread = hypot(a.x - b.x, a.y - b.y)
        lastMid = startMid
        lastSpread = startSpread
        lastTime = ProcessInfo.processInfo.systemUptime
        remainder = .zero
        zoomRemainder = 0
        velocity = .zero
    }

    @objc(update:and:) func update(_ a: CGPoint, _ b: CGPoint) {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let spread = hypot(a.x - b.x, a.y - b.y)
        let now = ProcessInfo.processInfo.systemUptime
        defer {
            if mode != .undecided {
                lastMid = mid
                lastSpread = spread
                lastTime = now
            }
        }

        switch mode {
        case .undecided:
            // Decide once, so a scroll never turns into a zoom halfway through
            let pan = hypot(mid.x - startMid.x, mid.y - startMid.y)
            let pinch = abs(spread - startSpread)
            if MNTouchPrefs.pinchZoom && pinch > 14 && pinch > pan * 1.5 {
                mode = .zoom
                MNInput.keyDown(Self.ctrl, modifiers: .ctrl)
            }
            else if pan > 6 {
                mode = .scroll
            }
        case .zoom:
            // Fingers apart = wheel up = zoom in
            let units = (spread - lastSpread) * unitsPerPoint * CGFloat(MNTouchPrefs.scrollSpeed) + zoomRemainder
            let whole = units.rounded(.towardZero)
            zoomRemainder = units - whole
            MNInput.scroll(Int16(clamping: Int(whole)))
        case .scroll:
            let d = CGPoint(x: mid.x - lastMid.x, y: mid.y - lastMid.y)
            emit(d)
            let dt = max(now - lastTime, 1.0 / 240)
            velocity = CGPoint(x: velocity.x * 0.4 + d.x / dt * 0.6, y: velocity.y * 0.4 + d.y / dt * 0.6)
        }
    }

    /// Fingers lifted: a flick keeps scrolling and slows down
    @objc func end() {
        let flick = mode == .scroll && ProcessInfo.processInfo.systemUptime - lastTime < 0.05 && hypot(velocity.x, velocity.y) > 100
        cancel()
        guard flick, MNTouchPrefs.momentum else { return }
        let link = CADisplayLink(target: self, selector: #selector(glide(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Ends the gesture without momentum
    @objc func cancel() {
        if mode == .zoom {
            MNInput.keyUp(Self.ctrl, modifiers: [])
        }
        mode = .undecided
    }

    @objc func stopMomentum() {
        link?.invalidate()
        link = nil
    }

    @objc private func glide(_ link: CADisplayLink) {
        let dt = CGFloat(link.targetTimestamp - link.timestamp)
        let decay = pow(0.95, dt * 60)
        velocity = CGPoint(x: velocity.x * decay, y: velocity.y * decay)
        if hypot(velocity.x, velocity.y) < 20 {
            stopMomentum()
            return
        }
        emit(CGPoint(x: velocity.x * dt, y: velocity.y * dt))
    }

    /// Fingers moving down scroll the content up, as on a Mac trackpad. One axis at a time,
    /// so a vertical scroll doesn't drift sideways.
    private func emit(_ d: CGPoint) {
        let k = unitsPerPoint * CGFloat(MNTouchPrefs.scrollSpeed) * (MNTouchPrefs.reverseScroll ? -1 : 1)
        if abs(d.x) > abs(d.y) * 1.2 {
            let units = -d.x * k + remainder.x
            let whole = units.rounded(.towardZero)
            remainder.x = units - whole
            MNInput.hscroll(Int16(clamping: Int(whole)))
        }
        else {
            let units = d.y * k + remainder.y
            let whole = units.rounded(.towardZero)
            remainder.y = units - whole
            MNInput.scroll(Int16(clamping: Int(whole)))
        }
    }
}
