//
//  SettingsKit.swift
//  MoonLume
//
//  Building blocks for the Settings sections: collapsible sections, rows that can be pinned to
//  Favorites and found by search, and (i) tips. A section file builds its rows from these and
//  adds one line to SettingsView.pages.
//
//  Behaviour modelled on VoidLink's settings shell (GPLv3, SettingsSwiftUI.swift); the code is
//  MoonLume's own.
//

import SwiftUI

/// How the sections around a row are being shown.
enum SettingsMode: Equatable {
    /// One scrolling list (compact width): sections collapse.
    case list
    /// One page beside the sidebar (wide screen): sections stay open.
    case page
    /// Only pinned rows, without section headers (the Favorites section).
    case favorites
    /// Only rows whose title or tip matches, without section headers.
    case search(String)
}

private struct SettingsModeKey: EnvironmentKey {
    static let defaultValue = SettingsMode.list
}

extension EnvironmentValues {
    var settingsMode: SettingsMode {
        get { self[SettingsModeKey.self] }
        set { self[SettingsModeKey.self] = newValue }
    }
}

/// Sets of row or section ids kept as one newline-separated @AppStorage string.
enum SettingsIDs {
    static let favoritesKey = "mnSettingsFavorites"
    static let collapsedKey = "mnSettingsCollapsed"

    static func contains(_ raw: String, _ id: String) -> Bool {
        raw.split(separator: "\n").contains { $0 == id }
    }

    static func toggle(_ raw: inout String, _ id: String) {
        var ids = raw.split(separator: "\n").map(String.init)
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        raw = ids.joined(separator: "\n")
    }
}

/// A Settings section. In the list its header collapses it (remembered); in Favorites and search
/// results only its matching rows show, merged into one section.
struct SettingsSection<Content: View, Footer: View>: View {
    let title: String
    let id: String
    let content: Content
    let footer: Footer

    @Environment(\.settingsMode) private var mode
    @AppStorage(SettingsIDs.collapsedKey) private var collapsed = ""

    init(_ title: String, id: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.id = id
        self.content = content()
        self.footer = footer()
    }

    private var isOpen: Bool { mode != .list || !SettingsIDs.contains(collapsed, id) }

    var body: some View {
        switch mode {
        case .favorites, .search:
            content
        case .page:
            Section {
                content
            } header: {
                Theme.label(title)
            } footer: {
                footer
            }
        case .list:
            Section {
                if isOpen { content }
            } header: {
                header.id("\(id)-header")
            } footer: {
                if isOpen { footer }
            }
            .id(id)
        }
    }

    /// Collapsed sections draw no rows, so the controller ring can't land inside one.
    private var header: some View {
        Button(action: toggle) {
            HStack {
                Theme.label(title)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .rotationEffect(.degrees(isOpen ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .navTarget(activate: toggle)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
    }

    private func toggle() {
        withAnimation(.easeOut(duration: 0.2)) {
            SettingsIDs.toggle(&collapsed, id)
        }
    }
}

extension SettingsSection where Footer == EmptyView {
    init(_ title: String, id: String, @ViewBuilder content: () -> Content) {
        self.init(title, id: id, content: content, footer: { EmptyView() })
    }
}

/// A setting's title, with an (i) button when it has a tip.
struct SettingLabel: View {
    let title: String
    let hasTip: Bool
    let showTip: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if hasTip {
                Button(action: showTip) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.borderless)
                .navTarget(activate: showTip)
                .accessibilityLabel("About \(title)")
            }
        }
    }
}

/// One setting. `id` is stored in Favorites, so it must never change. Long-press pins or unpins
/// it; the tip's dialog can too (the only way with a controller).
struct SettingRow<Content: View>: View {
    let title: String
    let id: String
    let tip: String?
    let learnMore: URL?
    let content: (SettingLabel) -> Content

    @Environment(\.settingsMode) private var mode
    @Environment(\.openURL) private var openURL
    @AppStorage(SettingsIDs.favoritesKey) private var favorites = ""
    @SwiftUI.State private var tipShown = false

    init(_ title: String, id: String, tip: String? = nil, learnMore: String? = nil,
         @ViewBuilder content: @escaping (SettingLabel) -> Content) {
        self.title = title
        self.id = id
        self.tip = tip
        self.learnMore = learnMore.flatMap(URL.init(string:))
        self.content = content
    }

    private var isPinned: Bool { SettingsIDs.contains(favorites, id) }

    private var isShown: Bool {
        switch mode {
        case .list, .page:
            return true
        case .favorites:
            return isPinned
        case .search(let query):
            return title.localizedCaseInsensitiveContains(query) || (tip?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        if isShown {
            content(SettingLabel(title: title, hasTip: tip != nil, showTip: { tipShown = true }))
                .contextMenu {
                    Button(isPinned ? "Remove from Favorites" : "Add to Favorites",
                           systemImage: isPinned ? "star.slash" : "star", action: togglePin)
                }
                .alert(title, isPresented: $tipShown) {
                    if let learnMore {
                        Button("Learn More") { openURL(learnMore) }
                    }
                    Button(isPinned ? "Remove from Favorites" : "Add to Favorites", action: togglePin)
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(tip ?? "")
                }
                .navDialog(tipShown ? dialogActions : nil)
        }
    }

    private var dialogActions: [NavDialogAction] {
        var actions = [NavDialogAction(button: .a, title: "OK") { tipShown = false }]
        if let learnMore {
            actions.append(NavDialogAction(button: .x, title: "Learn More") {
                tipShown = false
                openURL(learnMore)
            })
        }
        actions.append(NavDialogAction(button: .y, title: isPinned ? "Unpin" : "Pin") {
            tipShown = false
            togglePin()
        })
        return actions
    }

    private func togglePin() {
        withAnimation { SettingsIDs.toggle(&favorites, id) }
    }
}

/// A switch row.
struct SettingToggle: View {
    let title: String
    let id: String
    @Binding var isOn: Bool
    var tip: String?
    var learnMore: String?

    init(_ title: String, id: String, isOn: Binding<Bool>, tip: String? = nil, learnMore: String? = nil) {
        self.title = title
        self.id = id
        _isOn = isOn
        self.tip = tip
        self.learnMore = learnMore
    }

    var body: some View {
        SettingRow(title, id: id, tip: tip, learnMore: learnMore) { label in
            Toggle(isOn: $isOn) { label }
        }
    }
}

/// A title over a segmented picker.
struct SettingChoice<Control: View>: View {
    let title: String
    let id: String
    var note: String?
    var tip: String?
    var learnMore: String?
    let picker: Control

    init(_ title: String, id: String, note: String? = nil, tip: String? = nil, learnMore: String? = nil,
         @ViewBuilder picker: () -> Control) {
        self.title = title
        self.id = id
        self.note = note
        self.tip = tip
        self.learnMore = learnMore
        self.picker = picker()
    }

    var body: some View {
        SettingRow(title, id: id, tip: tip, learnMore: learnMore) { label in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    label
                    Spacer()
                    if let note {
                        Text(note).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                }
                picker.pickerStyle(.segmented).labelsHidden()
            }
            .padding(.vertical, 4)
        }
    }
}

/// A title and value over a slider. `format` is applied to value × scale.
struct SettingSlider: View {
    let title: String
    let id: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step = 0.25
    var format = "%.2g×"
    var scale = 1.0
    var tip: String?

    init(_ title: String, id: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 0.25,
         format: String = "%.2g×", scale: Double = 1, tip: String? = nil) {
        self.title = title
        self.id = id
        _value = value
        self.range = range
        self.step = step
        self.format = format
        self.scale = scale
        self.tip = tip
    }

    var body: some View {
        SettingRow(title, id: id, tip: tip) { label in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    label
                    Spacer()
                    Text(String(format: format, value * scale)).foregroundStyle(Theme.muted)
                }
                Slider(value: $value, in: range, step: step)
            }
        }
    }
}
