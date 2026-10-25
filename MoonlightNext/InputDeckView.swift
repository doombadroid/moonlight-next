//
//  InputDeckView.swift
//  Moonlight Next
//
//  The input deck: when an iPhone Duo is half-open with the fold across the middle (Apple's
//  "tabletop" pose, though it's mostly held like a Nintendo DS and thumb-typed), the stream
//  keeps the top half and this fills the bottom half. Keyboard and trackpad, or a gamepad.
//  Everything goes to the host through MNInput.
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
        case keys = "Keys"
        case gamepad = "Gamepad"
    }

    @AppStorage("inputDeckMode") private var mode = Mode.keys.rawValue

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Picker("Input", selection: $mode) {
                    ForEach(Mode.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
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
            switch Mode(rawValue: mode) {
            case .gamepad: GamepadPanel()
            default: FullKeyboardDeck()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        // Down to the bottom edge: the stream defers the home-indicator swipe, so the space
        // the safe area would leave empty is usable
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.container, edges: .bottom)
        .background(Color(hex: 0x050506).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: - Feedback

/// Feels like the system keyboard: a light impact the moment a thumb lands on a key, the same
/// for letters and modifiers (iOS's own keyboard uses private feedback; this is its public
/// match). Mouse and gamepad buttons get a firmer click. All of it follows the System Haptics
/// setting; iOS doesn't expose the separate Keyboard Feedback switch to apps.
private enum Feedback {
    static let key = UIImpactFeedbackGenerator(style: .light)
    static let click = UIImpactFeedbackGenerator(style: .medium)

    /// Settings › Input › Haptics on button presses (on unless turned off)
    static var enabled: Bool { UserDefaults.standard.object(forKey: "mnHapticsEnabled") as? Bool ?? true }

    static func keyPress() {
        guard enabled else { return }
        key.impactOccurred()
        key.prepare()
    }

    static func modifierToggle() {
        keyPress()
    }

    static func clickPress() {
        guard enabled else { return }
        click.impactOccurred()
        click.prepare()
    }
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
    static let delete: Int16 = 0x2E, home: Int16 = 0x24, end: Int16 = 0x23, pageUp: Int16 = 0x21, pageDown: Int16 = 0x22
    static func f(_ n: Int) -> Int16 { Int16(0x70 + n - 1) }

    /// A–Z and 0–9 share their ASCII codes.
    static func char(_ c: Character) -> Int16 { Int16(c.asciiValue ?? 0) }
}

private struct Key: Identifiable {
    enum Kind { case normal, modifier(MNKeyModifiers), caps, accent, fn }
    let id = UUID()
    let label: String
    let vk: Int16
    var weight: CGFloat = 1
    var kind: Kind = .normal
    var accessibility: String? = nil
    /// What the key sends while fn is latched (F-keys, Delete, Home / End / Page Up / Down)
    var fnLabel: String? = nil
    var fnVK: Int16? = nil
}

/// Modifiers latch for one keypress (tap Shift, then a letter), like a phone keyboard;
/// Caps Lock is sent as a real toggle to the host.
private final class KeyboardState: ObservableObject {
    @Published var latched: MNKeyModifiers = []
    /// fn latches for one keypress too
    @Published var fnOn = false
    /// What each held key actually sent, so the key-up matches even after fn clears
    private var sent: [UUID: Int16] = [:]

    static let modifierKeys: [(MNKeyModifiers, Int16)] = [
        (.shift, VK.shift), (.ctrl, VK.ctrl), (.alt, VK.alt), (.meta, VK.win),
    ]

    func press(_ key: Key) {
        switch key.kind {
        case .modifier(let m):
            Feedback.modifierToggle()
            if latched.contains(m) { latched.remove(m) } else { latched.insert(m) }
        case .fn:
            Feedback.modifierToggle()
            fnOn.toggle()
        default:
            Feedback.keyPress()
            let vk = fnOn ? (key.fnVK ?? key.vk) : key.vk
            sent[key.id] = vk
            for (m, mvk) in Self.modifierKeys where latched.contains(m) {
                MNInput.keyDown(mvk, modifiers: latched)
            }
            MNInput.keyDown(vk, modifiers: latched)
        }
    }

    func release(_ key: Key) {
        switch key.kind {
        case .modifier, .fn: return
        default: break
        }
        MNInput.keyUp(sent.removeValue(forKey: key.id) ?? key.vk, modifiers: latched)
        for (m, vk) in Self.modifierKeys.reversed() where latched.contains(m) {
            MNInput.keyUp(vk, modifiers: [])
        }
        latched = []
        fnOn = false
    }
}

// Layouts are static so key ids stay stable across re-renders (the pressed set is keyed by them)
private enum Layouts {
    static func letters(_ s: String) -> [Key] { s.map { Key(label: String($0), vk: VK.char($0)) } }
    static let esc = Key(label: "esc", vk: VK.escape, weight: 1.2, accessibility: "Escape")
    static let backspace = Key(label: "⌫", vk: VK.backspace, weight: 1.5, accessibility: "Backspace",
                               fnLabel: "del", fnVK: VK.delete)
    static let tab = Key(label: "tab", vk: VK.tab, weight: 1.5, accessibility: "Tab")
    static let ret = Key(label: "return", vk: VK.enter, weight: 1.8, kind: .accent, accessibility: "Return")
    static func shift(_ w: CGFloat) -> Key { Key(label: "shift", vk: VK.shift, weight: w, kind: .modifier(.shift), accessibility: "Shift") }
    static let ctrl = Key(label: "ctrl", vk: VK.ctrl, weight: 1.2, kind: .modifier(.ctrl), accessibility: "Control")
    // One key on every host OS: Windows key on a PC, Super on Linux, Command on a Mac
    static let win = Key(label: "win", vk: VK.win, weight: 1.2, kind: .modifier(.meta), accessibility: "Windows, Super or Command")
    static let fn = Key(label: "fn", vk: 0, weight: 1, kind: .fn, accessibility: "Function")
    static let alt = Key(label: "alt", vk: VK.alt, weight: 1.2, kind: .modifier(.alt), accessibility: "Alt")
    static func space(_ w: CGFloat) -> Key { Key(label: "", vk: VK.space, weight: w, accessibility: "Space") }
    static let arrows = [
        Key(label: "←", vk: VK.left, accessibility: "Left", fnLabel: "home", fnVK: VK.home),
        Key(label: "↑", vk: VK.up, accessibility: "Up", fnLabel: "pg↑", fnVK: VK.pageUp),
        Key(label: "↓", vk: VK.down, accessibility: "Down", fnLabel: "pg↓", fnVK: VK.pageDown),
        Key(label: "→", vk: VK.right, accessibility: "Right", fnLabel: "end", fnVK: VK.end),
    ]
    /// 1–0, which become F1–F10 with fn
    static let digits: [Key] = "1234567890".enumerated().map { i, c in
        Key(label: String(c), vk: VK.char(c), fnLabel: "F\(i + 1)", fnVK: VK.f(i + 1))
    }
    /// Q and W carry F11 and F12
    static let topLetters: [Key] = letters("QWERTYUIOP").enumerated().map { i, key in
        guard i < 2 else { return key }
        return Key(label: key.label, vk: key.vk, fnLabel: "F\(i + 11)", fnVK: VK.f(i + 11))
    }

    static let full: [[Key]] = [
        [esc] + digits + [backspace],
        [tab] + topLetters,
        [Key(label: "caps", vk: VK.caps, weight: 1.7, kind: .caps, accessibility: "Caps lock")] + letters("ASDFGHJKL") + [ret],
        [shift(2.2)] + letters("ZXCVBNM") + [Key(label: ",", vk: VK.comma), Key(label: ".", vk: VK.period), shift(1.6)],
        [fn, Key(label: "ctrl", vk: VK.ctrl, weight: 1.1, kind: .modifier(.ctrl), accessibility: "Control"),
         win, Key(label: "alt", vk: VK.alt, weight: 1.1, kind: .modifier(.alt), accessibility: "Alt"), space(4.0)] + arrows,
    ]
}

/// Rows of keys sized to the width they're given, each row `keyHeight` tall.
private struct KeyGrid: View {
    let rows: [[Key]]
    let keyHeight: CGFloat
    @ObservedObject var state: KeyboardState
    @Binding var pressed: Set<UUID>

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                GeometryReader { geo in
                    let row = rows[r]
                    let gaps = CGFloat(row.count - 1) * 5
                    let unit = (geo.size.width - gaps) / row.reduce(0) { $0 + $1.weight }
                    HStack(spacing: 5) {
                        ForEach(row) { key in
                            KeyCap(key: key, latched: isLatched(key), pressed: pressed.contains(key.id),
                                   label: state.fnOn ? (key.fnLabel ?? key.label) : key.label)
                                .frame(width: unit * key.weight)
                                .zIndex(pressed.contains(key.id) ? 1 : 0)
                                .allowsHitTesting(false)
                                .accessibilityAction {
                                    state.press(key)
                                    state.release(key)
                                }
                        }
                    }
                }
                .frame(height: keyHeight)
            }
        }
        // One touch surface over the whole grid, so palm rejection can see each touch's size
        .overlay(KeyTouchSurface(rows: rows.map { $0.map(\.weight) }, keyHeight: keyHeight,
                                 onDown: { r, i in
                                     let key = rows[r][i]
                                     pressed.insert(key.id)
                                     state.press(key)
                                 }, onUp: { r, i in
                                     let key = rows[r][i]
                                     pressed.remove(key.id)
                                     state.release(key)
                                 }))
    }

    private func isLatched(_ key: Key) -> Bool {
        switch key.kind {
        case .modifier(let m): return state.latched.contains(m)
        case .fn: return state.fnOn
        default: return false
        }
    }
}

/// Thumb-typing layout: full-width keys along the bottom, where thumbs rest when the Duo is
/// held like a DS, and the trackpad in the space above them. (A split keyboard was tried:
/// on this width the thumbs meet in the middle anyway, so splitting only shrank the keys.)
private struct FullKeyboardDeck: View {
    @StateObject private var state = KeyboardState()
    @SwiftUI.State private var pressed: Set<UUID> = []

    var body: some View {
        VStack(spacing: 10) {
            TrackpadPanel()
            KeyGrid(rows: Layouts.full, keyHeight: 54, state: state, pressed: $pressed)
        }
    }
}

private struct KeyCap: View {
    let key: Key
    let latched: Bool
    var pressed = false
    /// The fn layer's label while fn is latched
    var label: String? = nil

    var body: some View {
        let text = label ?? key.label
        let isLetter = text.count == 1 && text.first!.isLetter || (text.count == 1 && text.first?.isNumber == true)
        let accent: Bool = { if case .accent = key.kind { return true }; return false }()
        let lit = accent || latched || pressed
        Text(text)
            .font(.system(size: isLetter || text.count == 1 ? 15 : 12, weight: pressed ? .semibold : .medium))
            .foregroundStyle(lit ? Color.black : (isLetter ? Theme.text : Color(hex: 0xA3A3AA)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(lit ? Theme.accent : (isLetter ? Color(hex: 0x0F0F13) : Color(hex: 0x141419))))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(pressed ? Color.white.opacity(0.6) : Color(hex: 0x1F1F25)))
            // Pressed keys pop up and grow above the finger, like a phone keyboard's key preview
            .scaleEffect(pressed ? 1.18 : 1, anchor: .bottom)
            .offset(y: pressed ? -4 : 0)
            .shadow(color: Theme.accent.opacity(pressed ? 0.45 : 0), radius: 8)
            .animation(.spring(duration: 0.12), value: pressed)
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
                .frame(width: 92)
            TrackpadSurface()
                .overlay(alignment: .bottom) {
                    Text("Tap to click · tap, then hold to drag · two fingers scroll · pinch zooms")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .padding(.bottom, 10)
                        .allowsHitTesting(false)
                }
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x0B0B0E)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lineStrong))
                .accessibilityLabel("Trackpad")
            ClickButton(title: "Right click", button: .right, corners: (4, 12))
                .frame(width: 92)
        }
        .frame(minHeight: 60, maxHeight: .infinity)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(UnevenRoundedRectangle(topLeadingRadius: corners.0, bottomLeadingRadius: corners.0,
                                               bottomTrailingRadius: corners.1, topTrailingRadius: corners.1)
                .fill(pressed ? Color(hex: 0x1E1E24) : Color(hex: 0x0F0F13)))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: corners.0, bottomLeadingRadius: corners.0,
                                            bottomTrailingRadius: corners.1, topTrailingRadius: corners.1)
                .stroke(Color(hex: 0x1F1F25), lineWidth: 1))
            .overlay(PressSurface { down in
                pressed = down
                if down { Feedback.clickPress() }
                MNInput.mouseButton(button, down: down)
            })
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                MNInput.mouseButton(button, down: true)
                MNInput.mouseButton(button, down: false)
            }
    }
}

private struct KeyTouchSurface: UIViewRepresentable {
    let rows: [[CGFloat]]
    let keyHeight: CGFloat
    let onDown: (Int, Int) -> Void
    let onUp: (Int, Int) -> Void

    func makeUIView(context: Context) -> KeyTouchView { KeyTouchView() }
    func updateUIView(_ view: KeyTouchView, context: Context) {
        view.rows = rows
        view.keyHeight = keyHeight
        view.onDown = onDown
        view.onUp = onUp
    }
    static func dismantleUIView(_ view: KeyTouchView, coordinator: ()) { view.releaseAll() }
}

private struct PressSurface: UIViewRepresentable {
    let onChange: (Bool) -> Void

    func makeUIView(context: Context) -> PressTouchView { PressTouchView() }
    func updateUIView(_ view: PressTouchView, context: Context) { view.onChange = onChange }
}

/// A UIKit view so one- and two-finger pans and taps can be told apart.
private struct TrackpadSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> TrackpadUIView { TrackpadUIView() }
    func updateUIView(_ uiView: TrackpadUIView, context: Context) {}
}

final class TrackpadUIView: UIView {
    /// Moves, clicks, drags, scrolls and pinches; shared with the full-screen touchpad mode
    private lazy var pad: MNTouchpad = {
        let pad = MNTouchpad(view: self, fullScreen: false)
        pad.onClick = { Feedback.clickPress() }
        return pad
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Touches the trackpad accepted; palms and touches that land while typing never reach it
    private var accepted = Set<ObjectIdentifier>()

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let typing = PalmGuard.shared.typingRecently
        let fresh = touches.filter { !PalmGuard.shared.isPalm($0, landing: true) && !typing }
        accepted.formUnion(fresh.map(ObjectIdentifier.init))
        if !fresh.isEmpty { pad.touchesBegan(fresh) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let mine = touches.filter { accepted.contains(ObjectIdentifier($0)) }
        // A touch that spreads into a palm is withdrawn as if cancelled
        let palms = mine.filter { PalmGuard.shared.isPalm($0) }
        if !palms.isEmpty {
            accepted.subtract(palms.map(ObjectIdentifier.init))
            pad.touchesCancelled(palms)
        }
        let moving = mine.subtracting(palms)
        if !moving.isEmpty { pad.touchesMoved(moving) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let mine = lift(touches)
        if !mine.isEmpty { pad.touchesEnded(mine) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let mine = lift(touches)
        if !mine.isEmpty { pad.touchesCancelled(mine) }
    }

    private func lift(_ touches: Set<UITouch>) -> Set<UITouch> {
        touches.forEach { PalmGuard.shared.touchLifted($0) }
        let mine = touches.filter { accepted.contains(ObjectIdentifier($0)) }
        accepted.subtract(mine.map(ObjectIdentifier.init))
        return mine
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
        .onPress(down: { pressed = true; Feedback.clickPress(); send(true) }, up: { pressed = false; send(false) })
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
