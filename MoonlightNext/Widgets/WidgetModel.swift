//
//  WidgetModel.swift
//  MoonLume
//
//  On-screen widgets: buttons for any gamepad button, key, mouse button, wheel notch, chord or
//  macro; touchpads (floating stick, camera pad, trigger strip, WASD pad, mouse and screen pads,
//  scroll strips, a PlayStation touchpad); gyro buttons; stream function buttons; folders (one
//  level of nesting); and a live diagram of a connected controller.
//
//  Widgets are saved inside the on-screen controls layout (per posture, per game, in named
//  layouts and exported files) under the "widgets" key, as an array of plain dictionaries.
//  Layouts without the key simply have no widgets, and OnScreenControls keeps keys it doesn't
//  know, so older builds load these layouts too.
//

import Foundation

/// One input a widget presses. Stored as a short string ("key:65", "pad:4096", "mouse:4",
/// "wheel:up", "lt") so exported layouts stay readable.
enum WidgetInput: Hashable {
    case pad(Int)       // gamepad button flag (Limelight.h: A_FLAG ...)
    case leftTrigger
    case rightTrigger
    case key(Int)       // Windows virtual-key code
    case mouse(Int)     // 1 left, 2 middle, 3 right, 4 X1 (back), 5 X2 (forward)
    case wheel(Direction)

    enum Direction: String, CaseIterable { case up, down, left, right }

    init?(string: String) {
        let parts = string.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first ?? "", parts.count > 1 ? Int(parts[1]) : nil) {
        case ("pad", let v?) where v > 0 && v <= 0x200000: self = .pad(v)
        case ("key", let v?) where (1...0xFE).contains(v): self = .key(v)
        case ("mouse", let v?) where (1...5).contains(v): self = .mouse(v)
        case ("lt", _): self = .leftTrigger
        case ("rt", _): self = .rightTrigger
        case ("wheel", _):
            guard parts.count > 1, let d = Direction(rawValue: parts[1]) else { return nil }
            self = .wheel(d)
        default: return nil
        }
    }

    var string: String {
        switch self {
        case .pad(let v): return "pad:\(v)"
        case .key(let v): return "key:\(v)"
        case .mouse(let v): return "mouse:\(v)"
        case .leftTrigger: return "lt"
        case .rightTrigger: return "rt"
        case .wheel(let d): return "wheel:\(d.rawValue)"
        }
    }

    var name: String {
        switch self {
        case .pad(let v): return WidgetCatalog.padButtons.first { $0.flag == v }?.name ?? "Button"
        case .leftTrigger: return "LT"
        case .rightTrigger: return "RT"
        case .key(let v): return WidgetCatalog.keyName(v)
        case .mouse(let v): return WidgetCatalog.mouseButtons.first { $0.button == v }?.name ?? "Mouse"
        case .wheel(let d): return "Wheel \(d.rawValue)"
        }
    }

    var isModifierKey: Bool {
        if case .key(let v) = self { return WidgetCatalog.modifierBit(v) != 0 }
        return false
    }
}

extension WidgetInput: Codable {
    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let input = WidgetInput(string: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown input \(s)"))
        }
        self = input
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }
}

/// One step of a macro: press `inputs` together, hold them `holdMs` (0 = a quick tap), or until
/// the widget is let go, then wait `waitMs` before the next step.
struct MacroStep: Codable, Equatable, Identifiable {
    var id = UUID()
    var inputs: [WidgetInput]
    var holdMs = 0
    var waitMs = 50
    var untilRelease = false

    private enum CodingKeys: String, CodingKey { case inputs, holdMs, waitMs, untilRelease }

    init(inputs: [WidgetInput], holdMs: Int = 0, waitMs: Int = 50, untilRelease: Bool = false) {
        self.inputs = inputs
        self.holdMs = holdMs
        self.waitMs = waitMs
        self.untilRelease = untilRelease
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputs = try c.decode([WidgetInput].self, forKey: .inputs)
        holdMs = min(max(try c.decodeIfPresent(Int.self, forKey: .holdMs) ?? 0, 0), 10_000)
        waitMs = min(max(try c.decodeIfPresent(Int.self, forKey: .waitMs) ?? 50, 0), 10_000)
        untilRelease = try c.decodeIfPresent(Bool.self, forKey: .untilRelease) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(inputs, forKey: .inputs)
        try c.encode(holdMs, forKey: .holdMs)
        try c.encode(waitMs, forKey: .waitMs)
        if untilRelease { try c.encode(true, forKey: .untilRelease) }
    }

    static func == (a: MacroStep, b: MacroStep) -> Bool {
        a.inputs == b.inputs && a.holdMs == b.holdMs && a.waitMs == b.waitMs && a.untilRelease == b.untilRelease
    }
}

/// Stream actions a function button runs (handled by StreamFrameViewController).
@objc enum MNWidgetFunction: Int, CaseIterable {
    case settings, disconnect, quitApp, pictureInPicture, editControls, softKeyboard, inputDeck,
         touchToggle, controllerMouse, stats, profiles

    var name: String {
        switch self {
        case .settings: return "Settings"
        case .disconnect: return "Disconnect"
        case .quitApp: return "Quit App"
        case .pictureInPicture: return "Picture in Picture"
        case .editControls: return "Edit Controls"
        case .softKeyboard: return "Soft Keyboard"
        case .inputDeck: return "Keyboard & Trackpad"
        case .touchToggle: return "Touch On/Off"
        case .controllerMouse: return "Controller Mouse"
        case .stats: return "Stats"
        case .profiles: return "Layouts"
        }
    }

    var symbol: String {
        switch self {
        case .settings: return "gearshape"
        case .disconnect: return "xmark"
        case .quitApp: return "power"
        case .pictureInPicture: return "pip.enter"
        case .editControls: return "arrow.up.and.down.and.arrow.left.and.right"
        case .softKeyboard: return "keyboard"
        case .inputDeck: return "keyboard.badge.ellipsis"
        case .touchToggle: return "hand.raised.slash"
        case .controllerMouse: return "cursorarrow.motionlines"
        case .stats: return "chart.bar.xaxis"
        case .profiles: return "square.stack.3d.up"
        }
    }

    /// Saved name (an @objc enum doesn't print its case names)
    var key: String {
        switch self {
        case .settings: return "settings"
        case .disconnect: return "disconnect"
        case .quitApp: return "quitApp"
        case .pictureInPicture: return "pip"
        case .editControls: return "editControls"
        case .softKeyboard: return "softKeyboard"
        case .inputDeck: return "inputDeck"
        case .touchToggle: return "touchToggle"
        case .controllerMouse: return "controllerMouse"
        case .stats: return "stats"
        case .profiles: return "profiles"
        }
    }
}

struct MNWidget: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case button       // presses `inputs` together; or plays `macro`; optional turbo
        case stickPad     // floating stick: appears under the thumb, displacement drives a stick
        case cameraPad    // swipe speed drives a stick, with inertia after lifting
        case triggerPad   // swipe up for an analog trigger
        case directionPad // WASD / arrow keys from displacement, with walk and sprint keys
        case gyroAim      // aim with the gyro while held
        case gyroPause    // pause gyro aiming while held (lift and re-centre)
        case function     // a stream action
        case folder       // shows or hides the widgets in it
        case overlay      // live diagram of a connected controller
        case mousePad     // a small trackpad: move, tap to click, two fingers scroll
        case scrollPad    // one finger scrolls the mouse wheel
        case blocker      // takes touches so nothing under it reacts (a resting palm)
        case controllerTouchpad // a DualShock/DualSense touchpad: up to two fingers, sent as pad touches
        case screenPad    // stands for the whole host screen: touch points the mouse there (absolute)

        var isButtonLike: Bool { self == .button || self == .gyroAim || self == .gyroPause || self == .function || self == .folder }
    }

    enum Shape: String, Codable, CaseIterable { case circle, rounded }
    enum Haptic: String, Codable, CaseIterable { case off, light, medium, heavy }

    var id = UUID().uuidString
    var kind: Kind
    /// Centre, as a fraction of the stream area, so it stays put when the area resizes
    var x = 0.5
    var y = 0.5
    var w = 56.0
    var h = 56.0
    var opacity = 1.0
    var label = ""
    var symbol = ""
    var shape = Shape.circle
    var border = true
    var haptic = Haptic.medium
    /// Tap to latch, tap again to release
    var toggle = false
    /// A finger rolling onto this button from another slide button presses it
    var slide = false
    /// Button-like widgets: hold still, then drag to move it during play (saved with the layout)
    var movable = false
    /// Folder this widget is in
    var folder = ""

    // Buttons
    var inputs: [WidgetInput] = []
    var macro: [MacroStep] = []
    /// Repeat while held, every this many milliseconds (0: off)
    var turboMs = 0
    /// Stop after this many repeats (0: until let go)
    var turboCount = 0

    // Pads
    /// Stick pads and camera pads: the right stick, else the left; trigger pads: RT, else LT
    var right = true
    var sensitivity = 1.0
    var inertia = true
    /// Direction pad keys: up, left, down, right
    var keys: [Int] = WidgetCatalog.wasd
    var walkKey = 0
    var sprintKey = 0
    /// Walk key below, sprint key above this distance (points from where the thumb landed)
    var walkBelow = 30.0
    var sprintAbove = 80.0
    /// Tap the walk / sprint key on entering its zone and again on leaving, instead of holding it
    var walkToggle = false
    var sprintToggle = false
    /// Scroll strips: whole wheel notches, one per stretch of travel
    var notched = false

    // Gyro buttons: per-axis factors for aiming while held
    var gyroX = 1.0
    var gyroY = 1.0

    var function = MNWidgetFunction.settings

    // Folders
    var collapsed = false
    /// Slide to the nearest edge after this many idle seconds while collapsed (0: never)
    var autoDock = 0.0
    /// Shows what's in it only while held; letting go over a widget in it presses that widget
    var peek = false

    init(kind: Kind) {
        self.kind = kind
        switch kind {
        case .stickPad, .cameraPad, .directionPad:
            w = 190; h = 190; shape = .rounded; haptic = .off
        case .triggerPad:
            w = 64; h = 170; shape = .rounded; haptic = .off
        case .overlay:
            w = 200; h = 130; shape = .rounded; border = false; haptic = .off
        case .mousePad:
            w = 220; h = 150; shape = .rounded; haptic = .off
        case .scrollPad:
            w = 56; h = 170; shape = .rounded; haptic = .off
        case .blocker:
            w = 160; h = 110; shape = .rounded; haptic = .off; opacity = 0.3
        case .controllerTouchpad:
            w = 220; h = 110; shape = .rounded; haptic = .off
        case .screenPad:
            w = 240; h = 135; shape = .rounded; haptic = .light
        case .function, .folder:
            w = 44; h = 44
        default:
            break
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, x, y, w, h, opacity, label, symbol, shape, border, haptic, toggle, slide, movable, folder,
             inputs, macro, turboMs, turboCount, right, sensitivity, inertia, keys, walkKey, sprintKey,
             walkBelow, sprintAbove, walkToggle, sprintToggle, notched, gyroX, gyroY, function, collapsed,
             autoDock, peek
    }

    // Saved layouts come from older and newer builds and from imported files: every field is
    // optional, out-of-range numbers are clamped, and an unknown kind drops just that widget.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kind: try c.decode(Kind.self, forKey: .kind))
        func num(_ key: CodingKeys, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            guard let v = try? c.decodeIfPresent(Double.self, forKey: key), v.isFinite else { return fallback }
            return min(max(v, range.lowerBound), range.upperBound)
        }
        func int(_ key: CodingKeys, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
            guard let v = try? c.decodeIfPresent(Int.self, forKey: key) else { return fallback }
            return min(max(v, range.lowerBound), range.upperBound)
        }
        func bool(_ key: CodingKeys, _ fallback: Bool) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: key)) ?? fallback }
        func str(_ key: CodingKeys) -> String { String(((try? c.decodeIfPresent(String.self, forKey: key)) ?? "").prefix(64)) }

        id = str(.id).isEmpty ? UUID().uuidString : str(.id)
        x = num(.x, 0.5, 0...1)
        y = num(.y, 0.5, 0...1)
        w = num(.w, w, 24...600)
        h = num(.h, h, 24...600)
        opacity = num(.opacity, 1, 0.1...1)
        label = String(str(.label).prefix(24))
        symbol = str(.symbol)
        shape = (try? c.decodeIfPresent(Shape.self, forKey: .shape)) ?? shape
        border = bool(.border, border)
        haptic = (try? c.decodeIfPresent(Haptic.self, forKey: .haptic)) ?? haptic
        toggle = bool(.toggle, false)
        slide = bool(.slide, false)
        movable = bool(.movable, false)
        folder = str(.folder)
        inputs = Array(((try? c.decodeIfPresent([WidgetInput].self, forKey: .inputs)) ?? []).prefix(8))
        macro = Array(((try? c.decodeIfPresent([MacroStep].self, forKey: .macro)) ?? []).prefix(32))
        turboMs = int(.turboMs, 0, 0...5000)
        turboCount = int(.turboCount, 0, 0...999)
        right = bool(.right, true)
        sensitivity = num(.sensitivity, 1, 0.1...5)
        inertia = bool(.inertia, true)
        let k = (try? c.decodeIfPresent([Int].self, forKey: .keys)) ?? []
        keys = k.count == 4 && k.allSatisfy({ (1...0xFE).contains($0) }) ? k : WidgetCatalog.wasd
        walkKey = int(.walkKey, 0, 0...0xFE)
        sprintKey = int(.sprintKey, 0, 0...0xFE)
        walkBelow = num(.walkBelow, 30, 0...400)
        sprintAbove = num(.sprintAbove, 80, 0...400)
        walkToggle = bool(.walkToggle, false)
        sprintToggle = bool(.sprintToggle, false)
        notched = bool(.notched, false)
        gyroX = num(.gyroX, 1, -5...5)
        gyroY = num(.gyroY, 1, -5...5)
        function = (try? c.decodeIfPresent(String.self, forKey: .function))
            .flatMap { name in MNWidgetFunction.allCases.first { $0.key == name } } ?? .settings
        collapsed = bool(.collapsed, false)
        autoDock = num(.autoDock, 0, 0...120)
        peek = bool(.peek, false)
    }

    // Only what applies to the kind, so saved layouts stay small
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(w, forKey: .w)
        try c.encode(h, forKey: .h)
        try c.encode(opacity, forKey: .opacity)
        if !label.isEmpty { try c.encode(label, forKey: .label) }
        if !symbol.isEmpty { try c.encode(symbol, forKey: .symbol) }
        try c.encode(shape, forKey: .shape)
        try c.encode(border, forKey: .border)
        try c.encode(haptic, forKey: .haptic)
        if toggle { try c.encode(true, forKey: .toggle) }
        if slide { try c.encode(true, forKey: .slide) }
        if movable { try c.encode(true, forKey: .movable) }
        if !folder.isEmpty { try c.encode(folder, forKey: .folder) }
        switch kind {
        case .button:
            try c.encode(inputs, forKey: .inputs)
            if !macro.isEmpty { try c.encode(macro, forKey: .macro) }
            if turboMs > 0 {
                try c.encode(turboMs, forKey: .turboMs)
                try c.encode(turboCount, forKey: .turboCount)
            }
        case .scrollPad:
            try c.encode(sensitivity, forKey: .sensitivity)
            if notched { try c.encode(true, forKey: .notched) }
        case .stickPad, .cameraPad, .triggerPad:
            try c.encode(right, forKey: .right)
            try c.encode(sensitivity, forKey: .sensitivity)
            if kind != .triggerPad { try c.encode(inertia, forKey: .inertia) }
        case .directionPad:
            try c.encode(keys, forKey: .keys)
            try c.encode(walkKey, forKey: .walkKey)
            try c.encode(sprintKey, forKey: .sprintKey)
            try c.encode(walkBelow, forKey: .walkBelow)
            try c.encode(sprintAbove, forKey: .sprintAbove)
            if walkToggle { try c.encode(true, forKey: .walkToggle) }
            if sprintToggle { try c.encode(true, forKey: .sprintToggle) }
        case .gyroAim:
            try c.encode(gyroX, forKey: .gyroX)
            try c.encode(gyroY, forKey: .gyroY)
        case .function:
            try c.encode(function.key, forKey: .function)
        case .folder:
            try c.encode(collapsed, forKey: .collapsed)
            try c.encode(autoDock, forKey: .autoDock)
            if peek { try c.encode(true, forKey: .peek) }
        case .gyroPause, .overlay, .mousePad, .blocker, .controllerTouchpad, .screenPad:
            break
        }
    }

    /// What the widget shows when it has no label of its own
    var title: String {
        if !label.isEmpty { return label }
        switch kind {
        case .button:
            if !macro.isEmpty { return "Macro" }
            return inputs.map { WidgetCatalog.shortName($0) }.joined(separator: "+")
        case .stickPad: return right ? "Right stick" : "Left stick"
        case .cameraPad: return "Look"
        case .triggerPad: return right ? "RT" : "LT"
        case .directionPad: return keys == WidgetCatalog.arrows ? "Arrows" : "WASD"
        case .gyroAim: return "Gyro"
        case .gyroPause: return "Gyro pause"
        case .function: return function.name
        case .folder: return "Folder"
        case .overlay: return "Controller"
        case .mousePad: return "Touchpad"
        case .scrollPad: return "Scroll"
        case .blocker: return "Blocker"
        case .controllerTouchpad: return "PS touchpad"
        case .screenPad: return "Screen"
        }
    }

    /// The symbol drawn when no label is set (and none chosen)
    var defaultSymbol: String {
        switch kind {
        case .gyroAim: return "gyroscope"
        case .gyroPause: return "pause.circle"
        case .function: return function.symbol
        case .folder: return collapsed ? "folder" : "folder.fill"
        case .button:
            if inputs == [.wheel(.up)] { return "chevron.up" }
            if inputs == [.wheel(.down)] { return "chevron.down" }
            if inputs == [.wheel(.left)] { return "chevron.left" }
            if inputs == [.wheel(.right)] { return "chevron.right" }
            return ""
        default: return ""
        }
    }
}

/// Reading and writing the "widgets" entry of a layout dictionary.
enum WidgetStore {
    static let key = "widgets"

    static func widgets(in layout: [String: Any]) -> [MNWidget] {
        guard let raw = layout[key] as? [Any] else { return [] }
        let decoder = JSONDecoder()
        // One at a time, so one odd entry doesn't lose the rest
        return raw.prefix(200).compactMap { entry in
            guard JSONSerialization.isValidJSONObject([entry]),
                  let data = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
            return try? decoder.decode(MNWidget.self, from: data)
        }
    }

    /// A property-list-safe value for the layout (nil when there are no widgets)
    static func value(for widgets: [MNWidget]) -> [[String: Any]]? {
        guard !widgets.isEmpty, let data = try? JSONEncoder().encode(widgets),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return array
    }

    /// An imported file's widgets, decoded and re-encoded so only known, clamped fields are kept
    static func sanitized(_ raw: Any?) -> [[String: Any]]? {
        value(for: widgets(in: [key: raw as Any]))
    }
}
