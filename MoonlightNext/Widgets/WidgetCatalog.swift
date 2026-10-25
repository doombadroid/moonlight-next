//
//  WidgetCatalog.swift
//  MoonLume
//
//  Names for everything a widget can press, and the preset shortcut library.
//

import Foundation

enum WidgetCatalog {
    struct PadButton { let name: String; let flag: Int; let symbol: String }
    struct MouseButton { let name: String; let button: Int; let symbol: String }
    struct Key { let name: String; let vk: Int }
    struct Shortcut { let name: String; let keys: [Int]; var note: String? = nil }

    // Limelight.h flags
    static let padButtons: [PadButton] = [
        PadButton(name: "A", flag: 0x1000, symbol: "a.circle"),
        PadButton(name: "B", flag: 0x2000, symbol: "b.circle"),
        PadButton(name: "X", flag: 0x4000, symbol: "x.circle"),
        PadButton(name: "Y", flag: 0x8000, symbol: "y.circle"),
        PadButton(name: "D-pad up", flag: 0x0001, symbol: "arrowtriangle.up"),
        PadButton(name: "D-pad down", flag: 0x0002, symbol: "arrowtriangle.down"),
        PadButton(name: "D-pad left", flag: 0x0004, symbol: "arrowtriangle.left"),
        PadButton(name: "D-pad right", flag: 0x0008, symbol: "arrowtriangle.right"),
        PadButton(name: "LB", flag: 0x0100, symbol: "lb.button.roundedbottom.horizontal"),
        PadButton(name: "RB", flag: 0x0200, symbol: "rb.button.roundedbottom.horizontal"),
        PadButton(name: "L3", flag: 0x0040, symbol: "l.joystick.press.down"),
        PadButton(name: "R3", flag: 0x0080, symbol: "r.joystick.press.down"),
        PadButton(name: "Start", flag: 0x0010, symbol: "line.3.horizontal.circle"),
        PadButton(name: "Select", flag: 0x0020, symbol: "rectangle.on.rectangle.circle"),
        PadButton(name: "Home", flag: 0x0400, symbol: "house.circle"),
        PadButton(name: "Paddle 1", flag: 0x010000, symbol: "p1.button.horizontal"),
        PadButton(name: "Paddle 2", flag: 0x020000, symbol: "p2.button.horizontal"),
        PadButton(name: "Paddle 3", flag: 0x040000, symbol: "p3.button.horizontal"),
        PadButton(name: "Paddle 4", flag: 0x080000, symbol: "p4.button.horizontal"),
        PadButton(name: "Touchpad click", flag: 0x100000, symbol: "hand.tap"),
        PadButton(name: "Share", flag: 0x200000, symbol: "square.and.arrow.up.circle"),
    ]

    static let mouseButtons: [MouseButton] = [
        MouseButton(name: "Left click", button: 1, symbol: "computermouse"),
        MouseButton(name: "Middle click", button: 2, symbol: "computermouse"),
        MouseButton(name: "Right click", button: 3, symbol: "computermouse"),
        MouseButton(name: "Back (X1)", button: 4, symbol: "arrow.left.circle"),
        MouseButton(name: "Forward (X2)", button: 5, symbol: "arrow.right.circle"),
    ]

    static let shift = 0xA0, ctrl = 0xA2, alt = 0xA4, win = 0x5B
    static let wasd = [0x57, 0x41, 0x53, 0x44]
    static let arrows = [0x26, 0x25, 0x28, 0x27]

    /// Windows virtual-key codes, grouped for the key picker
    static let keyGroups: [(name: String, keys: [Key])] = [
        ("Letters", (0x41...0x5A).map { Key(name: String(UnicodeScalar(UInt8($0))), vk: $0) }),
        ("Numbers", (0x30...0x39).map { Key(name: String(UnicodeScalar(UInt8($0))), vk: $0) }),
        ("Modifiers", [Key(name: "Shift", vk: shift), Key(name: "Ctrl", vk: ctrl), Key(name: "Alt", vk: alt),
                       Key(name: "Win", vk: win), Key(name: "Right Shift", vk: 0xA1), Key(name: "Right Ctrl", vk: 0xA3),
                       Key(name: "Right Alt", vk: 0xA5)]),
        ("Editing", [Key(name: "Esc", vk: 0x1B), Key(name: "Tab", vk: 0x09), Key(name: "Space", vk: 0x20),
                     Key(name: "Enter", vk: 0x0D), Key(name: "Backspace", vk: 0x08), Key(name: "Delete", vk: 0x2E),
                     Key(name: "Insert", vk: 0x2D), Key(name: "Caps Lock", vk: 0x14), Key(name: "Menu", vk: 0x5D),
                     Key(name: "Print Screen", vk: 0x2C), Key(name: "Pause", vk: 0x13), Key(name: "Scroll Lock", vk: 0x91)]),
        ("Navigation", [Key(name: "Up", vk: 0x26), Key(name: "Down", vk: 0x28), Key(name: "Left", vk: 0x25),
                        Key(name: "Right", vk: 0x27), Key(name: "Home", vk: 0x24), Key(name: "End", vk: 0x23),
                        Key(name: "Page Up", vk: 0x21), Key(name: "Page Down", vk: 0x22)]),
        ("Function", (1...12).map { Key(name: "F\($0)", vk: 0x70 + $0 - 1) }),
        ("Symbols", [Key(name: "-", vk: 0xBD), Key(name: "=", vk: 0xBB), Key(name: "[", vk: 0xDB), Key(name: "]", vk: 0xDD),
                     Key(name: "\\", vk: 0xDC), Key(name: ";", vk: 0xBA), Key(name: "'", vk: 0xDE), Key(name: ",", vk: 0xBC),
                     Key(name: ".", vk: 0xBE), Key(name: "/", vk: 0xBF), Key(name: "`", vk: 0xC0)]),
        ("Numpad", (0...9).map { Key(name: "Num \($0)", vk: 0x60 + $0) } +
                   [Key(name: "Num *", vk: 0x6A), Key(name: "Num +", vk: 0x6B), Key(name: "Num -", vk: 0x6D),
                    Key(name: "Num .", vk: 0x6E), Key(name: "Num /", vk: 0x6F), Key(name: "Num Lock", vk: 0x90)]),
        ("Media", [Key(name: "Mute", vk: 0xAD), Key(name: "Volume down", vk: 0xAE), Key(name: "Volume up", vk: 0xAF),
                   Key(name: "Play/Pause", vk: 0xB3), Key(name: "Next track", vk: 0xB0), Key(name: "Previous track", vk: 0xB1),
                   Key(name: "Stop", vk: 0xB2)]),
    ]

    private static let keyNames: [Int: String] = {
        var names: [Int: String] = [:]
        for group in keyGroups { for key in group.keys { names[key.vk] = key.name } }
        return names
    }()

    static func keyName(_ vk: Int) -> String { keyNames[vk] ?? String(format: "Key 0x%02X", vk) }

    /// Compact text for a button face ("Ctrl", "F4", "LMB")
    static func shortName(_ input: WidgetInput) -> String {
        switch input {
        case .key(let vk):
            switch vk {
            case 0x26: return "↑"
            case 0x28: return "↓"
            case 0x25: return "←"
            case 0x27: return "→"
            case 0xA1: return "RShift"
            case 0xA3: return "RCtrl"
            case 0xA5: return "RAlt"
            default: return keyName(vk)
            }
        case .mouse(let b): return ["LMB", "MMB", "RMB", "X1", "X2"][b - 1]
        case .pad(let flag):
            let name = padButtons.first { $0.flag == flag }?.name ?? "?"
            return name.hasPrefix("D-pad ") ? String(name.dropFirst(6)).capitalized : name
        default: return input.name
        }
    }

    /// MNKeyModifiers bit a modifier key sets (0 for other keys)
    static func modifierBit(_ vk: Int) -> UInt8 {
        switch vk {
        case 0x10, 0xA0, 0xA1: return 0x01
        case 0x11, 0xA2, 0xA3: return 0x02
        case 0x12, 0xA4, 0xA5: return 0x04
        case 0x5B, 0x5C: return 0x08
        default: return 0
        }
    }

    // Adapted from VoidLink (GPLv3), VoidLinkPreview/WidgetPickerView.swift (shortcut library)
    static let shortcuts: [(section: String, items: [Shortcut])] = [
        ("Editing", [
            Shortcut(name: "Copy", keys: [ctrl, 0x43]), Shortcut(name: "Cut", keys: [ctrl, 0x58]),
            Shortcut(name: "Paste", keys: [ctrl, 0x56]), Shortcut(name: "Undo", keys: [ctrl, 0x5A]),
            Shortcut(name: "Redo", keys: [ctrl, 0x59]), Shortcut(name: "Select all", keys: [ctrl, 0x41]),
            Shortcut(name: "Save", keys: [ctrl, 0x53]), Shortcut(name: "Find", keys: [ctrl, 0x46]),
            Shortcut(name: "Zoom in", keys: [ctrl, 0xBB]), Shortcut(name: "Zoom out", keys: [ctrl, 0xBD]),
            Shortcut(name: "New tab", keys: [ctrl, 0x54]), Shortcut(name: "Close tab", keys: [ctrl, 0x57]),
            Shortcut(name: "New folder", keys: [ctrl, shift, 0x4E]),
        ]),
        ("Windows", [
            Shortcut(name: "Switch window", keys: [alt, 0x09]), Shortcut(name: "Close window", keys: [alt, 0x73]),
            Shortcut(name: "Fullscreen", keys: [alt, 0x0D]), Shortcut(name: "Escape", keys: [0x1B]),
            Shortcut(name: "Show desktop", keys: [win, 0x44]), Shortcut(name: "Task view", keys: [win, 0x09]),
            Shortcut(name: "Snap left", keys: [win, 0x25]), Shortcut(name: "Snap right", keys: [win, 0x27]),
            Shortcut(name: "Maximize", keys: [win, 0x26]), Shortcut(name: "Minimize", keys: [win, 0x28]),
            Shortcut(name: "Start menu", keys: [win]),
        ]),
        ("System", [
            Shortcut(name: "Task Manager", keys: [ctrl, shift, 0x1B]),
            Shortcut(name: "Ctrl+Alt+Del", keys: [ctrl, alt, 0x2E], note: "Windows ignores this from streaming apps; Task Manager works instead"),
            Shortcut(name: "File Explorer", keys: [win, 0x45]), Shortcut(name: "Settings", keys: [win, 0x49]),
            Shortcut(name: "Power menu", keys: [win, 0x58]), Shortcut(name: "Lock", keys: [win, 0x4C]),
            Shortcut(name: "Run", keys: [win, 0x52]), Shortcut(name: "Search", keys: [win, 0x53]),
            Shortcut(name: "Screenshot area", keys: [win, shift, 0x53]),
            Shortcut(name: "Input language", keys: [win, 0x20]), Shortcut(name: "Keyboard layout", keys: [alt, shift]),
        ]),
        ("Games", [
            Shortcut(name: "Game Bar", keys: [win, 0x47]), Shortcut(name: "Toggle HDR", keys: [win, alt, 0x42]),
            Shortcut(name: "NVIDIA overlay", keys: [alt, 0x5A]), Shortcut(name: "NVIDIA screenshot", keys: [alt, 0x70]),
            Shortcut(name: "NVIDIA record", keys: [alt, 0x78]), Shortcut(name: "Steam overlay", keys: [shift, 0x09]),
            Shortcut(name: "Steam screenshot", keys: [0x7B]),
        ]),
    ]
}
