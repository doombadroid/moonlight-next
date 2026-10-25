//
//  WidgetEditor.swift
//  MoonLume
//
//  The layout editor's widget sheets: "Add widget" (by category, with the shortcut library) and
//  the properties of the selected widget.
//

import SwiftUI

// MARK: - Picker

struct WidgetPickerView: View {
    let onPick: (MNWidget) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                NavigationLink { gamepad } label: { Label("Gamepad buttons", systemImage: "gamecontroller") }
                NavigationLink { keyboard } label: { Label("Keyboard keys", systemImage: "keyboard") }
                NavigationLink { mouse } label: { Label("Mouse buttons and wheel", systemImage: "computermouse") }
                NavigationLink { shortcuts } label: { Label("Shortcuts", systemImage: "command") }
                NavigationLink { pads } label: { Label("Touchpads", systemImage: "hand.draw") }
                Section {
                    item("Gyro aim (hold)", "gyroscope", MNWidget(kind: .gyroAim))
                    item("Gyro pause (hold)", "pause.circle", MNWidget(kind: .gyroPause))
                } header: {
                    Text("Motion")
                } footer: {
                    Text("With a gyro aim button on screen, gyro aiming only runs while it's held. It aims with what Settings › Gyro sets, or the right stick when gyro aiming is off there.")
                }
                Section("Stream") {
                    ForEach(MNWidgetFunction.allCases, id: \.rawValue) { f in
                        item(f.name, f.symbol, { var w = MNWidget(kind: .function); w.function = f; return w }())
                    }
                }
                Section("More") {
                    item("Macro", "list.number", {
                        var w = MNWidget(kind: .button)
                        w.shape = .rounded
                        w.w = 72
                        w.h = 44
                        w.macro = [MacroStep(inputs: [.key(0x20)])]
                        return w
                    }())
                    item("Folder", "folder", MNWidget(kind: .folder))
                    item("Controller overlay", "gamecontroller.fill", MNWidget(kind: .overlay))
                }
            }
            .navigationTitle("Add Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .environment(\.colorScheme, .dark)
        .tint(Theme.accent)
    }

    private func item(_ title: String, _ symbol: String, _ widget: MNWidget, note: String? = nil) -> some View {
        Button {
            onPick(widget)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol).foregroundStyle(Theme.text)
                if let note {
                    Text(note).font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    static func button(_ inputs: [WidgetInput], label: String = "", rounded: Bool = false) -> MNWidget {
        var w = MNWidget(kind: .button)
        w.inputs = inputs
        w.label = label
        if rounded || w.title.count > 3 {
            w.shape = .rounded
            w.w = max(56, min(Double(w.title.count) * 9 + 24, 140))
            w.h = 44
        }
        return w
    }

    private var gamepad: some View {
        List {
            ForEach(WidgetCatalog.padButtons, id: \.flag) { b in
                item(b.name, "circle", WidgetPickerView.button([.pad(b.flag)]))
            }
            item("LT (full press)", "l2.button.roundedtop.horizontal", WidgetPickerView.button([.leftTrigger]))
            item("RT (full press)", "r2.button.roundedtop.horizontal", WidgetPickerView.button([.rightTrigger]))
        }
        .navigationTitle("Gamepad")
    }

    private var keyboard: some View {
        List {
            ForEach(WidgetCatalog.keyGroups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.keys, id: \.vk) { key in
                        item(key.name, "keyboard", WidgetPickerView.button([.key(key.vk)]))
                    }
                }
            }
        }
        .navigationTitle("Keyboard")
    }

    private var mouse: some View {
        List {
            Section {
                ForEach(WidgetCatalog.mouseButtons, id: \.button) { b in
                    item(b.name, b.symbol, WidgetPickerView.button([.mouse(b.button)], label: WidgetCatalog.shortName(.mouse(b.button))))
                }
            }
            Section {
                ForEach(WidgetInput.Direction.allCases, id: \.rawValue) { d in
                    item("Wheel \(d.rawValue)", "chevron.\(d.rawValue)", WidgetPickerView.button([.wheel(d)]))
                }
            } footer: {
                Text("One notch per tap. Turn on turbo in the widget's settings to keep scrolling while held.")
            }
        }
        .navigationTitle("Mouse")
    }

    private var shortcuts: some View {
        List {
            ForEach(WidgetCatalog.shortcuts, id: \.section) { section in
                Section(section.section) {
                    ForEach(section.items, id: \.name) { s in
                        let inputs = s.keys.map { WidgetInput.key($0) }
                        item(s.name, "command", WidgetPickerView.button(inputs, label: s.name, rounded: true),
                             note: inputs.map(\.name).joined(separator: " + ") + (s.note.map { " · \($0)" } ?? ""))
                    }
                }
            }
            Section {
                item("Custom chord", "plus.square.on.square", WidgetPickerView.button([.key(WidgetCatalog.ctrl)], label: "Chord", rounded: true),
                     note: "Pick its keys in the widget's settings")
            } footer: {
                Text("Most of these are Windows shortcuts; macOS and Linux hosts may use other keys. Win is Command on a Mac and Super on Linux.")
            }
        }
        .navigationTitle("Shortcuts")
    }

    private var pads: some View {
        List {
            Section {
                item("Floating stick (left)", "l.joystick", { var w = MNWidget(kind: .stickPad); w.right = false; return w }(),
                     note: "Appears where your thumb lands")
                item("Floating stick (right)", "r.joystick", MNWidget(kind: .stickPad), note: "Appears where your thumb lands")
                item("Look pad", "camera.viewfinder", MNWidget(kind: .cameraPad),
                     note: "Swipe speed turns the right stick, with a glide after you lift")
            }
            Section {
                item("Left trigger strip", "l2.button.roundedtop.horizontal", { var w = MNWidget(kind: .triggerPad); w.right = false; return w }(),
                     note: "Swipe up for a partial press")
                item("Right trigger strip", "r2.button.roundedtop.horizontal", MNWidget(kind: .triggerPad), note: "Swipe up for a partial press")
            }
            Section {
                item("WASD pad", "arrow.up.and.down.and.arrow.left.and.right", {
                    var w = MNWidget(kind: .directionPad)
                    w.sprintKey = WidgetCatalog.shift
                    return w
                }(), note: "Push far for Shift (sprint); walk key optional")
                item("Arrow keys pad", "arrow.up.and.down.and.arrow.left.and.right", {
                    var w = MNWidget(kind: .directionPad)
                    w.keys = WidgetCatalog.arrows
                    return w
                }())
            }
            Section {
                item("Mouse touchpad", "rectangle.and.hand.point.up.left", MNWidget(kind: .mousePad),
                     note: "Move, tap to click, tap then hold to drag, two fingers scroll")
                item("Scroll strip", "arrow.up.and.down", MNWidget(kind: .scrollPad), note: "One finger turns the mouse wheel")
                item("Touch blocker", "hand.raised.slash", MNWidget(kind: .blocker),
                     note: "Covers a spot so a resting palm doesn't touch the stream")
            }
        }
        .navigationTitle("Touchpads")
    }
}

// MARK: - Input picker

/// Picks one key, gamepad button, mouse button or wheel notch.
struct WidgetInputPicker: View {
    let onPick: (WidgetInput) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Gamepad") {
                ForEach(WidgetCatalog.padButtons, id: \.flag) { b in row(b.name, .pad(b.flag)) }
                row("LT", .leftTrigger)
                row("RT", .rightTrigger)
            }
            Section("Mouse") {
                ForEach(WidgetCatalog.mouseButtons, id: \.button) { b in row(b.name, .mouse(b.button)) }
                ForEach(WidgetInput.Direction.allCases, id: \.rawValue) { d in row("Wheel \(d.rawValue)", .wheel(d)) }
            }
            ForEach(WidgetCatalog.keyGroups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.keys, id: \.vk) { key in row(key.name, .key(key.vk)) }
                }
            }
        }
        .navigationTitle("Choose Input")
    }

    private func row(_ title: String, _ input: WidgetInput) -> some View {
        Button(title) {
            onPick(input)
            dismiss()
        }
        .foregroundStyle(Theme.text)
    }
}

// MARK: - Properties

struct WidgetPropertiesView: View {
    @ObservedObject var model: LayoutEditorModel
    let layer: MNWidgetLayer
    let id: String
    @Environment(\.dismiss) private var dismiss
    /// One undo step for everything changed while the sheet is open
    @SwiftUI.State private var undoRecorded = false
    /// Macro step getting another key
    @SwiftUI.State private var addingToStep: Int?

    private var widget: MNWidget? { _ = model.revision; return layer.widget(id) }

    var body: some View {
        NavigationStack {
            Group {
                if let w = widget {
                    form(w)
                }
                else {
                    Text("This widget was removed.").foregroundStyle(Theme.muted)
                }
            }
            .navigationTitle(widget?.title ?? "Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(isPresented: Binding(get: { addingToStep != nil }, set: { if !$0 { addingToStep = nil } })) {
                WidgetInputPicker { input in
                    if let i = addingToStep {
                        change { if i < $0.macro.count, $0.macro[i].inputs.count < 8 { $0.macro[i].inputs.append(input) } }
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .tint(Theme.accent)
    }

    private func change(_ edit: (inout MNWidget) -> Void) {
        if !undoRecorded {
            layer.pushUndo()
            undoRecorded = true
        }
        layer.update(id, undo: false, edit)
    }

    private func bind<T>(_ path: WritableKeyPath<MNWidget, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { widget?[keyPath: path] ?? fallback },
                set: { value in change { $0[keyPath: path] = value } })
    }

    @ViewBuilder private func form(_ w: MNWidget) -> some View {
        Form {
            appearance(w)
            switch w.kind {
            case .button:
                buttonSections(w)
            case .stickPad, .cameraPad, .triggerPad:
                padSection(w)
            case .scrollPad:
                Section {
                    slider("Speed", bind(\.sensitivity, 1), 0.2...4, format: "%.1f×")
                } footer: {
                    Text("Also follows Settings › Touch scroll speed and direction.")
                }
            case .directionPad:
                directionSection(w)
            case .gyroAim:
                gyroSection(w)
            case .function:
                Section {
                    Picker("Action", selection: bind(\.function, .settings)) {
                        ForEach(MNWidgetFunction.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                }
            case .folder:
                Section {
                    Toggle("Starts collapsed", isOn: bind(\.collapsed, false))
                    Picker("Dock to the edge when idle", selection: bind(\.autoDock, 0)) {
                        Text("Off").tag(0.0)
                        ForEach([3.0, 5.0, 10.0, 30.0], id: \.self) { Text("After \(Int($0)) s").tag($0) }
                    }
                } footer: {
                    Text("Tap the folder to show or hide what's in it. Put widgets in it from their settings. Moving the folder moves them too. A collapsed folder can slide to the nearest edge after a while; tap the tab to bring it back.")
                }
            case .gyroPause, .overlay, .mousePad, .blocker:
                EmptyView()
            }
            if w.kind != .folder, !layer.folders.isEmpty {
                Section {
                    Picker("Folder", selection: bind(\.folder, "")) {
                        Text("None").tag("")
                        ForEach(layer.folders) { f in Text(f.label.isEmpty ? "Folder \(folderNumber(f))" : f.label).tag(f.id) }
                    }
                }
            }
            Section {
                Button("Duplicate") {
                    layer.duplicate(id)
                    dismiss()
                }
                Button("Delete Widget", role: .destructive) {
                    layer.delete(id)
                    dismiss()
                }
            }
        }
    }

    private func folderNumber(_ f: MNWidget) -> Int {
        (layer.folders.firstIndex { $0.id == f.id } ?? 0) + 1
    }

    @ViewBuilder private func appearance(_ w: MNWidget) -> some View {
        Section("Look") {
            TextField("Label (\(w.title))", text: bind(\.label, ""))
            if w.kind != .overlay {
                TextField("SF Symbol (e.g. bolt.fill)", text: bind(\.symbol, ""))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Shape", selection: bind(\.shape, .circle)) {
                    Text("Circle").tag(MNWidget.Shape.circle)
                    Text("Rounded rectangle").tag(MNWidget.Shape.rounded)
                }
                Toggle("Border", isOn: bind(\.border, true))
            }
            slider("Width", bind(\.w, 56), 24...400, format: "%.0f pt")
            slider("Height", bind(\.h, 56), 24...400, format: "%.0f pt")
            slider("Opacity", bind(\.opacity, 1), 0.1...1, format: "%.0f%%", scale: 100)
            if w.kind.isButtonLike || w.kind == .directionPad {
                Picker("Haptic", selection: bind(\.haptic, .medium)) {
                    Text("Off").tag(MNWidget.Haptic.off)
                    Text("Light").tag(MNWidget.Haptic.light)
                    Text("Medium").tag(MNWidget.Haptic.medium)
                    Text("Heavy").tag(MNWidget.Haptic.heavy)
                }
            }
            if [.button, .gyroAim, .gyroPause].contains(w.kind) {
                Toggle("Tap to toggle", isOn: bind(\.toggle, false))
            }
            if w.kind == .button {
                Toggle("Slide across", isOn: bind(\.slide, false))
            }
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, format: String, scale: Double = 1) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue * scale)).foregroundStyle(Theme.muted).monospacedDigit()
            }
            Slider(value: value, in: range)
        }
    }

    @ViewBuilder private func buttonSections(_ w: MNWidget) -> some View {
        Section {
            ForEach(Array(w.inputs.enumerated()), id: \.offset) { i, input in
                Text(input.name)
                    .swipeActions { Button("Remove", role: .destructive) { change { $0.inputs.remove(at: i) } } }
            }
            .onMove { from, to in change { $0.inputs.move(fromOffsets: from, toOffset: to) } }
            if w.inputs.count < 8 {
                NavigationLink("Add Input…") { WidgetInputPicker { input in change { $0.inputs.append(input) } } }
            }
        } header: {
            Text("Presses")
        } footer: {
            Text(w.macro.isEmpty ? "Pressed together in this order while held, let go in reverse (Ctrl, then C)."
                                 : "Not used: this button plays its macro.")
        }
        Section {
            Toggle("Turbo", isOn: Binding(get: { (widget?.turboMs ?? 0) > 0 },
                                          set: { on in change { $0.turboMs = on ? 100 : 0 } }))
            if w.turboMs > 0 {
                Stepper("Every \(w.turboMs) ms", value: bind(\.turboMs, 100), in: 40...2000, step: 10)
                Stepper(w.turboCount == 0 ? "Until let go" : "\(w.turboCount) times", value: bind(\.turboCount, 0), in: 0...99)
            }
        } footer: {
            Text("Taps the presses over and over while held (or until tapped again, with Tap to toggle).")
        }
        Section {
            ForEach(Array(w.macro.enumerated()), id: \.element.id) { i, step in
                macroStep(i, step)
            }
            .onMove { from, to in change { $0.macro.move(fromOffsets: from, toOffset: to) } }
            if w.macro.count < 32 {
                NavigationLink("Add Step…") { WidgetInputPicker { input in change { $0.macro.append(MacroStep(inputs: [input])) } } }
            }
        } header: {
            Text("Macro")
        } footer: {
            Text("Steps play in order on each press. A step is held for its hold time (or until you let go of the button), then the macro waits before the next one.")
        }
    }

    private func macroStep(_ i: Int, _ step: MacroStep) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(i + 1). " + step.inputs.map(\.name).joined(separator: " + ")).font(.body.weight(.medium))
                Spacer()
                Button { addingToStep = i } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Add a key to this step")
                Button(role: .destructive) { change { if i < $0.macro.count { $0.macro.remove(at: i) } } } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove step")
            }
            Toggle("Hold until let go", isOn: Binding(get: { step.untilRelease },
                                                      set: { v in change { if i < $0.macro.count { $0.macro[i].untilRelease = v } } }))
            if !step.untilRelease {
                Stepper(step.holdMs == 0 ? "Hold: tap" : "Hold: \(step.holdMs) ms",
                        value: Binding(get: { step.holdMs }, set: { v in change { if i < $0.macro.count { $0.macro[i].holdMs = v } } }),
                        in: 0...5000, step: 50)
            }
            Stepper("Then wait: \(step.waitMs) ms",
                    value: Binding(get: { step.waitMs }, set: { v in change { if i < $0.macro.count { $0.macro[i].waitMs = v } } }),
                    in: 0...5000, step: 25)
        }
        .swipeActions { Button("Remove", role: .destructive) { change { if i < $0.macro.count { $0.macro.remove(at: i) } } } }
    }

    @ViewBuilder private func padSection(_ w: MNWidget) -> some View {
        Section {
            Picker(w.kind == .triggerPad ? "Trigger" : "Stick", selection: bind(\.right, true)) {
                Text(w.kind == .triggerPad ? "Left (LT)" : "Left").tag(false)
                Text(w.kind == .triggerPad ? "Right (RT)" : "Right").tag(true)
            }
            slider("Sensitivity", bind(\.sensitivity, 1), 0.2...4, format: "%.1f×")
            if w.kind == .cameraPad {
                Toggle("Glide after lifting", isOn: bind(\.inertia, true))
            }
        } footer: {
            switch w.kind {
            case .stickPad: Text("The stick centres where your thumb lands and follows it past the edge.")
            case .cameraPad: Text("How fast you swipe sets how far the stick turns, like a mouse for camera control.")
            default: Text("Swipe up from where your finger lands; about 60 pt is a full press at sensitivity 1.")
            }
        }
    }

    private static let walkKeys: [(String, Int)] = [("None", 0), ("Shift", WidgetCatalog.shift), ("Ctrl", WidgetCatalog.ctrl),
                                                    ("Alt", WidgetCatalog.alt), ("Caps Lock", 0x14), ("C", 0x43), ("X", 0x58),
                                                    ("Z", 0x5A), ("Space", 0x20)]

    @ViewBuilder private func directionSection(_ w: MNWidget) -> some View {
        Section {
            Picker("Keys", selection: bind(\.keys, WidgetCatalog.wasd)) {
                Text("W A S D").tag(WidgetCatalog.wasd)
                Text("Arrow keys").tag(WidgetCatalog.arrows)
            }
            Picker("Walk key", selection: bind(\.walkKey, 0)) {
                ForEach(WidgetPropertiesView.walkKeys, id: \.1) { Text($0.0).tag($0.1) }
            }
            if w.walkKey > 0 {
                slider("Walk within", bind(\.walkBelow, 30), 16...150, format: "%.0f pt")
            }
            Picker("Sprint key", selection: bind(\.sprintKey, 0)) {
                ForEach(WidgetPropertiesView.walkKeys, id: \.1) { Text($0.0).tag($0.1) }
            }
            if w.sprintKey > 0 {
                slider("Sprint beyond", bind(\.sprintAbove, 80), 30...200, format: "%.0f pt")
            }
        } footer: {
            Text("Directions come from how far your thumb moves from where it landed. The walk key is held while it stays close, the sprint key once it goes far.")
        }
    }

    @ViewBuilder private func gyroSection(_ w: MNWidget) -> some View {
        Section {
            slider("Horizontal", bind(\.gyroX, 1), -3...3, format: "%.1f×")
            slider("Vertical", bind(\.gyroY, 1), -3...3, format: "%.1f×")
        } header: {
            Text("Aim speed")
        } footer: {
            Text("Multiplies Settings › Gyro sensitivity while this button is held. Negative values invert the axis.")
        }
    }
}
