//
//  WidgetLayer.swift
//  MoonLume
//
//  The view that holds the on-screen widgets, laid over the stream at the same size. Touches
//  that land on a widget are handled here; everywhere else they fall through to the stream
//  (and to the on-screen controls under it).
//
//  While the controls are being edited, touching a widget selects and drags it (the corner
//  handle resizes the selected one), with the same snapping, undo and save as the on-screen
//  controls: the widgets live in the controls' layout dictionary, so OnScreenControls keeps
//  the undo stack and saves them per posture and per game.
//

import UIKit

@objc final class MNWidgetLayer: UIView {
    /// Runs a function button's action (StreamFrameViewController)
    @objc var onFunction: ((MNWidgetFunction) -> Void)?
    /// Selection or widgets changed, for the editor bar
    var onEditorChange: (() -> Void)?

    static let stickRadius: CGFloat = 56

    private weak var osc: OnScreenControls?
    private(set) var widgets: [MNWidget] = []
    private var views: [String: WidgetView] = [:]
    private let inputs = WidgetInputs()
    @objc private(set) var isEditing = false
    private(set) var selectedID: String?

    // MARK: Play state

    /// Which widget each finger is on
    private var touchOwners: [ObjectIdentifier: String] = [:]
    private var live: [String: Live] = [:]
    /// Folders' current state (starts from the saved one)
    private var folderCollapsed: [String: Bool] = [:]
    private var displayLink: CADisplayLink?
    private var resignObserver: NSObjectProtocol?
    private var overlayTimer: Timer?

    /// What a widget is doing right now
    private final class Live {
        var fingers = 0
        var latched = false
        var origin = CGPoint.zero
        var last = CGPoint.zero
        // Camera pads
        var pending = CGVector.zero
        var velocity = CGVector.zero
        var lastTick = 0.0
        // Direction pads
        var mask = 0
        var walking = false
        var sprinting = false
        // Buttons
        var turbo: Timer?
        var turboTaps = 0
        var macroRun = 0
        var macroWaiting: (() -> Void)?
        var gyroHeld = false
        // Folders
        var dockTimer: Timer?
        var docked = false
        // Mouse pads and scroll strips
        var touchpad: MNTouchpad?
        var scrollRemainder: CGFloat = 0
    }

    // MARK: Editing state

    private var dragID: String?
    private var dragTouch: UITouch?
    private var dragResizing = false
    private var dragMoved = false
    private var dragStart = CGPoint.zero
    private var dragStartFrame = CGRect.zero
    private var dragStartCenters: [String: CGPoint] = [:]
    private var writing = false
    private let selectionLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()
    private let guideLayer = CAShapeLayer()

    @objc init(controls: OnScreenControls) {
        osc = controls
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        let accent = UIColor(red: 0x8A / 255.0, green: 0xB4 / 255.0, blue: 1, alpha: 1)
        selectionLayer.fillColor = nil
        selectionLayer.strokeColor = accent.cgColor
        selectionLayer.lineWidth = 1.5
        selectionLayer.lineDashPattern = [6, 4]
        handleLayer.fillColor = accent.cgColor
        guideLayer.strokeColor = accent.withAlphaComponent(0.7).cgColor
        guideLayer.lineWidth = 1
        guideLayer.lineDashPattern = [4, 4]
        resignObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.releaseAll()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        displayLink?.invalidate()
        overlayTimer?.invalidate()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            releaseAll()
            MNGyro.shared.aimWidgetShown = false
        }
        else {
            reload()
        }
    }

    // MARK: Layout data

    /// Re-reads the widgets from the controls' layout: after undo, a template, a posture change
    @objc func layoutChanged() {
        if osc?.selectedControl() != nil, selectedID != nil {
            selectedID = nil
        }
        if !writing {
            reload()
        }
        updateEditorOverlay()
    }

    private func reload() {
        guard let osc else { return }
        let saved = WidgetStore.widgets(in: osc.layoutDictionary())
        if saved != widgets {
            if !isEditing { releaseAll() }
            apply(saved)
        }
    }

    private func apply(_ list: [MNWidget]) {
        let oldIDs = Set(widgets.map(\.id))
        widgets = list
        let ids = Set(list.map(\.id))
        for id in oldIDs.subtracting(ids) {
            releaseWidget(id)
            views.removeValue(forKey: id)?.removeFromSuperview()
            live[id] = nil
            folderCollapsed[id] = nil
        }
        for widget in list {
            var shown = widget
            if widget.kind == .folder {
                if folderCollapsed[widget.id] == nil { folderCollapsed[widget.id] = widget.collapsed }
                shown.collapsed = folderCollapsed[widget.id] ?? widget.collapsed
            }
            if let view = views[widget.id] {
                if view.widget != shown { view.configure(shown) }
            }
            else {
                let view = WidgetView(widget: shown)
                views[widget.id] = view
                addSubview(view)
            }
        }
        // Folders above what's in them, the rest in list order
        for widget in list where widget.kind == .folder {
            if let view = views[widget.id] { bringSubviewToFront(view) }
        }
        if selectedID.map({ !ids.contains($0) }) == true { selectedID = nil }
        MNGyro.shared.aimWidgetShown = window != nil && list.contains { $0.kind == .gyroAim }
        updateOverlayTimer()
        layoutWidgets()
        for widget in list where widget.kind == .folder { scheduleDock(widget.id) }
    }

    /// Writes the widgets back into the layout being edited (the caller records the undo step)
    private func commit() {
        writing = true
        osc?.setLayoutValue(WidgetStore.value(for: widgets), forKey: WidgetStore.key)
        writing = false
        onEditorChange?()
    }

    func widget(_ id: String) -> MNWidget? { widgets.first { $0.id == id } }

    var folders: [MNWidget] { widgets.filter { $0.kind == .folder } }

    // MARK: Editing API (LayoutEditorBar)

    @objc func setEditing(_ editing: Bool) {
        releaseAll()
        isEditing = editing
        selectedID = nil
        dragID = nil
        dragTouch = nil
        if !editing {
            // Cancel puts the saved layout back; Save reloads what was saved
            reload()
            guideLayer.removeFromSuperlayer()
            onEditorChange = nil
        }
        for (id, l) in live where l.docked { undock(id, animated: false) }
        setNeedsLayout()
        updateEditorOverlay()
    }

    /// Adds a widget in the middle of the screen and selects it
    func add(_ widget: MNWidget) {
        var widget = widget
        // Each new one a little lower and to the right, so a few in a row don't stack exactly
        let n = Double(widgets.count % 5)
        widget.x = min(max(0.5 + n * 0.04, 0.05), 0.95)
        widget.y = min(max(0.45 + n * 0.05, 0.05), 0.95)
        osc?.pushUndo()
        osc?.selectControl(nil)
        widgets.append(widget)
        apply(widgets)
        selectedID = widget.id
        commit()
        updateEditorOverlay()
    }

    /// Changes a widget (one undo step per call unless `undo` is false: sliders push their own)
    func update(_ id: String, undo: Bool = true, _ change: (inout MNWidget) -> Void) {
        guard let i = widgets.firstIndex(where: { $0.id == id }) else { return }
        var copy = widgets[i]
        change(&copy)
        guard copy != widgets[i] else { return }
        if undo { osc?.pushUndo() }
        if copy.kind == .folder, copy.collapsed != widgets[i].collapsed { folderCollapsed[id] = copy.collapsed }
        widgets[i] = copy
        apply(widgets)
        commit()
        updateEditorOverlay()
    }

    func pushUndo() { osc?.pushUndo() }

    func delete(_ id: String) {
        guard widgets.contains(where: { $0.id == id }) else { return }
        osc?.pushUndo()
        releaseWidget(id)
        // A deleted folder's widgets stay, out of the folder
        widgets = widgets.filter { $0.id != id }.map { w in
            var w = w
            if w.folder == id { w.folder = "" }
            return w
        }
        selectedID = nil
        apply(widgets)
        commit()
        updateEditorOverlay()
    }

    func duplicate(_ id: String) {
        guard var copy = widget(id) else { return }
        copy.id = UUID().uuidString
        copy.x = min(copy.x + 0.04, 0.97)
        copy.y = min(copy.y + 0.04, 0.97)
        osc?.pushUndo()
        widgets.append(copy)
        apply(widgets)
        selectedID = copy.id
        commit()
        updateEditorOverlay()
    }

    func select(_ id: String?) {
        selectedID = id
        if id != nil { osc?.selectControl(nil) }
        updateEditorOverlay()
        onEditorChange?()
    }

    // MARK: Geometry

    override func layoutSubviews() {
        super.layoutSubviews()
        // The posture (and so the layout) follows the stream's size, which may just have changed
        osc?.relayout()
        reload()
        layoutWidgets()
    }

    private func layoutWidgets() {
        let global = osc?.globalOpacity ?? 1
        for widget in widgets {
            guard let view = views[widget.id] else { continue }
            guard live[widget.id]?.docked != true else { continue }
            view.frame = rect(of: widget)
            view.globalOpacity = global
            let hidden = isHiddenByFolder(widget)
            view.isHidden = hidden && !isEditing
            view.dimmed = hidden && isEditing
        }
        updateEditorOverlay()
    }

    private func rect(of w: MNWidget) -> CGRect {
        let c = CGPoint(x: bounds.minX + w.x * bounds.width, y: bounds.minY + w.y * bounds.height)
        return CGRect(x: c.x - w.w / 2, y: c.y - w.h / 2, width: w.w, height: w.h)
    }

    private func isHiddenByFolder(_ w: MNWidget) -> Bool {
        guard !w.folder.isEmpty, widget(w.folder)?.kind == .folder else { return false }
        return folderCollapsed[w.folder] ?? false
    }

    /// The topmost widget under a point that takes touches now
    private func widgetAt(_ p: CGPoint) -> MNWidget? {
        for view in subviews.reversed() {
            guard let view = view as? WidgetView, !view.isHidden, view.frame.insetBy(dx: -4, dy: -4).contains(p) else { continue }
            if !isEditing && view.widget.kind == .overlay { continue }
            return widget(view.widget.id)
        }
        return nil
    }

    private var handleCenter: CGPoint? {
        guard isEditing, let id = selectedID, let view = views[id] else { return nil }
        return CGPoint(x: view.frame.maxX + 4, y: view.frame.maxY + 4)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if let h = handleCenter, hypot(point.x - h.x, point.y - h.y) < 22 { return true }
        if widgetAt(point) != nil { return true }
        if isEditing, event?.type == .touches, selectedID != nil, dragTouch == nil {
            // A touch on empty space while editing goes to the controls under it: that ends
            // this selection
            DispatchQueue.main.async { self.select(nil) }
        }
        return false
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isEditing {
            editTouches(touches, phase: .began)
            return
        }
        for touch in touches {
            let p = touch.location(in: self)
            guard let w = widgetAt(p) else { continue }
            touchOwners[ObjectIdentifier(touch)] = w.id
            if w.kind == .mousePad {
                touchpad(w).touchesBegan([touch])
                continue
            }
            touchBegan(w, at: p)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isEditing {
            editTouches(touches, phase: .moved)
            return
        }
        for touch in touches {
            guard let id = touchOwners[ObjectIdentifier(touch)], let w = widget(id) else { continue }
            if w.kind == .mousePad {
                live[id]?.touchpad?.touchesMoved([touch])
                continue
            }
            let p = touch.location(in: self)
            if w.kind == .button, w.slide, !w.toggle, let other = widgetAt(p), other.id != id,
               other.kind == .button, other.slide, !other.toggle {
                // Rolling a thumb from one slide button onto another presses that one instead
                touchEnded(w, at: p)
                touchOwners[ObjectIdentifier(touch)] = other.id
                touchBegan(other, at: p)
                continue
            }
            touchMoved(w, at: p)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isEditing {
            editTouches(touches, phase: .ended)
            return
        }
        for touch in touches {
            guard let id = touchOwners.removeValue(forKey: ObjectIdentifier(touch)), let w = widget(id) else { continue }
            if w.kind == .mousePad {
                live[id]?.touchpad?.touchesEnded([touch])
                continue
            }
            touchEnded(w, at: touch.location(in: self))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    private func state(_ id: String) -> Live {
        if let l = live[id] { return l }
        let l = Live()
        live[id] = l
        return l
    }

    /// The mouse pad's trackpad (the deck's, so it moves, clicks, drags and scrolls the same way)
    private func touchpad(_ w: MNWidget) -> MNTouchpad {
        let l = state(w.id)
        if let pad = l.touchpad { return pad }
        let pad = MNTouchpad(view: views[w.id] ?? self, fullScreen: false)
        l.touchpad = pad
        return pad
    }

    private func touchBegan(_ w: MNWidget, at p: CGPoint) {
        let l = state(w.id)
        l.fingers += 1
        guard l.fingers == 1 else { return }
        l.origin = p
        l.last = p
        let view = views[w.id]
        switch w.kind {
        case .button, .gyroAim, .gyroPause:
            haptic(w)
            if w.toggle {
                l.latched.toggle()
                if l.latched { activate(w) } else { deactivate(w) }
            }
            else {
                activate(w)
            }
        case .function:
            haptic(w)
            view?.pressed = true
        case .folder:
            if l.docked {
                undock(w.id, animated: true)
                l.fingers = -1_000 // this touch only brings it back
                return
            }
            l.dockTimer?.invalidate()
            haptic(w)
            view?.pressed = true
        case .stickPad, .directionPad:
            view?.showTouch(origin: p.relative(to: view), at: p.relative(to: view))
            if w.kind == .directionPad { updateDirections(w, at: p) }
        case .cameraPad:
            l.pending = .zero
            l.velocity = .zero
            l.lastTick = CACurrentMediaTime()
            view?.showTouch(origin: nil, at: p.relative(to: view))
            startDisplayLink()
        case .triggerPad:
            view?.showLevel(0)
        case .scrollPad:
            l.scrollRemainder = 0
            view?.showTouch(origin: nil, at: p.relative(to: view))
        case .overlay, .mousePad, .blocker:
            break
        }
    }

    private func touchMoved(_ w: MNWidget, at p: CGPoint) {
        guard let l = live[w.id], l.fingers > 0 else { return }
        let view = views[w.id]
        switch w.kind {
        case .stickPad:
            // Floating stick: the base follows a thumb that goes past the edge, so turning back
            // reacts at once
            var d = CGVector(dx: p.x - l.origin.x, dy: p.y - l.origin.y)
            let r = MNWidgetLayer.stickRadius / CGFloat(w.sensitivity)
            let length = hypot(d.dx, d.dy)
            if length > r {
                l.origin.x += d.dx * (1 - r / length)
                l.origin.y += d.dy * (1 - r / length)
                d = CGVector(dx: p.x - l.origin.x, dy: p.y - l.origin.y)
            }
            let shaped = MNGyro.shapeStick(x: Double(d.dx / r), y: Double(-d.dy / r), minimum: 0, deadZone: 0.05)
            inputs.setStick(right: w.right, x: shaped.x, y: shaped.y, by: w.id)
            view?.showTouch(origin: l.origin.relative(to: view), at: p.relative(to: view))
        case .cameraPad:
            l.pending.dx += p.x - l.last.x
            l.pending.dy += p.y - l.last.y
            view?.showTouch(origin: nil, at: p.relative(to: view))
        case .triggerPad:
            // Adapted from VoidLink (GPLv3), OnScreenWidgetView.swift: 4.5 trigger units per point
            let value = Double(max(l.origin.y - p.y, 0)) * 4.5 * w.sensitivity / 255
            inputs.setTrigger(right: w.right, value: value, by: w.id)
            view?.showLevel(min(value, 1))
        case .directionPad:
            updateDirections(w, at: p)
            view?.showTouch(origin: l.origin.relative(to: view), at: p.relative(to: view))
        case .scrollPad:
            // Same direction and speed setting as the trackpad's two-finger scroll: 4 wheel
            // units (1/30 notch) per point at sensitivity 1
            let k = 4 * w.sensitivity * MNTouchPrefs.scrollSpeed * (MNTouchPrefs.reverseScroll ? -1 : 1)
            let units = (p.y - l.last.y) * k + l.scrollRemainder
            let whole = units.rounded(.towardZero)
            l.scrollRemainder = units - whole
            MNInput.scroll(Int16(clamping: Int(whole)))
            view?.showTouch(origin: nil, at: p.relative(to: view))
        default:
            break
        }
        l.last = p
    }

    private func touchEnded(_ w: MNWidget, at p: CGPoint) {
        guard let l = live[w.id] else { return }
        l.fingers -= 1
        if l.fingers < 0 {
            // The touch that brought a docked folder back
            l.fingers = 0
            scheduleDock(w.id)
            return
        }
        guard l.fingers == 0 else { return }
        let view = views[w.id]
        let inside = view.map { $0.frame.insetBy(dx: -12, dy: -12).contains(p) } ?? false
        switch w.kind {
        case .button, .gyroAim, .gyroPause:
            if !w.toggle {
                deactivate(w)
            }
            else if !l.latched, let resume = l.macroWaiting {
                l.macroWaiting = nil
                resume()
            }
        case .function:
            view?.pressed = false
            if inside { onFunction?(w.function) }
        case .folder:
            view?.pressed = false
            if inside { toggleFolder(w) }
        case .cameraPad:
            l.pending.dx += p.x - l.last.x
            l.pending.dy += p.y - l.last.y
            view?.showTouch(origin: nil, at: nil)
            if !w.inertia {
                l.velocity = .zero
                inputs.releaseAll(by: w.id)
            }
        case .scrollPad:
            view?.showTouch(origin: nil, at: nil)
        case .stickPad, .triggerPad, .directionPad:
            inputs.releaseAll(by: w.id)
            l.mask = 0
            l.walking = false
            l.sprinting = false
            view?.showTouch(origin: nil, at: nil)
            view?.showLevel(0)
        case .overlay, .mousePad, .blocker:
            break
        }
    }

    // MARK: Buttons

    private func activate(_ w: MNWidget) {
        let l = state(w.id)
        views[w.id]?.pressed = true
        switch w.kind {
        case .gyroAim:
            l.gyroHeld = true
            MNGyro.shared.widgetAim = (w.gyroX, w.gyroY)
        case .gyroPause:
            if !l.gyroHeld { MNGyro.shared.widgetPauses += 1 }
            l.gyroHeld = true
        default:
            if !w.macro.isEmpty {
                playMacro(w)
            }
            else if w.turboMs > 0 {
                // Adapted from VoidLink (GPLv3), OnScreenWidgetView.swift (auto-tap timer)
                l.turboTaps = 0
                tap(w)
                let t = Timer(timeInterval: Double(max(w.turboMs, 40)) / 1000, repeats: true) { [weak self, weak l] timer in
                    guard let self, let l else { timer.invalidate(); return }
                    self.tap(w)
                    if w.turboCount > 0, l.turboTaps >= w.turboCount {
                        timer.invalidate()
                        l.turbo = nil
                        if w.toggle, l.latched {
                            l.latched = false
                            self.views[w.id]?.pressed = false
                        }
                    }
                }
                RunLoop.main.add(t, forMode: .common)
                l.turbo = t
            }
            else {
                inputs.press(w.inputs, by: w.id)
            }
        }
    }

    private func deactivate(_ w: MNWidget) {
        guard let l = live[w.id] else { return }
        views[w.id]?.pressed = false
        switch w.kind {
        case .gyroAim:
            if l.gyroHeld { MNGyro.shared.widgetAim = nil }
            l.gyroHeld = false
        case .gyroPause:
            if l.gyroHeld { MNGyro.shared.widgetPauses = max(MNGyro.shared.widgetPauses - 1, 0) }
            l.gyroHeld = false
        default:
            l.turbo?.invalidate()
            l.turbo = nil
            inputs.releaseAll(by: w.id)
            // A macro keeps playing to the end; a step waiting for the finger goes on now
            if let resume = l.macroWaiting {
                l.macroWaiting = nil
                resume()
            }
        }
    }

    /// One quick press and release (turbo)
    private func tap(_ w: MNWidget) {
        let holder = w.id + "#tap"
        inputs.press(w.inputs, by: holder)
        live[w.id]?.turboTaps += 1
        let hold = min(30.0, Double(max(w.turboMs, 40)) / 2) / 1000
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            self?.inputs.release(w.inputs, by: holder)
        }
    }

    /// Plays the steps in order. Pressing again restarts it.
    private func playMacro(_ w: MNWidget) {
        let l = state(w.id)
        let holder = w.id + "#macro"
        inputs.releaseAll(by: holder)
        l.macroRun += 1
        l.macroWaiting = nil
        let run = l.macroRun
        func step(_ i: Int) {
            guard live[w.id] === l, l.macroRun == run, i < w.macro.count else {
                if l.macroRun == run { inputs.releaseAll(by: holder) }
                return
            }
            let s = w.macro[i]
            inputs.press(s.inputs, by: holder)
            let next = { [weak self] in
                guard let self, l.macroRun == run else { return }
                self.inputs.release(s.inputs, by: holder)
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(s.waitMs) / 1000) { step(i + 1) }
            }
            if s.untilRelease, l.fingers > 0 || l.latched {
                l.macroWaiting = next
            }
            else {
                // At least 30 ms, so the host sees the press
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(max(s.holdMs, 30)) / 1000) { next() }
            }
        }
        step(0)
    }

    /// Lets go of everything one widget holds and resets it
    private func releaseWidget(_ id: String) {
        guard let l = live[id] else {
            inputs.releaseAll(by: id)
            return
        }
        l.turbo?.invalidate()
        l.turbo = nil
        l.macroRun += 1
        l.macroWaiting = nil
        l.latched = false
        l.fingers = 0
        l.velocity = .zero
        l.pending = .zero
        l.mask = 0
        l.walking = false
        l.sprinting = false
        // A dropped trackpad lets go of a drag it was holding
        l.touchpad = nil
        if l.gyroHeld, let w = widget(id) {
            deactivate(w)
        }
        l.gyroHeld = false
        for holder in [id, id + "#tap", id + "#macro"] { inputs.releaseAll(by: holder) }
        views[id]?.pressed = false
        views[id]?.showTouch(origin: nil, at: nil)
        views[id]?.showLevel(0)
        touchOwners = touchOwners.filter { $0.value != id }
    }

    /// Stuck-input safety: the stream ended, the editor opened or the app left the foreground
    @objc func releaseAll() {
        for id in Array(live.keys) { releaseWidget(id) }
        inputs.releaseEverything()
        touchOwners.removeAll()
        MNGyro.shared.widgetAim = nil
        MNGyro.shared.widgetPauses = 0
    }

    // MARK: Direction pads

    // Adapted from VoidLink (GPLv3), OnScreenWidgetView.swift (LRUD pad): each direction
    // covers 67.5° either side, so diagonals press two keys; nothing within 16 pt of the start.
    private func updateDirections(_ w: MNWidget, at p: CGPoint) {
        guard let l = live[w.id] else { return }
        let dx = p.x - l.origin.x, dy = p.y - l.origin.y
        let dist = Double(hypot(dx, dy))
        var mask = 0
        if dist >= 16 {
            let degrees = atan2(-dy, dx) * 180 / .pi
            if abs(90 - degrees) < 67.5 { mask |= 1 }        // up
            if 180 - abs(degrees) < 67.5 { mask |= 2 }       // left
            if abs(-90 - degrees) < 67.5 { mask |= 4 }       // down
            if abs(degrees) < 67.5 { mask |= 8 }             // right
        }
        for bit in 0..<4 where (mask ^ l.mask) & (1 << bit) != 0 {
            let input = WidgetInput.key(w.keys[bit])
            if mask & (1 << bit) != 0 { inputs.press(input, by: w.id) } else { inputs.release(input, by: w.id) }
        }
        l.mask = mask
        // Walk key close to the start, sprint key far out
        let walk = w.walkKey > 0 && dist < w.walkBelow
        if walk != l.walking {
            if walk { inputs.press(.key(w.walkKey), by: w.id) } else { inputs.release(.key(w.walkKey), by: w.id) }
            l.walking = walk
        }
        let sprint = w.sprintKey > 0 && dist > w.sprintAbove
        if sprint != l.sprinting {
            if sprint {
                inputs.press(.key(w.sprintKey), by: w.id)
                haptic(w)
            }
            else {
                inputs.release(.key(w.sprintKey), by: w.id)
            }
            l.sprinting = sprint
        }
    }

    // MARK: Camera pads

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Swipe speed drives the stick: full deflection at 1000 pt/s, scaled by the widget's
    /// sensitivity. After lifting, the last speed fades out (inertia).
    @objc private func tick() {
        let now = CACurrentMediaTime()
        var active = false
        for w in widgets where w.kind == .cameraPad {
            guard let l = live[w.id], l.fingers > 0 || l.velocity != .zero else { continue }
            let dt = max(now - l.lastTick, 1.0 / 240)
            l.lastTick = now
            if l.fingers > 0 {
                let target = CGVector(dx: l.pending.dx / dt / 1000, dy: l.pending.dy / dt / 1000)
                l.pending = .zero
                // Touch reports and display frames don't line up: smooth over a frame or two
                l.velocity = CGVector(dx: (l.velocity.dx + target.dx) / 2, dy: (l.velocity.dy + target.dy) / 2)
            }
            else {
                // Adapted from VoidLink (GPLv3), InertialScroller.swift: 0.93 per 60 Hz frame
                let decay = pow(0.93, dt * 60)
                l.velocity = CGVector(dx: l.velocity.dx * decay, dy: l.velocity.dy * decay)
                if hypot(l.velocity.dx, l.velocity.dy) * w.sensitivity < 0.02 {
                    l.velocity = .zero
                    inputs.releaseAll(by: w.id)
                    continue
                }
            }
            let s = MNGyro.shapeStick(x: Double(l.velocity.dx) * w.sensitivity, y: Double(-l.velocity.dy) * w.sensitivity, minimum: 0)
            inputs.setStick(right: w.right, x: s.x, y: s.y, by: w.id)
            active = true
        }
        if !active {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    // MARK: Folders

    private func toggleFolder(_ w: MNWidget) {
        let collapse = !(folderCollapsed[w.id] ?? w.collapsed)
        folderCollapsed[w.id] = collapse
        if collapse {
            // Whatever is held inside lets go as it disappears
            for child in widgets where child.folder == w.id { releaseWidget(child.id) }
        }
        var shown = w
        shown.collapsed = collapse
        views[w.id]?.configure(shown)
        setNeedsLayout()
        scheduleDock(w.id)
    }

    private func scheduleDock(_ id: String) {
        guard let w = widget(id), w.kind == .folder else { return }
        let l = state(id)
        l.dockTimer?.invalidate()
        l.dockTimer = nil
        guard !isEditing, w.autoDock > 0, folderCollapsed[id] ?? w.collapsed, !l.docked else { return }
        l.dockTimer = Timer.scheduledTimer(withTimeInterval: w.autoDock, repeats: false) { [weak self] _ in
            self?.dock(id)
        }
    }

    // Adapted from VoidLink (GPLv3), OnScreenWidgetView.swift (folder auto-dock): an idle folder
    // slides to the nearest side edge, leaving a 17 pt tab, and fades to 0.2 after two seconds.
    private func dock(_ id: String) {
        guard let view = views[id], let l = live[id], !isEditing, l.fingers == 0 else { return }
        l.docked = true
        let f = view.frame
        let toLeft = f.midX < bounds.midX
        let x = toLeft ? bounds.minX - f.width + 17 : bounds.maxX - 17
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0) {
            view.frame.origin.x = x
            view.alpha = 0.8
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 2) {
                if l.docked { view.alpha = 0.2 }
            }
        }
    }

    private func undock(_ id: String, animated: Bool) {
        guard let w = widget(id), let view = views[id], let l = live[id] else { return }
        l.docked = false
        let target = rect(of: w)
        let change = {
            view.frame = target
            view.globalOpacity = self.osc?.globalOpacity ?? 1
        }
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, animations: change)
        }
        else {
            change()
        }
    }

    // MARK: Controller overlay

    private func updateOverlayTimer() {
        let needed = widgets.contains { $0.kind == .overlay }
        if needed, overlayTimer == nil {
            let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                guard let self else { return }
                for w in self.widgets where w.kind == .overlay { self.views[w.id]?.refreshDiagram() }
            }
            RunLoop.main.add(t, forMode: .common)
            overlayTimer = t
        }
        else if !needed {
            overlayTimer?.invalidate()
            overlayTimer = nil
        }
    }

    // MARK: Haptics

    private var generators: [MNWidget.Haptic: UIImpactFeedbackGenerator] = [:]

    private func haptic(_ w: MNWidget) {
        guard UserDefaults.standard.object(forKey: "mnHapticsEnabled") as? Bool ?? true else { return }
        let style = w.haptic
        let feedback: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case .off: return
        case .light: feedback = .light
        case .medium: feedback = .medium
        case .heavy: feedback = .heavy
        }
        let generator = generators[style] ?? UIImpactFeedbackGenerator(style: feedback)
        generators[style] = generator
        generator.impactOccurred(intensity: 0.8)
        generator.prepare()
    }

    // MARK: Editing touches

    private func editTouches(_ touches: Set<UITouch>, phase: UITouch.Phase) {
        for touch in touches {
            let p = touch.location(in: self)
            switch phase {
            case .began:
                guard dragTouch == nil else { continue }
                if let h = handleCenter, let id = selectedID, hypot(p.x - h.x, p.y - h.y) < 22 {
                    dragID = id
                    dragResizing = true
                }
                else if let w = widgetAt(p) {
                    dragID = w.id
                    dragResizing = false
                    select(w.id)
                }
                else {
                    continue
                }
                dragTouch = touch
                dragMoved = false
                dragStart = p
                dragStartFrame = views[dragID!]?.frame ?? .zero
                dragStartCenters = Dictionary(uniqueKeysWithValues: widgets.map { ($0.id, CGPoint(x: $0.x, y: $0.y)) })
            case .moved:
                guard touch == dragTouch, let id = dragID else { continue }
                if !dragMoved {
                    // A tap only selects: ignore the wobble of a finger landing
                    guard hypot(p.x - dragStart.x, p.y - dragStart.y) >= 4 else { continue }
                    osc?.pushUndo()
                    dragMoved = true
                }
                if dragResizing { resize(id, by: CGVector(dx: p.x - dragStart.x, dy: p.y - dragStart.y)) }
                else { move(id, by: CGVector(dx: p.x - dragStart.x, dy: p.y - dragStart.y)) }
            default:
                guard touch == dragTouch else { continue }
                dragTouch = nil
                dragID = nil
                guideLayer.removeFromSuperlayer()
                onEditorChange?()
            }
        }
    }

    private func move(_ id: String, by d: CGVector) {
        guard bounds.width > 0, bounds.height > 0, let start = dragStartCenters[id] else { return }
        var c = CGPoint(x: start.x * bounds.width + d.dx, y: start.y * bounds.height + d.dy)
        var guideX: CGFloat?, guideY: CGFloat?
        if osc?.snapToGuides ?? true { (c, guideX, guideY) = snap(c, excluding: id) }
        c.x = min(max(c.x, 0), bounds.width)
        c.y = min(max(c.y, 0), bounds.height)
        let nx = Double(c.x / bounds.width), ny = Double(c.y / bounds.height)
        let moved = (dx: nx - start.x, dy: ny - start.y)
        for i in widgets.indices {
            let w = widgets[i]
            // A folder takes what's in it along
            guard w.id == id || (w.folder == id && widget(id)?.kind == .folder), let s = dragStartCenters[w.id] else { continue }
            widgets[i].x = min(max(s.x + moved.dx, 0), 1)
            widgets[i].y = min(max(s.y + moved.dy, 0), 1)
        }
        apply(widgets)
        commit()
        drawGuides(x: guideX, y: guideY)
    }

    private func resize(_ id: String, by d: CGVector) {
        update(id, undo: false) { w in
            w.w = Double(min(max(dragStartFrame.width + d.dx, 24), 600))
            w.h = Double(min(max(dragStartFrame.height + d.dy, 24), 600))
            if w.shape == .circle, w.kind.isButtonLike {
                // Circles stay round
                w.w = max(w.w, w.h)
                w.h = w.w
            }
        }
    }

    /// Snaps a centre to the screen's centre lines, another widget's or control's row or column,
    /// or the mirror of another widget (so pairs sit symmetrically)
    private func snap(_ p: CGPoint, excluding id: String) -> (CGPoint, CGFloat?, CGFloat?) {
        var bestX: CGFloat = 8, bestY: CGFloat = 8
        var gx: CGFloat?, gy: CGFloat?
        func tryX(_ v: CGFloat) { if abs(v - p.x) < bestX { bestX = abs(v - p.x); gx = v } }
        func tryY(_ v: CGFloat) { if abs(v - p.y) < bestY { bestY = abs(v - p.y); gy = v } }
        tryX(bounds.midX)
        tryY(bounds.midY)
        for w in widgets where w.id != id && w.folder != id {
            let c = CGPoint(x: w.x * bounds.width, y: w.y * bounds.height)
            tryX(c.x)
            tryX(bounds.width - c.x)
            tryY(c.y)
        }
        // The controls are drawn in the stream view, which this layer covers exactly
        for value in osc?.controlCenters() ?? [] {
            let c = value.cgPointValue
            tryX(c.x)
            tryY(c.y)
        }
        return (CGPoint(x: gx ?? p.x, y: gy ?? p.y), gx, gy)
    }

    private func drawGuides(x: CGFloat?, y: CGFloat?) {
        guard x != nil || y != nil else {
            guideLayer.removeFromSuperlayer()
            return
        }
        let path = UIBezierPath()
        if let x {
            path.move(to: CGPoint(x: x, y: bounds.minY))
            path.addLine(to: CGPoint(x: x, y: bounds.maxY))
        }
        if let y {
            path.move(to: CGPoint(x: bounds.minX, y: y))
            path.addLine(to: CGPoint(x: bounds.maxX, y: y))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        guideLayer.path = path.cgPath
        if guideLayer.superlayer == nil { layer.addSublayer(guideLayer) }
        CATransaction.commit()
    }

    /// Dashed outline and resize handle on the selected widget
    private func updateEditorOverlay() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard isEditing, let id = selectedID, let view = views[id] else {
            selectionLayer.removeFromSuperlayer()
            handleLayer.removeFromSuperlayer()
            return
        }
        selectionLayer.path = UIBezierPath(roundedRect: view.frame.insetBy(dx: -6, dy: -6), cornerRadius: 10).cgPath
        if let h = handleCenter {
            handleLayer.path = UIBezierPath(ovalIn: CGRect(x: h.x - 8, y: h.y - 8, width: 16, height: 16)).cgPath
        }
        layer.addSublayer(selectionLayer)
        layer.addSublayer(handleLayer)
    }
}

private extension CGPoint {
    func relative(to view: UIView?) -> CGPoint {
        guard let view else { return self }
        return CGPoint(x: x - view.frame.minX, y: y - view.frame.minY)
    }
}
