//
//  LayoutEditorBar.swift
//  MoonLume
//
//  The bar shown while rearranging the on-screen controls. Top row: undo, layouts (templates,
//  saved layouts, import/export), options, Cancel and Save. Second row: size, opacity, hide,
//  tap-to-toggle and reset for the control you tapped, or the opacity of every control when
//  none is selected.
//  Selecting, dragging, snapping and the layout data itself live in OnScreenControls.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

@objc final class MNLayoutEditorBar: NSObject {
    @objc static func makeViewController(controls: OnScreenControls,
                                         hasGameLayout: Bool,
                                         onSave: @escaping (_ thisGame: Bool) -> Void,
                                         onCancel: @escaping () -> Void,
                                         onMoveBar: @escaping (_ toBottom: Bool) -> Void) -> UIViewController {
        let bar = LayoutEditorBar(model: LayoutEditorModel(osc: controls), hasGameLayout: hasGameLayout,
                                  onSave: onSave, onCancel: onCancel, onMoveBar: onMoveBar)
        let host = UIHostingController(rootView: bar)
        host.view.backgroundColor = .clear
        host.sizingOptions = .intrinsicContentSize
        return host
    }
}

/// Redraws the bar whenever the controls report a change (selection, layout, undo stack).
final class LayoutEditorModel: ObservableObject {
    let osc: OnScreenControls
    @Published private(set) var revision = 0

    init(osc: OnScreenControls) {
        self.osc = osc
        osc.editorChanged = { [weak self] in self?.changed() }
    }

    func changed() {
        revision &+= 1
    }
}

/// Named layouts, kept per posture (folded, phone, unfolded) in `mnOSCProfiles.<posture>`,
/// in the same format OnScreenControls saves.
enum OSCProfiles {
    private static func key(_ posture: String) -> String { "mnOSCProfiles.\(posture)" }

    private static func all(_ posture: String) -> [String: [String: Any]] {
        UserDefaults.standard.dictionary(forKey: key(posture)) as? [String: [String: Any]] ?? [:]
    }

    static func names(_ posture: String) -> [String] {
        all(posture).keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func layout(_ name: String, posture: String) -> [String: Any]? {
        all(posture)[name]
    }

    static func save(_ name: String, layout: [String: Any], posture: String) {
        var profiles = all(posture)
        profiles[name] = layout
        UserDefaults.standard.set(profiles, forKey: key(posture))
    }

    static func delete(_ name: String, posture: String) {
        var profiles = all(posture)
        profiles[name] = nil
        UserDefaults.standard.set(profiles, forKey: key(posture))
    }

    static func uniqueName(_ base: String, posture: String) -> String {
        let taken = Set(names(posture))
        var name = base
        var n = 2
        while taken.contains(name) {
            name = "\(base) \(n)"
            n += 1
        }
        return name
    }

    /// Built-in starting points. Each one starts from the fold-aware default arrangement.
    static let templates: [(name: String, layout: [String: Any])] = {
        let ids = OnScreenControls.controlIds()
        func scaled(_ scale: Double) -> [String: Any] {
            var layout: [String: Any] = [:]
            for id in ids { layout[id] = [0, 0, scale, 1, false] as [Any] }
            return layout
        }
        return [
            ("Default", [:]),
            ("Compact", scaled(0.8)),
            ("Large", scaled(1.25)),
            ("Faded", ["opacity": 0.4]),
        ]
    }()

    static func postureLabel(_ posture: String) -> String {
        switch posture {
        case "square": return "folded"
        case "roomy": return "unfolded"
        default: return "phone"
        }
    }

    // MARK: Files

    private static let format = "moonlume.osc-layout"

    static func fileData(name: String, posture: String, layout: [String: Any]) -> Data {
        let root: [String: Any] = ["format": format, "version": 1, "name": name, "posture": posture, "layout": layout]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    struct ImportError: LocalizedError {
        var errorDescription: String? { "This isn't a MoonLume controls layout file." }
    }

    /// Reads a layout file. Only number entries are kept, so anything else in the file never
    /// reaches the saved settings.
    static func read(_ url: URL) throws -> (name: String, layout: [String: Any]) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard data.count < 1_000_000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["format"] as? String == format,
              let raw = root["layout"] as? [String: Any] else {
            throw ImportError()
        }
        var layout: [String: Any] = [:]
        for (key, value) in raw where key.count <= 64 {
            if key == "opacity", let number = value as? NSNumber {
                layout[key] = number.doubleValue
            }
            else if let numbers = value as? [NSNumber], (2...8).contains(numbers.count) {
                layout[key] = numbers
            }
        }
        let name = (root["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (name.isEmpty ? "Imported" : String(name.prefix(40)), layout)
    }
}

/// A layout shared as a .json file (share sheet, Save to Files, AirDrop).
struct LayoutFile: Transferable {
    let fileName: String
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.fileName)
            try file.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

private struct LayoutEditorBar: View {
    @StateObject var model: LayoutEditorModel
    let hasGameLayout: Bool
    let onSave: (Bool) -> Void
    let onCancel: () -> Void
    let onMoveBar: (Bool) -> Void

    @SwiftUI.State private var atBottom = false
    @SwiftUI.State private var activeLayout: String?
    @SwiftUI.State private var naming = false
    @SwiftUI.State private var newName = ""
    @SwiftUI.State private var importing = false
    @SwiftUI.State private var importError: String?
    @SwiftUI.State private var confirmingCancel = false

    private var osc: OnScreenControls { model.osc }
    private var posture: String { osc.currentPosture() }

    var body: some View {
        VStack(spacing: 6) {
            if atBottom {
                detailRow
                mainRow
            }
            else {
                mainRow
                detailRow
            }
        }
        .environment(\.colorScheme, .dark)
        .tint(Theme.accent)
        .alert("Save layout", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Save") {
                let name = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                guard !name.isEmpty else { return }
                OSCProfiles.save(name, layout: osc.layoutDictionary(), posture: posture)
                activeLayout = name
                model.changed()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved layouts are listed for the \(OSCProfiles.postureLabel(posture)) screen. Using a name again replaces that layout.")
        }
        .alert("Couldn't import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let file = try OSCProfiles.read(try result.get())
                let name = OSCProfiles.uniqueName(file.name, posture: posture)
                OSCProfiles.save(name, layout: file.layout, posture: posture)
                osc.applyLayoutDictionary(file.layout)
                activeLayout = name
            }
            catch {
                importError = error.localizedDescription
            }
        }
    }

    private var mainRow: some View {
        HStack(spacing: 8) {
            Button { osc.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(PillButtonStyle())
                .disabled(!osc.canUndo())
                .accessibilityLabel("Undo")
            layoutsMenu
            Menu {
                Toggle("Snap to Guides", isOn: Binding(get: { osc.snapToGuides }, set: { osc.snapToGuides = $0 }))
                Button {
                    atBottom.toggle()
                    onMoveBar(atBottom)
                } label: {
                    Label(atBottom ? "Move Bar to Top" : "Move Bar to Bottom",
                          systemImage: atBottom ? "arrow.up.to.line" : "arrow.down.to.line")
                }
                Button(role: .destructive) {
                    osc.resetLayout()
                    activeLayout = nil
                } label: {
                    Label("Reset All Controls", systemImage: "arrow.counterclockwise")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(PillButtonStyle())
            .accessibilityLabel("Options")
            Button("Cancel") {
                // Changes made: ask before throwing them away
                if osc.canUndo() { confirmingCancel = true } else { onCancel() }
            }
            .buttonStyle(PillButtonStyle())
            .confirmationDialog("Discard your changes to the controls?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive, action: onCancel)
                Button("Keep Editing", role: .cancel) {}
            }
            Menu {
                Button("Save for this game") { onSave(true) }
                Button(hasGameLayout ? "Save for all games (replaces this game's)" : "Save for all games") { onSave(false) }
            } label: {
                Text("Save")
            }
            .buttonStyle(PillButtonStyle(primary: true))
        }
        .padding(6)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .overlay(Capsule().strokeBorder(Theme.lineStrong))
    }

    private var layoutsMenu: some View {
        Menu {
            Section("Templates") {
                ForEach(OSCProfiles.templates.indices, id: \.self) { i in
                    Button(OSCProfiles.templates[i].name) {
                        osc.applyLayoutDictionary(OSCProfiles.templates[i].layout)
                        activeLayout = nil
                    }
                }
            }
            let names = OSCProfiles.names(posture)
            if !names.isEmpty {
                Section("Saved · \(OSCProfiles.postureLabel(posture))") {
                    ForEach(names, id: \.self) { name in
                        Menu(name) {
                            Button {
                                if let layout = OSCProfiles.layout(name, posture: posture) {
                                    osc.applyLayoutDictionary(layout)
                                    activeLayout = name
                                }
                            } label: { Label("Use", systemImage: "checkmark") }
                            Button {
                                OSCProfiles.save(name, layout: osc.layoutDictionary(), posture: posture)
                                activeLayout = name
                                model.changed()
                            } label: { Label("Replace with Current", systemImage: "square.and.arrow.down.on.square") }
                            Button {
                                if let layout = OSCProfiles.layout(name, posture: posture) {
                                    OSCProfiles.save(OSCProfiles.uniqueName("\(name) copy", posture: posture), layout: layout, posture: posture)
                                    model.changed()
                                }
                            } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            if let layout = OSCProfiles.layout(name, posture: posture) {
                                ShareLink(item: LayoutFile(fileName: "\(name).json",
                                                           data: OSCProfiles.fileData(name: name, posture: posture, layout: layout)),
                                          preview: SharePreview(name)) {
                                    Label("Export", systemImage: "square.and.arrow.up")
                                }
                            }
                            Button(role: .destructive) {
                                OSCProfiles.delete(name, posture: posture)
                                if activeLayout == name { activeLayout = nil }
                                model.changed()
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
            Section {
                Button {
                    newName = activeLayout.map { OSCProfiles.uniqueName("\($0) copy", posture: posture) } ?? ""
                    naming = true
                } label: { Label("Save as New Layout…", systemImage: "plus") }
                Button { importing = true } label: { Label("Import…", systemImage: "square.and.arrow.down") }
                let name = activeLayout ?? "MoonLume layout"
                ShareLink(item: LayoutFile(fileName: "\(name).json",
                                           data: OSCProfiles.fileData(name: name, posture: posture, layout: osc.layoutDictionary())),
                          preview: SharePreview(name)) {
                    Label("Export Current…", systemImage: "square.and.arrow.up")
                }
            }
        } label: {
            Label(activeLayout ?? "Layouts", systemImage: "square.stack.3d.up")
                .lineLimit(1)
        }
        .buttonStyle(PillButtonStyle())
    }

    @ViewBuilder private var detailRow: some View {
        HStack(spacing: 10) {
            if let id = osc.selectedControl() {
                let hidden = osc.isControlHidden(id)
                Text(osc.displayName(forControl: id))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                slider("Size", value: Binding(get: { Double(osc.scale(forControl: id)) },
                                              set: { osc.setScale(CGFloat($0), forControl: id) }), in: 0.5...2)
                slider("Opacity", value: Binding(get: { Double(osc.opacity(forControl: id)) },
                                                 set: { osc.setOpacity(CGFloat($0), forControl: id) }), in: 0.15...1)
                Button { osc.setHidden(!hidden, forControl: id) } label: {
                    Image(systemName: hidden ? "eye.slash" : "eye")
                }
                .buttonStyle(RoundIconStyle(active: hidden))
                .accessibilityLabel(hidden ? "Show control" : "Hide control")
                if osc.controlSupportsToggle(id) {
                    let toggle = osc.isControlToggle(id)
                    Button { osc.setToggle(!toggle, forControl: id) } label: {
                        Image(systemName: toggle ? "pin.fill" : "pin")
                    }
                    .buttonStyle(RoundIconStyle(active: toggle))
                    .accessibilityLabel(toggle ? "Tap to toggle: on" : "Tap to toggle: off")
                }
                Button { osc.resetControl(id) } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(RoundIconStyle())
                    .accessibilityLabel("Reset this control")
                Button { osc.selectControl(nil) } label: { Image(systemName: "xmark") }
                    .buttonStyle(RoundIconStyle())
                    .accessibilityLabel("Done with this control")
            }
            else {
                Text("Tap a control to size, fade or hide it")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                slider("All", value: Binding(get: { Double(osc.globalOpacity) },
                                             set: { osc.globalOpacity = CGFloat($0) }), in: 0.15...1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .overlay(Capsule().strokeBorder(Theme.lineStrong))
    }

    /// A labelled slider; one undo step per drag.
    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Slider(value: value, in: range, onEditingChanged: { began in
                if began { osc.pushUndo() }
            })
            .frame(width: 96)
            .accessibilityLabel(title)
        }
    }
}

/// A small round icon button for the second row.
private struct RoundIconStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(active ? Color.black : Color(hex: 0xE4E4E8))
            .frame(width: 34, height: 34)
            .background {
                Circle().fill(active ? Theme.accent : Color.clear)
                Circle().strokeBorder(active ? Color.clear : Color(hex: 0x2A2A30))
            }
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
