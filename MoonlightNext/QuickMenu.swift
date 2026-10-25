//
//  QuickMenu.swift
//  MoonLume
//
//  The in-stream quick menu: hold a chosen controller button (Guide by default) for a wheel of
//  stream actions. A stick or the d-pad picks, releasing the button chooses (Quit needs A),
//  B cancels. The held button never reaches the game; a short press is replayed as a tap.
//  ControllerSupport asks intercept(_:) on every pad change. The items come from
//  StreamFrameViewController, the same actions as its ••• menu.
//
//  Behaviour modelled on VoidLink's radial menu (RadialMenuOverlayView.swift, GPLv3); the code is
//  MoonLume's own.
//

import GameController
import SwiftUI
import UIKit

enum QuickMenuSettings {
    enum Button: Int, CaseIterable {
        case guide = 0, selectStart = 1, select = 2, off = 3

        var label: String {
            switch self {
            case .guide: return "Guide"
            case .selectStart: return "Select + Start"
            case .select: return "Select"
            case .off: return "Off"
            }
        }
    }

    static let buttonKey = "mnQuickMenuButton"

    static var button: Button { Button(rawValue: UserDefaults.standard.integer(forKey: buttonKey)) ?? .guide }

    /// What to call the button on a given pad (Guide falls back to Select + Start without one).
    static func buttonName(for pad: GCExtendedGamepad?) -> String {
        if button == .guide, let pad, pad.buttonHome == nil {
            return Button.selectStart.label
        }
        return button.label
    }
}

@objc final class MNQuickMenuItem: NSObject {
    let title: String
    let symbol: String
    let destructive: Bool
    let handler: () -> Void

    @objc init(title: String, symbol: String, destructive: Bool, handler: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.destructive = destructive
        self.handler = handler
    }
}

enum QuickMenuGeometry {
    /// The item a stick at (x, y), y up, points at: item 0 at the top, then clockwise.
    static func sector(x: Double, y: Double, count: Int) -> Int {
        let degrees = atan2(x, y) * 180 / .pi
        let width = 360 / Double(count)
        let shifted = (degrees + width / 2 + 360).truncatingRemainder(dividingBy: 360)
        return Int(shifted / width) % count
    }

    /// Where item `index` sits on a circle of `radius`, in a y-down view.
    static func point(index: Int, count: Int, radius: CGFloat, center: CGPoint) -> CGPoint {
        let angle = Double(index) * 2 * .pi / Double(count)
        return CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
    }
}

@objc final class MNQuickMenu: NSObject {
    @objc static let shared = MNQuickMenu()

    /// passing: the button joined a chord with another button, so it goes to the game until released
    private enum Phase { case idle, holding, open, draining, passing }

    /// How long the button is held before the menu opens
    private let holdTime = 0.45
    /// Stick travel that picks an item; smaller movements (and the stick recentring) keep the pick
    private let pickThreshold = 0.5

    private var items: (() -> [MNQuickMenuItem])?
    private var phase = Phase.idle
    private var hold: DispatchWorkItem?
    private weak var pad: GCExtendedGamepad?
    private var trigger: (buttons: [GCControllerButtonInput], flags: Int32, replayTap: Bool) = ([], 0, false)
    private var tap: Int32 = 0
    private var shown: [MNQuickMenuItem] = []
    private var selection: Int?

    private override init() {
        super.init()
        // Only the pad that opened the menu can close it: if it goes away (battery, Bluetooth),
        // reset instead of leaving the wheel up or the menu stuck for the rest of the stream
        NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] note in
            guard let self, self.phase != .idle else { return }
            let gone = (note.object as? GCController)?.extendedGamepad
            if self.pad == nil || gone == nil || gone === self.pad {
                self.reset()
            }
        }
    }

    private func reset() {
        close()
        phase = .idle
    }

    /// The stream started: `items` builds the wheel each time it opens.
    @objc func attach(_ stream: UIViewController, items: @escaping () -> [MNQuickMenuItem]) {
        MNControllerNav.shared.streamController = stream
        MNControllerNav.shared.start()
        self.items = items
    }

    @objc func detach() {
        close()
        phase = .idle
        items = nil
        MNControllerNav.shared.streamController = nil
    }

    /// For each input change on a physical pad, on the main thread. Returns the button flags
    /// (Limelight.h) to keep from the host, or -1 to keep the whole pad from it.
    @objc func intercept(_ gamepad: GCExtendedGamepad) -> Int32 {
        if MNControllerNav.shared.drivesUIOverStream {
            if phase != .idle {
                close()
                phase = .idle
            }
            return -1
        }
        if phase != .idle && pad == nil {
            reset()
        }
        switch phase {
        case .open:
            guard gamepad === pad else { return 0 }
            if gamepad.buttonB.isPressed {
                close()
            } else if gamepad.buttonA.isPressed {
                close(choosing: true, allowDestructive: true)
            } else {
                pick(with: gamepad)
                if !trigger.buttons.allSatisfy(\.isPressed) {
                    close(choosing: true, allowDestructive: false)
                }
            }
            return -1
        case .draining:
            // After the menu, the buttons that closed it stay away from the game until released
            guard gamepad === pad else { return 0 }
            if trigger.buttons.contains(where: \.isPressed) || gamepad.buttonA.isPressed || gamepad.buttonB.isPressed {
                return -1
            }
            phase = .idle
            return 0
        case .passing:
            guard gamepad === pad else { return 0 }
            if !trigger.buttons.contains(where: \.isPressed) {
                phase = .idle
            }
            return 0
        case .holding:
            guard gamepad === pad else { return 0 }
            if trigger.buttons.allSatisfy(\.isPressed) {
                if otherButtonPressed(gamepad) {
                    // A chord on the host (Guide + RB in Steam): give the game the button now
                    hold?.cancel()
                    hold = nil
                    phase = .passing
                    return 0
                }
                return trigger.flags
            }
            // Let go before the menu opened: the game gets the press after all
            hold?.cancel()
            hold = nil
            phase = .idle
            if trigger.replayTap {
                tap = trigger.flags
            }
            return trigger.flags
        case .idle:
            guard items != nil, let resolved = resolveTrigger(gamepad), resolved.buttons.allSatisfy(\.isPressed) else {
                return 0
            }
            trigger = resolved
            pad = gamepad
            phase = .holding
            let work = DispatchWorkItem { [weak self] in self?.open() }
            hold = work
            DispatchQueue.main.asyncAfter(deadline: .now() + holdTime, execute: work)
            return resolved.flags
        }
    }

    /// A short press of the menu button to send to the host as a tap (its flags), or 0.
    @objc func takeTap() -> Int32 {
        defer { tap = 0 }
        return tap
    }

    private func otherButtonPressed(_ gamepad: GCExtendedGamepad) -> Bool {
        let buttons: [GCControllerButtonInput?] = [
            gamepad.buttonA, gamepad.buttonB, gamepad.buttonX, gamepad.buttonY,
            gamepad.leftShoulder, gamepad.rightShoulder, gamepad.leftTrigger, gamepad.rightTrigger,
            gamepad.dpad.up, gamepad.dpad.down, gamepad.dpad.left, gamepad.dpad.right,
            gamepad.leftThumbstickButton, gamepad.rightThumbstickButton,
            gamepad.buttonMenu, gamepad.buttonOptions, gamepad.buttonHome,
        ]
        return buttons.contains { button in
            guard let button, button.isPressed else { return false }
            return !trigger.buttons.contains { $0 === button }
        }
    }

    private func resolveTrigger(_ pad: GCExtendedGamepad) -> (buttons: [GCControllerButtonInput], flags: Int32, replayTap: Bool)? {
        // SPECIAL_FLAG, PLAY_FLAG, BACK_FLAG
        let special: Int32 = 0x0400, play: Int32 = 0x0010, back: Int32 = 0x0020
        var choice = QuickMenuSettings.button
        if choice == .guide && pad.buttonHome == nil {
            choice = .selectStart
        }
        switch choice {
        case .off:
            return nil
        case .guide:
            guard let home = pad.buttonHome else { return nil }
            return ([home], special, true)
        case .selectStart:
            // A chord isn't replayed: Select already reached the game before Start joined it
            guard let options = pad.buttonOptions else { return nil }
            return ([options, pad.buttonMenu], play | back, false)
        case .select:
            guard let options = pad.buttonOptions else { return nil }
            return ([options], back, true)
        }
    }

    private func open() {
        guard phase == .holding else { return }
        guard let pad else {
            // The pad went away while the button was held
            reset()
            return
        }
        guard trigger.buttons.allSatisfy(\.isPressed),
              let stream = MNControllerNav.shared.streamController, stream.presentedViewController == nil,
              let window = MNControllerNav.shared.window, let items else { return }
        shown = items()
        guard !shown.isEmpty else { return }
        hold = nil
        phase = .open
        selection = nil
        let nav = MNControllerNav.shared
        nav.installOverlay(in: window)
        nav.overlay.wheelSelection = nil
        nav.overlay.wheelHints = [
            NavHint(symbol: MNControllerNav.symbol(for: .a, pad: pad), label: "Choose"),
            NavHint(symbol: MNControllerNav.symbol(for: .b, pad: pad), label: "Cancel"),
        ]
        nav.overlay.wheel = shown
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func pick(with gamepad: GCExtendedGamepad) {
        var x = Double(gamepad.dpad.xAxis.value), y = Double(gamepad.dpad.yAxis.value)
        if x == 0 && y == 0 {
            let left = gamepad.leftThumbstick, right = gamepad.rightThumbstick
            let useLeft = hypot(Double(left.xAxis.value), Double(left.yAxis.value))
                >= hypot(Double(right.xAxis.value), Double(right.yAxis.value))
            let stick = useLeft ? left : right
            x = Double(stick.xAxis.value)
            y = Double(stick.yAxis.value)
        }
        guard hypot(x, y) >= pickThreshold, !shown.isEmpty else { return }
        let index = QuickMenuGeometry.sector(x: x, y: y, count: shown.count)
        if index != selection {
            selection = index
            MNControllerNav.shared.overlay.wheelSelection = index
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func close(choosing: Bool = false, allowDestructive: Bool = false) {
        hold?.cancel()
        hold = nil
        let item = selection.flatMap { shown.indices.contains($0) ? shown[$0] : nil }
        if phase == .open {
            phase = .draining
        }
        let overlay = MNControllerNav.shared.overlay
        if overlay.wheel != nil {
            overlay.wheel = nil
            overlay.wheelSelection = nil
        }
        shown = []
        selection = nil
        if choosing, let item, !item.destructive || allowDestructive {
            DispatchQueue.main.async { item.handler() }
        }
    }
}

// MARK: - Wheel

struct QuickMenuWheel: View {
    let items: [MNQuickMenuItem]
    let selection: Int?
    let hints: [NavHint]

    private let diameter: CGFloat = 250
    private let destructiveColor = Color(hex: 0xFF6B6B)

    private var selected: MNQuickMenuItem? {
        selection.flatMap { items.indices.contains($0) ? items[$0] : nil }
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.black.opacity(0.85))
                Circle().strokeBorder(Theme.lineStrong)
                if let selection, items.count > 1 {
                    WheelSector(index: selection, count: items.count)
                        .fill((selected?.destructive == true ? destructiveColor : Theme.accent).opacity(0.25))
                }
                ForEach(items.indices, id: \.self) { index in
                    Image(systemName: items[index].symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(index == selection ? (items[index].destructive ? destructiveColor : Theme.accent)
                                         : (items[index].destructive ? destructiveColor.opacity(0.8) : Theme.text))
                        .position(QuickMenuGeometry.point(index: index, count: items.count, radius: diameter * 0.37,
                                                          center: CGPoint(x: diameter / 2, y: diameter / 2)))
                }
                VStack(spacing: 3) {
                    Text(selected?.title ?? "Quick menu")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(selected?.destructive == true ? "Press A" : (selected == nil ? "Tilt a stick" : "Release to choose"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(width: diameter * 0.42)
            }
            .frame(width: diameter, height: diameter)
            NavHintBar(hints: hints)
        }
        .animation(.easeOut(duration: 0.1), value: selection)
        .accessibilityHidden(true)
    }
}

private struct WheelSector: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let width = 360 / Double(count)
        // Item 0 is at the top (-90° here), then clockwise
        let mid = -90 + Double(index) * width
        var path = Path()
        path.addArc(center: center, radius: radius - 3, startAngle: .degrees(mid - width / 2),
                    endAngle: .degrees(mid + width / 2), clockwise: false)
        path.addArc(center: center, radius: radius * 0.52, startAngle: .degrees(mid + width / 2),
                    endAngle: .degrees(mid - width / 2), clockwise: true)
        path.closeSubpath()
        return path
    }
}
