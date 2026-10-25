//
//  LauncherView.swift
//  Moonlight Next
//
//  Computers and their apps, in a NavigationSplitView: a sidebar of computers beside the
//  selected computer's apps on a wide window, a push from one to the other when folded.
//  The actions are real toolbar items, so on an iPhone Duo the system lays them out in its
//  vertical bar beside the status bar (folded, or unfolded in landscape) and keeps the split
//  clear of the fold when the device is held like a book. Layout follows size class and
//  available width, never the device model.
//
//  `State` alone is ambiguous here (Moonlight's host State enum), so SwiftUI's is spelled out.
//

import SwiftUI

struct LauncherView: View {
    @EnvironmentObject private var model: LauncherModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var nav = MNControllerNav.shared
    @SwiftUI.State private var showSettings = false
    @SwiftUI.State private var showAddHost = false
    @SwiftUI.State private var newHostAddress = ""
    /// The second page of a computer's controller options (X, then Y: More)
    @SwiftUI.State private var hostMore: TemporaryHost?

    /// The sidebar selection is the model's selected computer.
    private var hostSelection: Binding<String?> {
        Binding(
            get: { model.selectedHost?.uuid },
            set: { uuid in
                if let uuid, let host = model.hosts.first(where: { $0.uuid == uuid }) {
                    if host !== model.selectedHost { model.select(host, userInitiated: true) }
                } else {
                    model.deselectHost()
                }
            })
    }

    // Split in two: one modifier chain this long is too much for the type checker
    var body: some View {
        optionsDialogs(content)
            .sheet(isPresented: $nav.showWizard) { ControllerWizard() }
            .onAppear { MNControllerNav.shared.start() }
    }

    private var content: some View {
        NavigationSplitView {
            ComputersList(selection: hostSelection)
                .navigationTitle("Computers")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { showAddHost = true } label: { Label("Add computer", systemImage: "plus") }
                        Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    }
                }
        } detail: {
            if let host = model.selectedHost {
                HostDetailView(host: host)
            } else {
                EmptyState(icon: "desktopcomputer",
                           title: model.hosts.isEmpty ? "Searching for PCs on your network…" : "Choose a computer",
                           message: "MoonLume finds PCs running Sunshine or GeForce Experience on your network.")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.accent)
        .foregroundStyle(Theme.text)
        .overlay { BusyOverlay(message: model.busyMessage) }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: Binding(get: { model.hostDetails != nil }, set: { if !$0 { model.hostDetails = nil } })) {
            if let host = model.hostDetails { HostInfoSheet(host: host) }
        }
        .sheet(isPresented: Binding(get: { model.pairingPIN != nil }, set: { if !$0 { model.cancelPairing() } })) {
            PairingSheet(pin: model.pairingPIN ?? "", hostName: model.selectedHost?.name ?? "your PC") {
                model.cancelPairing()
            }
        }
        .alert(model.alert?.title ?? "", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.alert?.message ?? "")
        }
        .alert("Add Computer", isPresented: $showAddHost) {
            TextField("IP address or hostname", text: $newHostAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Cancel", role: .cancel) { newHostAddress = "" }
            Button("Add") {
                model.addHost(address: newHostAddress)
                newHostAddress = ""
            }
        } message: {
            Text("If your gaming PC isn't found automatically, enter its IP address.")
        }
        .confirmationDialog(model.runningAppChoice?.tapped.displayName ?? "",
                            isPresented: Binding(get: { model.runningAppChoice != nil }, set: { if !$0 { model.runningAppChoice = nil } }),
                            titleVisibility: .visible,
                            presenting: model.runningAppChoice) { choice in
            RunningAppActions(choice: choice)
        } message: { choice in
            if choice.tapped.id != choice.running.id {
                Text("\(choice.running.displayName) is currently running")
            }
        }
        // Controller navigation: B, Y/Menu, face buttons for the dialogs, X options, first-connection sheet
        .navScreen(back: navBack, settings: { showSettings = true })
        .navDialog(model.alert == nil ? nil : [NavDialogAction(button: .a, title: "OK") { model.alert = nil }])
        .navDialog(!showAddHost ? nil : [
            NavDialogAction(button: .a, title: "Add") {
                model.addHost(address: newHostAddress)
                newHostAddress = ""
                showAddHost = false
            },
            NavDialogAction(button: .b, title: "Cancel") {
                newHostAddress = ""
                showAddHost = false
            },
        ])
        .navDialog(model.runningAppChoice.map(runningAppDialog))
    }

    /// X on an app or a computer: its options, on face buttons and as a dialog
    private func optionsDialogs(_ content: some View) -> some View {
        content
            .navDialog(nav.optionsApp.map(appOptionsDialog))
            .navDialog(nav.optionsHost.map(hostOptionsDialog))
            .navDialog(hostMore.map(hostMoreDialog))
            .confirmationDialog(nav.optionsApp?.displayName ?? "",
                                isPresented: Binding(get: { nav.optionsApp != nil }, set: { if !$0 { nav.optionsApp = nil } }),
                                titleVisibility: .visible,
                                presenting: nav.optionsApp) { app in
                ForEach(appOptionsDialog(app).filter { $0.button != .b }, id: \.title) { action in
                    Button(action.title, action: action.perform)
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(nav.optionsHost?.name ?? "",
                                isPresented: Binding(get: { nav.optionsHost != nil }, set: { if !$0 { nav.optionsHost = nil } }),
                                titleVisibility: .visible,
                                presenting: nav.optionsHost) { host in
                ForEach(hostOptionsDialog(host).filter { $0.button != .b }, id: \.title) { action in
                    Button(action.title, action: action.perform)
                }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog(hostMore?.name ?? "",
                                isPresented: Binding(get: { hostMore != nil }, set: { if !$0 { hostMore = nil } }),
                                titleVisibility: .visible,
                                presenting: hostMore) { host in
                ForEach(hostMoreDialog(host).filter { $0.button != .b }, id: \.title) { action in
                    Button(action.title, role: action.button == .y ? .destructive : nil, action: action.perform)
                }
                Button("Back", role: .cancel) {}
            }
    }

    /// B on the launcher: back from a computer's apps to the list, when they're pushed (folded).
    private var navBack: (() -> Void)? {
        guard horizontalSizeClass != .regular, model.selectedHost != nil else { return nil }
        return { model.deselectHost() }
    }

    // MARK: Controller dialogs (the same actions as the touch menus, on face buttons)

    private func runningAppDialog(_ choice: RunningAppChoice) -> [NavDialogAction] {
        let same = choice.tapped.id == choice.running.id
        var actions = [NavDialogAction(button: .a, title: same ? "Resume" : "Resume \(choice.running.displayName)") {
            model.runningAppChoice = nil
            model.stream(choice.running)
        }]
        if let host = choice.running.host {
            actions.append(NavDialogAction(button: .x, title: same ? "Quit App" : "Quit and Start") {
                model.runningAppChoice = nil
                model.quitRunningApp(on: host, thenStream: same ? nil : choice.tapped)
            })
        }
        actions.append(NavDialogAction(button: .b, title: "Cancel") { model.runningAppChoice = nil })
        return actions
    }

    private func appOptionsDialog(_ app: TemporaryApp) -> [NavDialogAction] {
        let running = app.host.map { app.id == $0.currentGame } ?? false
        var actions = [NavDialogAction(button: .a, title: running ? "Resume" : "Launch") {
            nav.optionsApp = nil
            model.tapped(app)
        }]
        if running, let host = app.host {
            actions.append(NavDialogAction(button: .x, title: "Quit App") {
                nav.optionsApp = nil
                model.quitRunningApp(on: host)
            })
        }
        if !running || app.hidden {
            actions.append(NavDialogAction(button: .y, title: app.hidden ? "Show App" : "Hide App") {
                nav.optionsApp = nil
                model.toggleHidden(app)
            })
        }
        actions.append(NavDialogAction(button: .b, title: "Cancel") { nav.optionsApp = nil })
        return actions
    }

    private func hostOptionsDialog(_ host: TemporaryHost) -> [NavDialogAction] {
        let main: NavDialogAction
        if host.state != .online {
            main = NavDialogAction(button: .a, title: "Wake PC") {
                nav.optionsHost = nil
                model.wake(host)
            }
        } else if host.pairState == .unpaired {
            main = NavDialogAction(button: .a, title: "Pair") {
                nav.optionsHost = nil
                if host !== model.selectedHost { model.select(host, userInitiated: true) }
                model.pairSelectedHost()
            }
        } else {
            main = NavDialogAction(button: .a, title: "Refresh Apps") {
                nav.optionsHost = nil
                model.select(host, userInitiated: false)
            }
        }
        return [
            main,
            NavDialogAction(button: .x, title: "Computer Details") {
                nav.optionsHost = nil
                // A sheet can't come up while the dialog is still going away
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { model.hostDetails = host }
            },
            NavDialogAction(button: .y, title: "More…") {
                nav.optionsHost = nil
                // One dialog at a time: the second page comes up once the first has gone
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { hostMore = host }
            },
            NavDialogAction(button: .b, title: "Cancel") { nav.optionsHost = nil },
        ]
    }

    /// Second page: the rarer and destructive actions
    private func hostMoreDialog(_ host: TemporaryHost) -> [NavDialogAction] {
        [
            NavDialogAction(button: .x, title: "Test Network") {
                hostMore = nil
                model.testNetwork()
            },
            NavDialogAction(button: .y, title: "Remove Computer") {
                hostMore = nil
                model.remove(host)
            },
            NavDialogAction(button: .b, title: "Back") {
                hostMore = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { nav.optionsHost = host }
            },
        ]
    }
}

// MARK: - Actions for a tap while another app is running (port of appLongClicked)

private struct RunningAppActions: View {
    @EnvironmentObject private var model: LauncherModel
    let choice: RunningAppChoice

    var body: some View {
        let same = choice.tapped.id == choice.running.id
        Button(same ? "Resume" : "Resume \(choice.running.displayName)") {
            model.stream(choice.running)
        }
        if let host = choice.running.host {
            Button(same ? "Quit App" : "Quit Running App and Start", role: .destructive) {
                model.quitRunningApp(on: host, thenStream: same ? nil : choice.tapped)
            }
        }
        Button("Cancel", role: .cancel) {}
    }
}

// MARK: - Computers (sidebar unfolded, root screen folded)

private struct ComputersList: View {
    @EnvironmentObject private var model: LauncherModel
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            if model.hosts.isEmpty {
                Text("Searching for PCs on your network…")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .listRowBackground(Color.clear)
            }
            ForEach(model.hosts, id: \.uuid) { host in
                HostRow(host: host, selected: host === model.selectedHost)
                    .navTarget(pane: 0, options: { MNControllerNav.shared.optionsHost = host }) {
                        if host !== model.selectedHost { model.select(host, userInitiated: true) }
                    }
                    .tag(host.uuid as String?)
                    .contextMenu { HostActions(host: host) }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
    }
}

/// A computer in the list. Taps go to the list's selection, not to the row; the Launch
/// pill is its own button.
struct HostRow: View {
    @EnvironmentObject private var model: LauncherModel
    let host: TemporaryHost
    var selected = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 17))
                .foregroundStyle(Color(hex: 0xA3A3AA))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text(host.statusText).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            if host.state == .online && host.pairState == .paired {
                launchButton
            }
            Circle().fill(host.state == .online ? Theme.online : Theme.offline).frame(width: 8, height: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Theme.raised : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color(hex: 0x2A2A32) : Color.clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Resumes the running app, else starts the last one played, else opens the app list.
    private var launchButton: some View {
        let app = model.quickLaunchApp(on: host)
        let resume = app != nil && app?.id == host.currentGame
        return Button { model.quickLaunch(host) } label: {
            Label(resume ? "Resume" : "Launch", systemImage: "play.fill")
                .font(.system(size: 13, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Color.black)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(Capsule().fill(Theme.accent))
                .contentShape(Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(app.map { "\(resume ? "Resume" : "Launch") \($0.displayName)" } ?? "Open apps on \(host.name)")
    }
}

/// Long-press actions for a computer in the list.
private struct HostActions: View {
    @EnvironmentObject private var model: LauncherModel
    let host: TemporaryHost

    var body: some View {
        if let app = model.quickLaunchApp(on: host) {
            Button { model.stream(app) } label: {
                Label("\(app.id == host.currentGame ? "Resume" : "Launch") \(app.displayName)", systemImage: "play.fill")
            }
        }
        Button { model.hostDetails = host } label: { Label("Computer Details", systemImage: "info.circle") }
        if host.state != .online {
            Button { model.wake(host) } label: { Label("Wake PC", systemImage: "power") }
        }
    }
}

extension TemporaryHost {
    var statusText: String {
        switch state {
        case .online:
            return pairState == .paired ? "Online · paired" : (pairState == .unpaired ? "Online · tap to pair" : "Online")
        case .offline:
            return "Offline"
        default:
            return "Connecting…"
        }
    }
}

// MARK: - Host page

private struct HostDetailView: View {
    @EnvironmentObject private var model: LauncherModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let host: TemporaryHost

    private var compact: Bool { horizontalSizeClass != .regular }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(host.statusText).font(.system(size: 13)).foregroundStyle(Theme.muted)

                if host.state == .offline {
                    OfflineCard(host: host)
                } else if host.state == .online && host.pairState == .unpaired {
                    UnpairedCard(host: host)
                } else {
                    if let running = model.runningApp(on: host) {
                        NowRunningCard(app: running, compact: compact)
                    }
                    library
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, compact ? 20 : 28)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
        .refreshable { model.select(host, userInitiated: false) }
        .navigationTitle(host.name)
        .toolbar {
            // Icon-only items: on an iPhone Duo they move into the vertical bar
            ToolbarItemGroup(placement: .primaryAction) {
                if host.state != .online {
                    Button { model.wake(host) } label: { Label("Wake PC", systemImage: "power") }
                }
                Button { model.select(host, userInitiated: false) } label: {
                    Label("Refresh apps", systemImage: "arrow.clockwise")
                }
                hostMenu
            }
        }
    }

    private var hostMenu: some View {
        Menu {
            Button { model.hostDetails = host } label: { Label("Computer Details", systemImage: "info.circle") }
            if host.pairState == .paired {
                Button {
                    model.setShowHiddenApps(!model.showHiddenApps)
                } label: {
                    Label(model.showHiddenApps ? "Hide Hidden Apps" : "View All Apps", systemImage: "eye")
                }
            }
            Button { model.testNetwork() } label: { Label("Test Network", systemImage: "network") }
            Button(role: .destructive) { model.remove(host) } label: { Label("Remove Computer", systemImage: "trash") }
        } label: {
            Label("More for \(host.name)", systemImage: "ellipsis")
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Library").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(model.apps.count) apps").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: compact ? 12 : 14)],
                      spacing: compact ? 12 : 14) {
                ForEach(model.apps, id: \.self) { app in
                    AppTile(app: app, running: app.id == host.currentGame)
                }
            }
        }
    }
}

private struct NowRunningCard: View {
    @EnvironmentObject private var model: LauncherModel
    let app: TemporaryApp
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 12 : 16) {
            BoxArt(app: app, showTitle: false)
                .frame(width: compact ? 36 : 44, height: compact ? 48 : 58)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 3) {
                Text("NOW RUNNING")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.5)
                    .foregroundStyle(Theme.accent)
                Text(app.displayName)
                    .font(.system(size: compact ? 15 : 16, weight: .medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Resume") { model.stream(app) }
                .buttonStyle(PillButtonStyle(primary: true))
                .navTarget { model.stream(app) }
            if !compact, let host = app.host {
                Button("Quit") { model.quitRunningApp(on: host) }
                    .buttonStyle(PillButtonStyle())
                    .navTarget { model.quitRunningApp(on: host) }
            }
        }
        .padding(compact ? 10 : 12)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line))
    }
}

private struct AppTile: View {
    @EnvironmentObject private var model: LauncherModel
    let app: TemporaryApp
    let running: Bool

    var body: some View {
        Button { model.tapped(app) } label: {
            BoxArt(app: app, showTitle: true)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.tileRadius)
                    .strokeBorder(running ? Theme.accent : Color.clear, lineWidth: 2))
                .opacity(app.hidden ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .navTarget(options: { MNControllerNav.shared.optionsApp = app }) { model.tapped(app) }
        .accessibilityLabel(app.displayName)
        .accessibilityHint(running ? "Running" : "")
        .contextMenu {
            Button { model.tapped(app) } label: {
                Label(running ? "Resume" : "Launch", systemImage: "play.fill")
            }
            if running, let host = app.host {
                Button(role: .destructive) { model.quitRunningApp(on: host) } label: {
                    Label("Quit App", systemImage: "power")
                }
            }
            if !running || app.hidden {
                Button(role: app.hidden ? nil : .destructive) { model.toggleHidden(app) } label: {
                    Label(app.hidden ? "Show App" : "Hide App", systemImage: app.hidden ? "eye" : "eye.slash")
                }
            }
        }
    }
}

/// Box art, or MoonLume's tile (a glyph and the app's name) when the host has no art or sent
/// its blank placeholder.
private struct BoxArt: View {
    @EnvironmentObject private var model: LauncherModel
    let app: TemporaryApp
    let showTitle: Bool

    var body: some View {
        // Reading boxArtVersion re-renders this view when new art finishes decoding
        let _ = model.boxArtVersion
        if let image = model.boxArt(for: app) {
            Color.clear
                .overlay { Image(uiImage: image).resizable().scaledToFill() }
                .clipped()
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hex: 0x17171D), Color(hex: 0x0B0B0E)], startPoint: .top, endPoint: .bottom)
            Image(systemName: app.isDesktop ? "desktopcomputer" : "gamecontroller")
                .font(.system(size: showTitle ? 26 : 15, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, showTitle ? 28 : 0)
            if showTitle {
                Text(app.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                    .padding(10)
            }
        }
        .overlay(alignment: .top) { Theme.accent.opacity(0.35).frame(height: 2) }
    }
}

extension TemporaryApp {
    /// The name shown in the launcher: "Steam Big Picture" is just Steam.
    var displayName: String {
        let name = self.name ?? "App"
        return name == "Steam Big Picture" ? "Steam" : name
    }

    var isDesktop: Bool { name?.caseInsensitiveCompare("Desktop") == .orderedSame }
}

// MARK: - States

private struct OfflineCard: View {
    @EnvironmentObject private var model: LauncherModel
    let host: TemporaryHost

    var body: some View {
        StateCard(icon: "moon.zzz",
                  title: "\(host.name) is offline",
                  message: "Wake it with Wake-on-LAN, or check that it's on and connected to this network.") {
            Button("Wake PC") { model.wake(host) }.buttonStyle(PillButtonStyle(primary: true))
                .navTarget { model.wake(host) }
            Button("Test Network") { model.testNetwork() }.buttonStyle(PillButtonStyle())
                .navTarget { model.testNetwork() }
        }
    }
}

private struct UnpairedCard: View {
    @EnvironmentObject private var model: LauncherModel
    let host: TemporaryHost

    var body: some View {
        StateCard(icon: "link",
                  title: "Pair with \(host.name)",
                  message: "You'll get a PIN to enter on the PC. For Sunshine, enter it in Sunshine's web UI.") {
            Button("Pair") { model.pairSelectedHost() }.buttonStyle(PillButtonStyle(primary: true))
                .navTarget { model.pairSelectedHost() }
        }
    }
}

private struct StateCard<Actions: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Theme.accent)
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(message).font(.system(size: 14)).foregroundStyle(Theme.muted)
            HStack(spacing: 10) { actions }.padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line))
    }
}

private struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(Theme.muted)
            Text(title).font(.system(size: 18, weight: .semibold))
            Text(message).font(.system(size: 14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BusyOverlay: View {
    let message: String?

    var body: some View {
        if let message {
            ZStack {
                Color.black.opacity(0.6).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView().tint(Theme.text)
                    Text(message).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                }
                .padding(24)
                .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line))
            }
            .transition(.opacity)
        }
    }
}

private struct PairingSheet: View {
    let pin: String
    let hostName: String
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Theme.label("Pairing")
            Text(pin)
                .font(.system(size: 48, weight: .semibold, design: .monospaced))
                .tracking(8)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("PIN \(pin.map(String.init).joined(separator: " "))")
            Text("Enter this PIN on \(hostName). If it runs Sunshine, enter it in Sunshine's web UI.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Cancel", action: cancel).buttonStyle(PillButtonStyle())
                .navTarget(activate: cancel)
        }
        .navScreen(back: cancel)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground.ignoresSafeArea())
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}
