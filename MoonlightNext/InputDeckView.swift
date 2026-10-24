//
//  InputDeckView.swift
//  Moonlight Next
//
//  The tabletop input deck: when an iPhone Duo stands half-open on a table, the stream keeps
//  the top half and this fills the bottom half. Keyboard and trackpad for desktop use, or a
//  gamepad. Everything goes to the host through MNInput.
//

import SwiftUI
import UIKit

/// Built by StreamFrameViewController (ObjC), which owns the stream and the fold detection.
@objc final class MNInputDeck: NSObject {
    @objc static func makeViewController(onHide: @escaping () -> Void) -> UIViewController {
        let host = UIHostingController(rootView: InputDeckView(onHide: onHide))
        host.view.backgroundColor = UIColor(red: 5 / 255, green: 5 / 255, blue: 6 / 255, alpha: 1)
        return host
    }
}

struct InputDeckView: View {
    let onHide: () -> Void

    private enum Mode: String, CaseIterable {
        case keyboard = "Keyboard & trackpad"
        case gamepad = "Gamepad"
    }

    @AppStorage("inputDeckMode") private var mode = Mode.keyboard.rawValue

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Picker("Input", selection: $mode) {
                    ForEach(Mode.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Spacer()
                Button(action: onHide) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 40, height: 40)
                        .overlay(Circle().strokeBorder(Theme.lineStrong))
                }
                .accessibilityLabel("Hide input deck")
            }
            if mode == Mode.gamepad.rawValue {
                GamepadPanel()
            } else {
                KeyboardPanel()
                TrackpadPanel()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(hex: 0x050506).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: - Haptics

/// Taps you can feel: light for keys, a firmer click for mouse and gamepad buttons, a soft
/// tick for latching a modifier. Generators are kept warm so the first press isn't late.
private enum Haptics {
    static let key = UIImpactFeedbackGenerator(style: .light)
    static let click = UIImpactFeedbackGenerator(style: .medium)
    static let toggle = UISelectionFeedbackGenerator()

    static func keyPress() { key.impactOccurred(intensity: 0.7); key.prepare() }
    static func clickPress() { click.impactOccurred(); click.prepare() }
    static func modifierToggle() { toggle.selectionChanged(); toggle.prepare() }
}

// MARK: - Press helper

private extension View {
    /// Down when the finger lands, up when it lifts or slides off; each control is its own
    /// gesture, so several can be held at once (Shift + key, A + stick).
    func onPress(down: @escaping () -> Void, up: @escaping () -> Void) -> some View {
        // An infinite duration never completes, so the pressing state tracks the finger exactly
        onLongPressGesture(minimumDuration: .infinity, maximumDistance: 60, perform: {}, onPressingChanged: { pressing in
            pressing ? down() : up()
        })
    }
}

// MARK: - Keyboard

private enum VK {
    static let escape: Int16 = 0x1B, backspace: Int16 = 0x08, tab: Int16 = 0x09, caps: Int16 = 0x14
    static let enter: Int16 = 0x0D, space: Int16 = 0x20, shift: Int16 = 0xA0, ctrl: Int16 = 0xA2
    static let alt: Int16 = 0xA4, win: Int16 = 0x5B, comma: Int16 = 0xBC, period: Int16 = 0xBE
    static let left: Int16 = 0x25, up: Int16 = 0x26, right: Int16 = 0x27, down: Int16 = 0x28

    /// A–Z and 0–9 share their ASCII codes.
    static func char(_ c: Character) -> Int16 { Int16(c.asciiValue ?? 0) }
}

private struct Key: Identifiable {
    enum Kind { case normal, modifier(MNKeyModifiers), caps, accent }
    let id = UUID()
    let label: String
    let vk: Int16
    var weight: CGFloat = 1
    var kind: Kind = .normal
    var accessibility: String? = nil
}

/// Modifiers latch for one keypress (tap Shift, then a letter), like a phone keyboard;
/// Caps Lock is sent as a real toggle to the host.
private final class KeyboardState: ObservableObject {
    @Published var latched: MNKeyModifiers = []

    static let modifierKeys: [(MNKeyModifiers, Int16)] = [
        (.shift, VK.shift), (.ctrl, VK.ctrl), (.alt, VK.alt), (.meta, VK.win),
    ]

    func press(_ key: Key) {
        switch key.kind {
        case .modifier(let m):
            Haptics.modifierToggle()
            if latched.contains(m) { latched.remove(m) } else { latched.insert(m) }
        default:
            Haptics.keyPress()
            for (m, vk) in Self.modifierKeys where latched.contains(m) {
                MNInput.keyDown(vk, modifiers: latched)
            }
            MNInput.keyDown(key.vk, modifiers: latched)
        }
    }

    func release(_ key: Key) {
        if case .modifier = key.kind { return }
        MNInput.keyUp(key.vk, modifiers: latched)
        for (m, vk) in Self.modifierKeys.reversed() where latched.contains(m) {
            MNInput.keyUp(vk, modifiers: [])
        }
        latched = []
    }
}

private struct KeyboardPanel: View {
    @StateObject private var state = KeyboardState()

    private let rows: [[Key]] = {
        func letters(_ s: String) -> [Key] { s.map { Key(label: String($0), vk: VK.char($0)) } }
        return [
            [Key(label: "esc", vk: VK.escape, weight: 1.2, accessibility: "Escape")] + letters("1234567890")
                + [Key(label: "⌫", vk: VK.backspace, weight: 1.5, accessibility: "Backspace")],
            [Key(label: "tab", vk: VK.tab, weight: 1.5, accessibility: "Tab")] + letters("QWERTYUIOP"),
            [Key(label: "caps", vk: VK.caps, weight: 1.7, kind: .caps, accessibility: "Caps lock")] + letters("ASDFGHJKL")
                + [Key(label: "return", vk: VK.enter, weight: 1.8, kind: .accent, accessibility: "Return")],
            [Key(label: "shift", vk: VK.shift, weight: 2.2, kind: .modifier(.shift), accessibility: "Shift")] + letters("ZXCVBNM")
                + [Key(label: ",", vk: VK.comma), Key(label: ".", vk: VK.period),
                   Key(label: "shift", vk: VK.shift, weight: 1.6, kind: .modifier(.shift), accessibility: "Shift")],
            [Key(label: "ctrl", vk: VK.ctrl, weight: 1.2, kind: .modifier(.ctrl), accessibility: "Control"),
             Key(label: "win", vk: VK.win, weight: 1.2, kind: .modifier(.meta), accessibility: "Windows"),
             Key(label: "alt", vk: VK.alt, weight: 1.2, kind: .modifier(.alt), accessibility: "Alt"),
             Key(label: "", vk: VK.space, weight: 4.8, accessibility: "Space"),
             Key(label: "←", vk: VK.left, accessibility: "Left"), Key(label: "↑", vk: VK.up, accessibility: "Up"),
             Key(label: "↓", vk: VK.down, accessibility: "Down"), Key(label: "→", vk: VK.right, accessibility: "Right")],
        ]
    }()

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                GeometryReader { geo in
                    let row = rows[r]
                    let gaps = CGFloat(row.count - 1) * 5
                    let unit = (geo.size.width - gaps) / row.reduce(0) { $0 + $1.weight }
                    HStack(spacing: 5) {
                        ForEach(row) { key in
                            KeyCap(key: key, latched: isLatched(key))
                                .frame(width: unit * key.weight)
                                .onPress(down: { state.press(key) }, up: { state.release(key) })
                        }
                    }
                }
                .frame(height: 40)
            }
        }
    }

    private func isLatched(_ key: Key) -> Bool {
        if case .modifier(let m) = key.kind { return state.latched.contains(m) }
        return false
    }
}

private struct KeyCap: View {
    let key: Key
    let latched: Bool

    var body: some View {
        let isLetter = key.label.count == 1 && key.label.first!.isLetter || key.label.first?.isNumber == true
        let accent: Bool = { if case .accent = key.kind { return true }; return false }()
        Text(key.label)
            .font(.system(size: isLetter || key.label.count == 1 ? 15 : 12, weight: .medium))
            .foregroundStyle(accent || latched ? Color.black : (isLetter ? Theme.text : Color(hex: 0xA3A3AA)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(accent || latched ? Theme.accent : (isLetter ? Color(hex: 0x0F0F13) : Color(hex: 0x141419))))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(hex: 0x1F1F25)))
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel(key.accessibility ?? key.label)
            .accessibilityAddTraits(.isKeyboardKey)
    }
}

// MARK: - Trackpad

private struct TrackpadPanel: View {
    var body: some View {
        HStack(spacing: 8) {
            ClickButton(title: "Left click", button: .left, corners: (12, 4))
            TrackpadSurface()
                .overlay(alignment: .bottom) {
                    Text("Trackpad · tap to click · two fingers to scroll")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, 10)
                        .allowsHitTesting(false)
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x0B0B0E)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong))
                .accessibilityLabel("Trackpad")
            ClickButton(title: "Right click", button: .right, corners: (4, 12))
        }
        .frame(maxHeight: .infinity)
    }
}

private struct ClickButton: View {
    let title: String
    let button: MNMouseButton
    let corners: (CGFloat, CGFloat)
    @SwiftUI.State private var pressed = false

    var body: some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(Color(hex: 0xA3A3AA))
            .frame(width: 92)
            .frame(maxHeight: .infinity)
            .background(UnevenRoundedRectangle(topLeadingRadius: corners.0, bottomLeadingRadius: corners.0,
                                               bottomTrailingRadius: corners.1, topTrailingRadius: corners.1)
                .fill(pressed ? Color(hex: 0x1E1E24) : Color(hex: 0x0F0F13)))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: corners.0, bottomLeadingRadius: corners.0,
                                            bottomTrailingRadius: corners.1, topTrailingRadius: corners.1)
                .stroke(Color(hex: 0x1F1F25), lineWidth: 1))
            .contentShape(Rectangle())
            .onPress(down: { pressed = true; Haptics.clickPress(); MNInput.mouseButton(button, down: true) },
                     up: { pressed = false; MNInput.mouseButton(button, down: false) })
            .accessibilityAddTraits(.isButton)
    }
}

/// A UIKit view so one- and two-finger pans and taps can be told apart.
private struct TrackpadSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> TrackpadUIView { TrackpadUIView() }
    func updateUIView(_ uiView: TrackpadUIView, context: Context) {}
}

final class TrackpadUIView: UIView {
    /// Host pixels per point of finger travel.
    private let pointerSpeed: CGFloat = 2.0
    /// High-res scroll units (120 = one notch) per point.
    private let scrollSpeed: CGFloat = 4.0
    private var remainder = CGPoint.zero
    private var scrollRemainder: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        let movePan = UIPanGestureRecognizer(target: self, action: #selector(handleMove(_:)))
        movePan.maximumNumberOfTouches = 1
        let scrollPan = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scrollPan.minimumNumberOfTouches = 2
        scrollPan.maximumNumberOfTouches = 2
        let oneTap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let twoTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoTap.numberOfTouchesRequired = 2
        oneTap.require(toFail: twoTap)
        for recognizer in [movePan, scrollPan, oneTap, twoTap] {
            addGestureRecognizer(recognizer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func handleMove(_ pan: UIPanGestureRecognizer) {
        let t = pan.translation(in: self)
        pan.setTranslation(.zero, in: self)
        let dx = t.x * pointerSpeed + remainder.x
        let dy = t.y * pointerSpeed + remainder.y
        let sx = dx.rounded(.towardZero), sy = dy.rounded(.towardZero)
        remainder = CGPoint(x: dx - sx, y: dy - sy)
        MNInput.mouseMoveX(Int16(clamping: Int(sx)), y: Int16(clamping: Int(sy)))
        if pan.state == .ended || pan.state == .cancelled { remainder = .zero }
    }

    @objc private func handleScroll(_ pan: UIPanGestureRecognizer) {
        let t = pan.translation(in: self)
        pan.setTranslation(.zero, in: self)
        // Fingers moving down scroll the content up, as on a Mac trackpad
        let amount = t.y * scrollSpeed + scrollRemainder
        let whole = amount.rounded(.towardZero)
        scrollRemainder = amount - whole
        MNInput.scroll(Int16(clamping: Int(whole)))
        if pan.state == .ended || pan.state == .cancelled { scrollRemainder = 0 }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        click(.left)
    }

    @objc private func handleTwoFingerTap(_ recognizer: UITapGestureRecognizer) {
        click(.right)
    }

    private func click(_ button: MNMouseButton) {
        Haptics.clickPress()
        MNInput.mouseButton(button, down: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MNInput.mouseButton(button, down: false)
        }
    }
}

// MARK: - Gamepad

private enum Pad {
    static let a: Int32 = 0x1000, b: Int32 = 0x2000, x: Int32 = 0x4000, y: Int32 = 0x8000
    static let up: Int32 = 0x0001, down: Int32 = 0x0002, left: Int32 = 0x0004, right: Int32 = 0x0008
    static let lb: Int32 = 0x0100, rb: Int32 = 0x0200, play: Int32 = 0x0010, back: Int32 = 0x0020
    static let special: Int32 = 0x0400
}

private struct GamepadPanel: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                PadButton(label: "L2", width: 96, height: 42) { down in MNInput.gamepadLeftTrigger(down ? 255 : 0) }
                PadButton(label: "L1", width: 96, height: 42) { MNInput.gamepadButton(Pad.lb, down: $0) }
                Spacer()
                PadButton(label: "R1", width: 96, height: 42) { MNInput.gamepadButton(Pad.rb, down: $0) }
                PadButton(label: "R2", width: 96, height: 42) { down in MNInput.gamepadRightTrigger(down ? 255 : 0) }
            }
            HStack(alignment: .top) {
                VStack(spacing: 16) {
                    Stick { x, y in MNInput.gamepadLeftStickX(x, y: y) }
                    DPad().padding(.leading, 90)
                }
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    PadButton(label: "View", width: 54, height: 32, small: true) { MNInput.gamepadButton(Pad.back, down: $0) }
                    PadButton(label: "", symbol: "moon", width: 40, height: 32, small: true) { MNInput.gamepadButton(Pad.special, down: $0) }
                        .accessibilityLabel("Home")
                    PadButton(label: "Menu", width: 54, height: 32, small: true) { MNInput.gamepadButton(Pad.play, down: $0) }
                }
                .padding(.top, 56)
                Spacer(minLength: 0)
                VStack(spacing: 16) {
                    FaceButtons()
                    Stick { x, y in MNInput.gamepadRightStickX(x, y: y) }.padding(.trailing, 90)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PadButton: View {
    let label: String
    var symbol: String? = nil
    let width: CGFloat
    let height: CGFloat
    var small = false
    var filled = false
    let send: (Bool) -> Void
    @SwiftUI.State private var pressed = false

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
            } else {
                Text(label).font(.system(size: small ? 11 : 15, weight: .semibold))
                    .foregroundStyle(filled ? Color.black : (small ? Theme.textSecondary : Theme.text))
            }
        }
        .frame(width: width, height: height)
        .background(Capsule().fill(filled ? Theme.accent : (pressed ? Color(hex: 0x24242B) : Color(hex: 0x0F0F13))))
        .overlay(Capsule().strokeBorder(filled ? Color.clear : Color(hex: 0x2E2E35)))
        .scaleEffect(pressed ? 0.94 : 1)
        .contentShape(Capsule())
        .onPress(down: { pressed = true; Haptics.clickPress(); send(true) }, up: { pressed = false; send(false) })
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

private struct FaceButtons: View {
    var body: some View {
        VStack(spacing: 0) {
            PadButton(label: "Y", width: 52, height: 52) { MNInput.gamepadButton(Pad.y, down: $0) }
            HStack(spacing: 52) {
                PadButton(label: "X", width: 52, height: 52) { MNInput.gamepadButton(Pad.x, down: $0) }
                PadButton(label: "B", width: 52, height: 52) { MNInput.gamepadButton(Pad.b, down: $0) }
            }
            PadButton(label: "A", width: 52, height: 52, filled: true) { MNInput.gamepadButton(Pad.a, down: $0) }
        }
    }
}

private struct DPad: View {
    var body: some View {
        VStack(spacing: 0) {
            PadButton(label: "▲", width: 44, height: 44, small: true) { MNInput.gamepadButton(Pad.up, down: $0) }
                .accessibilityLabel("Up")
            HStack(spacing: 44) {
                PadButton(label: "◀", width: 44, height: 44, small: true) { MNInput.gamepadButton(Pad.left, down: $0) }
                    .accessibilityLabel("Left")
                PadButton(label: "▶", width: 44, height: 44, small: true) { MNInput.gamepadButton(Pad.right, down: $0) }
                    .accessibilityLabel("Right")
            }
            PadButton(label: "▼", width: 44, height: 44, small: true) { MNInput.gamepadButton(Pad.down, down: $0) }
                .accessibilityLabel("Down")
        }
    }
}

/// Analog stick: the knob follows the finger inside the ring and springs back on release.
private struct Stick: View {
    let send: (Int16, Int16) -> Void
    private let radius: CGFloat = 60
    @SwiftUI.State private var offset = CGSize.zero

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: 0x0B0B0E)).overlay(Circle().strokeBorder(Color(hex: 0x2E2E35)))
            Circle().fill(Color(hex: 0x1E1E24)).overlay(Circle().strokeBorder(Color(hex: 0x34343C)))
                .frame(width: 56, height: 56)
                .offset(offset)
        }
        .frame(width: radius * 2, height: radius * 2)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    var v = value.translation
                    let length = (v.width * v.width + v.height * v.height).squareRoot()
                    if length > radius {
                        v = CGSize(width: v.width / length * radius, height: v.height / length * radius)
                    }
                    offset = v
                    send(Int16(clamping: Int(v.width / radius * 32767)), Int16(clamping: Int(-v.height / radius * 32767)))
                }
                .onEnded { _ in
                    withAnimation(.spring(duration: 0.15)) { offset = .zero }
                    send(0, 0)
                }
        )
        .accessibilityLabel("Analog stick")
    }
}
