//
//  ControllerNavigator.swift
//  MoonLume
//
//  Drive the launcher, Settings and sheets with a game controller. An iPhone has no focus engine
//  a game controller can drive (UIFocusSystem and SwiftUI's focus follow a hardware keyboard on
//  iPad and Mac only), so this polls the current pad and moves its own focus ring between
//  targets: SwiftUI views marked with .navTarget, and the UIKit controls SwiftUI draws Form rows
//  with (switches, segmented pickers, sliders, buttons).
//
//  D-pad or left stick moves, A activates, B goes back or closes, X opens options for the focused
//  item, Y or Menu opens Settings, L1/R1 jump between the computer list and the apps. While a
//  system alert is up, its actions sit on the face buttons and the hint bar names them. The ring
//  and hints show once the controller is used and hide at the next touch.
//
//  Behaviour modelled on VoidLink's ControllerNavigator (GPLv3); the code is MoonLume's own.
//

import GameController
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

enum ControllerNavSettings {
    static let enabledKey = "mnControllerNavigation"
    static let hintsKey = "mnControllerHints"
    static let wizardShownKey = "mnControllerWizardShown"

    /// On by default: it only acts on controller input, and nothing else lets a controller reach the launcher.
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    static var hints: Bool { UserDefaults.standard.object(forKey: hintsKey) as? Bool ?? true }
}

// MARK: - Markers placed by SwiftUI views

/// A face-button action for the system alert a screen is showing.
struct NavDialogAction {
    enum Button { case a, b, x, y }
    let button: Button
    let title: String
    let perform: () -> Void
}

/// An invisible UIView behind a SwiftUI view, found by the navigator's scan of the window.
final class NavMarkerView: UIView {
    enum Role {
        /// Focusable. pane 0 is the computer list, 1 the apps (L1/R1).
        case target(pane: Int, activate: () -> Void, options: (() -> Void)?)
        /// B and Y/Menu for the screen it's in.
        case screen(back: (() -> Void)?, settings: (() -> Void)?)
        /// Face buttons for the alert this screen presents, nil while none is up.
        case dialog([NavDialogAction]?)
    }

    var role = Role.dialog(nil)
}

private struct NavMarker: UIViewRepresentable {
    let role: NavMarkerView.Role

    func makeUIView(context: Context) -> NavMarkerView {
        let view = NavMarkerView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: NavMarkerView, context: Context) {
        view.role = role
    }
}

extension View {
    /// Lets a controller focus this view; A runs `activate`, X runs `options`.
    func navTarget(pane: Int = 1, options: (() -> Void)? = nil, activate: @escaping () -> Void) -> some View {
        background(NavMarker(role: .target(pane: pane, activate: activate, options: options)))
    }

    /// What B and Y/Menu do on this screen.
    func navScreen(back: (() -> Void)? = nil, settings: (() -> Void)? = nil) -> some View {
        background(NavMarker(role: .screen(back: back, settings: settings)))
    }

    /// Face buttons for the alert or confirmation dialog this view presents (nil while none is up).
    func navDialog(_ actions: [NavDialogAction]?) -> some View {
        background(NavMarker(role: .dialog(actions)))
    }
}

// MARK: - Overlay: ring, hints, quick menu

struct NavHint: Hashable {
    let symbol: String
    let label: String
}

final class NavOverlayModel: ObservableObject {
    @Published var ring: CGRect?
    @Published var hints: [NavHint] = []
    @Published var wheel: [MNQuickMenuItem]?
    @Published var wheelSelection: Int?
    @Published var wheelHints: [NavHint] = []
}

private struct NavOverlayView: View {
    @ObservedObject var model: NavOverlayModel

    var body: some View {
        ZStack {
            Color.clear
            if let ring = model.ring {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 2.5)
                    .shadow(color: Theme.accent.opacity(0.55), radius: 6)
                    .frame(width: ring.width + 8, height: ring.height + 8)
                    .position(x: ring.midX, y: ring.midY)
                    .animation(.easeOut(duration: 0.12), value: ring)
            }
            if let wheel = model.wheel {
                Color.black.opacity(0.35)
                QuickMenuWheel(items: wheel, selection: model.wheelSelection, hints: model.wheelHints)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if !model.hints.isEmpty && model.wheel == nil {
                NavHintBar(hints: model.hints).padding(.bottom, 10)
            }
        }
        .allowsHitTesting(false)
    }
}

struct NavHintBar: View {
    let hints: [NavHint]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(hints, id: \.self) { hint in
                HStack(spacing: 5) {
                    Image(systemName: hint.symbol).font(.system(size: 15, weight: .semibold))
                    Text(hint.label).font(.system(size: 13, weight: .medium))
                }
            }
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.black.opacity(0.8)))
        .overlay(Capsule().strokeBorder(Theme.lineStrong))
        .accessibilityHidden(true)
    }
}

/// Fails at the first touch, after telling the navigator: touch input hides the ring.
private final class TouchWatcher: UIGestureRecognizer {
    var onTouch: () -> Void = {}

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        onTouch()
        state = .failed
    }
}

// MARK: - Navigator

@objc final class MNControllerNav: NSObject, ObservableObject {
    @objc static let shared = MNControllerNav()

    /// LauncherView presents the controller setup sheet while this is set.
    @Published var showWizard = false
    /// X on an app or a computer: LauncherView shows its options while set.
    @Published var optionsApp: TemporaryApp?
    @Published var optionsHost: TemporaryHost?

    let overlay = NavOverlayModel()

    enum Direction { case up, down, left, right }

    private struct Pad: Equatable {
        var a = false, b = false, x = false, y = false, menu = false, l1 = false, r1 = false
        var direction: Direction?

        init() {}

        init(_ pad: GCExtendedGamepad) {
            a = pad.buttonA.isPressed
            b = pad.buttonB.isPressed
            x = pad.buttonX.isPressed
            y = pad.buttonY.isPressed
            menu = pad.buttonMenu.isPressed
            l1 = pad.leftShoulder.isPressed
            r1 = pad.rightShoulder.isPressed
            let dx = pad.dpad.xAxis.value != 0 ? pad.dpad.xAxis.value : pad.leftThumbstick.xAxis.value
            let dy = pad.dpad.yAxis.value != 0 ? pad.dpad.yAxis.value : pad.leftThumbstick.yAxis.value
            if max(abs(dx), abs(dy)) >= 0.5 {
                direction = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .up : .down)
            }
        }
    }

    private var started = false
    private var timer: Timer?
    private var previous = Pad()
    private var heldDirection: Direction?
    private var nextRepeat: CFTimeInterval = 0
    /// Set after a move found nothing and scrolled instead: try again once the new rows are laid out.
    private var retryDirection: Direction?
    private var sliderNudge: (slider: UISlider, from: Float, step: Float, raw: Float)?
    private var active = false
    private weak var focused: UIView?
    private var lastFocusFrame: CGRect?
    private var pendingWizard = false
    private var overlayHost: UIViewController?
    private weak var watchedWindow: UIWindow?

    /// The stream, while one runs (set by StreamFrameViewController through MNQuickMenu).
    weak var streamController: UIViewController?

    // Steady-state repeat after the first step, VoidLink uses about the same (0.23 s / 0.177 s)
    private let repeatDelay: CFTimeInterval = 0.32
    private let repeatInterval: CFTimeInterval = 0.13

    var window: UIWindow? { LauncherModel.current?.window }

    func start() {
        guard !started else { return }
        started = true
        #if DEBUG
        Self.selfCheck()
        #endif
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(controllerConnected), name: .GCControllerDidConnect, object: nil)
        center.addObserver(self, selector: #selector(update), name: .GCControllerDidDisconnect, object: nil)
        center.addObserver(self, selector: #selector(update), name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(update), name: UIApplication.willResignActiveNotification, object: nil)
        if Self.pad != nil {
            controllerConnected()
        }
        update()
    }

    static var pad: GCExtendedGamepad? {
        GCController.current?.extendedGamepad ?? GCController.controllers().lazy.compactMap(\.extendedGamepad).first
    }

    @objc private func controllerConnected() {
        if !UserDefaults.standard.bool(forKey: ControllerNavSettings.wizardShownKey) {
            pendingWizard = true
        }
        update()
    }

    /// Poll at 60 Hz while a controller is connected and the app is active.
    @objc private func update() {
        let run = Self.pad != nil && UIApplication.shared.applicationState != .background
        if run && timer == nil {
            let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if !run {
            timer?.invalidate()
            timer = nil
            deactivate()
        }
    }

    /// True while a sheet over the stream (Settings) has the controller: the game must not see it.
    @objc var drivesUIOverStream: Bool {
        guard let stream = streamController, ControllerNavSettings.enabled, let window else { return false }
        let top = Self.topController(window)
        return top !== stream && !(top is UIAlertController)
    }

    static func topController(_ window: UIWindow) -> UIViewController? {
        var top = window.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top
    }

    private func tick() {
        guard let pad = Self.pad, let window, let top = Self.topController(window) else {
            deactivate()
            return
        }
        let state = Pad(pad)
        let old = previous
        previous = state
        installOverlay(in: window)

        // Over the stream itself the quick menu owns the pad
        if let stream = streamController, top === stream {
            deactivate()
            return
        }
        if pendingWizard && streamController == nil && top === window.rootViewController {
            pendingWizard = false
            UserDefaults.standard.set(true, forKey: ControllerNavSettings.wizardShownKey)
            showWizard = true
        }
        guard ControllerNavSettings.enabled else {
            deactivate()
            return
        }
        if state != old {
            active = true
        }
        guard active else { return }

        func pressed(_ key: KeyPath<Pad, Bool>) -> Bool { state[keyPath: key] && !old[keyPath: key] }

        if let alert = top as? UIAlertController {
            drive(alert: alert, pad: pad, pressed: pressed)
            return
        }
        guard let container = top.viewIfLoaded, container.window != nil else { return }

        var targets: [UIView] = []
        var screen: (back: (() -> Void)?, settings: (() -> Void)?) = (nil, nil)
        collect(container, window: window, targets: &targets, screen: &screen)

        if let focused, !targets.contains(where: { $0 === focused }) {
            self.focused = nil
        }
        if focused == nil {
            focused = initialTarget(targets)
        }

        let now = CACurrentMediaTime()
        if let retry = retryDirection {
            retryDirection = nil
            move(retry, targets: targets, allowScroll: false)
        } else if let direction = state.direction {
            if direction != heldDirection {
                move(direction, targets: targets, allowScroll: true)
                nextRepeat = now + repeatDelay
            } else if now >= nextRepeat {
                move(direction, targets: targets, allowScroll: true)
                nextRepeat = now + repeatInterval
            }
        }
        heldDirection = state.direction
        continueSliderNudge()

        if pressed(\.a), let focused {
            activate(focused)
        } else if pressed(\.b) {
            screen.back?()
        } else if pressed(\.x), let marker = focused as? NavMarkerView, case .target(_, _, let options?) = marker.role {
            options()
        } else if pressed(\.y) || pressed(\.menu) {
            screen.settings?()
        } else if pressed(\.l1) {
            if !jump(toPane: 0, targets: targets) {
                screen.back?()
            }
        } else if pressed(\.r1) {
            if !jump(toPane: 1, targets: targets), let focused {
                activate(focused)
            }
        }

        let frame = focused.map { $0.convert($0.bounds, to: window) }
        if let frame {
            lastFocusFrame = frame
        }
        if overlay.ring != frame {
            overlay.ring = frame
        }
        setHints(screenHints(pad: pad, back: screen.back != nil, settings: screen.settings != nil))
    }

    // MARK: Alerts

    private func drive(alert: UIAlertController, pad: GCExtendedGamepad, pressed: (KeyPath<Pad, Bool>) -> Bool) {
        if overlay.ring != nil {
            overlay.ring = nil
        }
        var actions: [NavDialogAction]?
        if let presenter = alert.presentingViewController?.viewIfLoaded {
            actions = dialogActions(in: presenter)
        }
        guard let actions else {
            setHints([])
            return
        }
        setHints(actions.map { NavHint(symbol: Self.symbol(for: $0.button, pad: pad), label: $0.title) })
        let fired = actions.first {
            switch $0.button {
            case .a: return pressed(\.a)
            case .b: return pressed(\.b)
            case .x: return pressed(\.x)
            case .y: return pressed(\.y)
            }
        }
        fired?.perform()
    }

    private func dialogActions(in view: UIView) -> [NavDialogAction]? {
        if let marker = view as? NavMarkerView, case .dialog(let actions?) = marker.role {
            return actions
        }
        for sub in view.subviews {
            if let found = dialogActions(in: sub) {
                return found
            }
        }
        return nil
    }

    // MARK: Targets

    private func collect(_ view: UIView, window: UIWindow, targets: inout [UIView],
                         screen: inout (back: (() -> Void)?, settings: (() -> Void)?)) {
        if view.isHidden || view.alpha < 0.02 {
            return
        }
        if let marker = view as? NavMarkerView {
            switch marker.role {
            case .target:
                if isOnScreen(marker, window: window) { targets.append(marker) }
            case .screen(let back, let settings):
                // The first one found wins: the screen's own, not one from a view under it
                if screen.back == nil && screen.settings == nil {
                    screen = (back, settings)
                }
            case .dialog:
                break
            }
            return
        }
        if let control = view as? UIControl,
           control is UISwitch || control is UISegmentedControl || control is UISlider || control is UIButton {
            if control.isEnabled && control.isUserInteractionEnabled && isOnScreen(control, window: window) {
                targets.append(control)
            }
            return
        }
        for sub in view.subviews {
            collect(sub, window: window, targets: &targets, screen: &screen)
        }
    }

    private func isOnScreen(_ view: UIView, window: UIWindow) -> Bool {
        let frame = view.convert(view.bounds, to: window)
        return frame.width >= 4 && frame.height >= 4 && frame.intersects(window.bounds)
    }

    private func pane(of view: UIView) -> Int? {
        if let marker = view as? NavMarkerView, case .target(let pane, _, _) = marker.role {
            return pane
        }
        return nil
    }

    private func frame(_ view: UIView) -> CGRect {
        view.convert(view.bounds, to: nil)
    }

    /// Nearest to where the ring last was; otherwise the first app (or row) at the top left.
    private func initialTarget(_ targets: [UIView]) -> UIView? {
        if let last = lastFocusFrame {
            return targets.min { distance(frame($0), last) < distance(frame($1), last) }
        }
        let preferred = targets.filter { pane(of: $0) == 1 }
        let pool = preferred.isEmpty ? targets.filter { pane(of: $0) != nil } : preferred
        return (pool.isEmpty ? targets : pool).min {
            let a = frame($0), b = frame($1)
            return (a.minY, a.minX) < (b.minY, b.minX)
        }
    }

    private func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        hypot(a.midX - b.midX, a.midY - b.midY)
    }

    private func jump(toPane target: Int, targets: [UIView]) -> Bool {
        guard focused.flatMap(pane(of:)) != target else { return false }
        let candidates = targets.filter { pane(of: $0) == target }
        guard !candidates.isEmpty else { return false }
        let reference = focused.map(frame) ?? .zero
        focus(candidates.min { abs(frame($0).midY - reference.midY) < abs(frame($1).midY - reference.midY) })
        return true
    }

    private func move(_ direction: Direction, targets: [UIView], allowScroll: Bool) {
        guard let current = focused else {
            focus(initialTarget(targets))
            return
        }
        // Left/right adjusts a slider or segmented picker instead of leaving it
        if direction == .left || direction == .right {
            let sign: Float = direction == .right ? 1 : -1
            if let slider = current as? UISlider {
                startSliderNudge(slider, sign: sign)
                return
            }
            if let segmented = current as? UISegmentedControl {
                stepSegment(segmented, by: Int(sign), wrap: false)
                return
            }
        }
        let others = targets.filter { $0 !== current }
        if let index = Self.nearest(from: frame(current), toward: direction, among: others.map(frame)) {
            focus(others[index])
        } else if allowScroll, scroll(from: current, toward: direction) {
            retryDirection = direction
        }
    }

    private func focus(_ view: UIView?) {
        guard let view else { return }
        focused = view
        sliderNudge = nil
        if let scrollView = enclosingScrollView(of: view) {
            let rect = view.convert(view.bounds, to: scrollView).insetBy(dx: 0, dy: -20)
            scrollView.scrollRectToVisible(rect, animated: true)
        }
    }

    private func enclosingScrollView(of view: UIView) -> UIScrollView? {
        var current = view.superview
        while let v = current {
            if let scrollView = v as? UIScrollView, scrollView.isScrollEnabled {
                return scrollView
            }
            current = v.superview
        }
        return nil
    }

    /// Nothing further that way on screen: scroll a page so lazy rows load, true if it moved.
    private func scroll(from view: UIView, toward direction: Direction) -> Bool {
        guard let scrollView = enclosingScrollView(of: view) else { return false }
        let inset = scrollView.adjustedContentInset
        var offset = scrollView.contentOffset
        let pageY = scrollView.bounds.height * 0.6, pageX = scrollView.bounds.width * 0.6
        switch direction {
        case .down:
            offset.y = min(offset.y + pageY, max(-inset.top, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height))
        case .up:
            offset.y = max(offset.y - pageY, -inset.top)
        case .right:
            offset.x = min(offset.x + pageX, max(-inset.left, scrollView.contentSize.width + inset.right - scrollView.bounds.width))
        case .left:
            offset.x = max(offset.x - pageX, -inset.left)
        }
        guard offset != scrollView.contentOffset else { return false }
        scrollView.setContentOffset(offset, animated: false)
        return true
    }

    /// The closest frame in `direction`, favouring ones in line with `from` (grid rows and columns).
    static func nearest(from: CGRect, toward direction: Direction, among frames: [CGRect]) -> Int? {
        // Rotate everything so the move is downward
        func turn(_ r: CGRect) -> CGRect {
            switch direction {
            case .down: return r
            case .up: return CGRect(x: r.minX, y: -r.maxY, width: r.width, height: r.height)
            case .right: return CGRect(x: r.minY, y: r.minX, width: r.height, height: r.width)
            case .left: return CGRect(x: r.minY, y: -r.maxX, width: r.height, height: r.width)
            }
        }
        let cur = turn(from)
        var best: (index: Int, score: CGFloat)?
        for (index, frame) in frames.enumerated() {
            let f = turn(frame)
            guard f.midY > cur.midY + 1, f.minY >= cur.midY - 1 else { continue }
            let ahead = max(0, f.minY - cur.maxY)
            let aside = max(0, max(f.minX - cur.maxX, cur.minX - f.maxX))
            let score = ahead + aside * 3 + abs(f.midX - cur.midX) * 0.1
            if best == nil || score < best!.score {
                best = (index, score)
            }
        }
        return best?.index
    }

    // MARK: Controls

    private func activate(_ view: UIView) {
        switch view {
        case let marker as NavMarkerView:
            if case .target(_, let activate, _) = marker.role {
                activate()
            }
        case let toggle as UISwitch:
            toggle.setOn(!toggle.isOn, animated: true)
            toggle.sendActions(for: .valueChanged)
        case let segmented as UISegmentedControl:
            stepSegment(segmented, by: 1, wrap: true)
        case let button as UIButton:
            if #available(iOS 17.4, *) {
                button.performPrimaryAction()
            } else {
                button.sendActions(for: .touchUpInside)
            }
        default:
            break
        }
    }

    private func stepSegment(_ control: UISegmentedControl, by delta: Int, wrap: Bool) {
        let count = control.numberOfSegments
        guard count > 1 else { return }
        var index = max(control.selectedSegmentIndex, 0)
        for _ in 0..<count {
            index += delta
            if wrap {
                index = (index + count) % count
            } else if index < 0 || index >= count {
                return
            }
            if control.isEnabledForSegment(at: index) {
                break
            }
        }
        guard index != control.selectedSegmentIndex else { return }
        control.selectedSegmentIndex = index
        control.sendActions(for: .valueChanged)
    }

    /// SwiftUI snaps a slider to its step, which the UISlider doesn't know: keep nudging the raw
    /// value until the shown value changes, so one press is one step whatever the step size.
    private func startSliderNudge(_ slider: UISlider, sign: Float) {
        let range = slider.maximumValue - slider.minimumValue
        guard range > 0 else { return }
        sliderNudge = (slider, slider.value, sign * range / 50, slider.value)
        continueSliderNudge()
    }

    private func continueSliderNudge() {
        guard var nudge = sliderNudge else { return }
        let slider = nudge.slider
        // SwiftUI has redrawn the slider at the stepped value: done once it shows a change
        if slider.value != nudge.from {
            sliderNudge = nil
            return
        }
        nudge.raw = min(max(nudge.raw + nudge.step, slider.minimumValue), slider.maximumValue)
        if nudge.raw == slider.value && (nudge.raw == slider.minimumValue || nudge.raw == slider.maximumValue) {
            sliderNudge = nil
            return
        }
        slider.value = nudge.raw
        slider.sendActions(for: .valueChanged)
        sliderNudge = nudge
        // Over half the range without a change: a slider that won't move, stop
        if abs(nudge.raw - nudge.from) > abs(nudge.step) * 25 {
            sliderNudge = nil
        }
    }

    // MARK: Ring, hints, overlay

    private func deactivate() {
        heldDirection = nil
        retryDirection = nil
        sliderNudge = nil
        if active {
            active = false
        }
        if overlay.ring != nil {
            overlay.ring = nil
        }
        setHints([])
    }

    private func setHints(_ hints: [NavHint]) {
        let shown = ControllerNavSettings.hints && active ? hints : []
        if overlay.hints != shown {
            overlay.hints = shown
        }
    }

    private func screenHints(pad: GCExtendedGamepad, back: Bool, settings: Bool) -> [NavHint] {
        var hints: [NavHint] = []
        switch focused {
        case is UISlider, is UISegmentedControl:
            hints.append(NavHint(symbol: pad.dpad.sfSymbolsName ?? "dpad", label: "Adjust"))
        case is UISwitch:
            hints.append(NavHint(symbol: Self.symbol(for: .a, pad: pad), label: "Toggle"))
        case .some:
            hints.append(NavHint(symbol: Self.symbol(for: .a, pad: pad), label: "Select"))
        case .none:
            break
        }
        if let marker = focused as? NavMarkerView, case .target(_, _, .some) = marker.role {
            hints.append(NavHint(symbol: Self.symbol(for: .x, pad: pad), label: "Options"))
        }
        if settings {
            hints.append(NavHint(symbol: Self.symbol(for: .y, pad: pad), label: "Settings"))
        }
        if back {
            hints.append(NavHint(symbol: Self.symbol(for: .b, pad: pad), label: "Back"))
        }
        return hints
    }

    /// The pad's own glyph (a cross on a PlayStation pad), or a lettered circle.
    static func symbol(for button: NavDialogAction.Button, pad: GCExtendedGamepad?) -> String {
        switch button {
        case .a: return pad?.buttonA.sfSymbolsName ?? "a.circle"
        case .b: return pad?.buttonB.sfSymbolsName ?? "b.circle"
        case .x: return pad?.buttonX.sfSymbolsName ?? "x.circle"
        case .y: return pad?.buttonY.sfSymbolsName ?? "y.circle"
        }
    }

    /// One non-interactive view on top of the window: ring, hint bar and quick menu wheel.
    func installOverlay(in window: UIWindow) {
        if overlayHost == nil {
            let host = UIHostingController(rootView: NavOverlayView(model: overlay))
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlayHost = host
        }
        guard let overlayView = overlayHost?.view else { return }
        if overlayView.superview !== window {
            overlayView.frame = window.bounds
            window.addSubview(overlayView)
        } else if window.subviews.last !== overlayView {
            window.bringSubviewToFront(overlayView)
        }
        if watchedWindow !== window {
            watchedWindow = window
            let watcher = TouchWatcher(target: nil, action: nil)
            watcher.cancelsTouchesInView = false
            watcher.delaysTouchesBegan = false
            watcher.delaysTouchesEnded = false
            watcher.onTouch = { [weak self] in self?.deactivate() }
            window.addGestureRecognizer(watcher)
        }
    }

    // MARK: Self-check (Debug builds, once at start)

    #if DEBUG
    static func selfCheck() {
        let cur = CGRect(x: 100, y: 100, width: 50, height: 50)
        let below = CGRect(x: 100, y: 200, width: 50, height: 50)
        let belowRight = CGRect(x: 200, y: 160, width: 50, height: 50)
        let right = CGRect(x: 170, y: 100, width: 50, height: 50)
        let above = CGRect(x: 100, y: 20, width: 50, height: 50)
        let all = [below, belowRight, right, above]
        assert(nearest(from: cur, toward: .down, among: all) == 0, "down picks the tile in the same column")
        assert(nearest(from: cur, toward: .right, among: all) == 2, "right picks the tile in the same row")
        assert(nearest(from: cur, toward: .up, among: all) == 3)
        assert(nearest(from: cur, toward: .left, among: all) == nil)
        assert(QuickMenuGeometry.sector(x: 0, y: 1, count: 8) == 0, "stick up is the top item")
        assert(QuickMenuGeometry.sector(x: 1, y: 0, count: 8) == 2, "right is a quarter turn clockwise")
        assert(QuickMenuGeometry.sector(x: 0, y: -1, count: 8) == 4)
        assert(QuickMenuGeometry.sector(x: -1, y: 0.05, count: 8) == 6)
        assert(QuickMenuGeometry.sector(x: -0.2, y: 1, count: 8) == 0, "slightly left of up is still the top item")
    }
    #endif
}
