//
//  LauncherView.swift
//  Moonlight Next
//
//  Hosts + library. Unfolded (regular width): sidebar of computers beside the library.
//  Folded (compact width): one column with a computer switcher at the top.
//  Layout follows size class and available width, never the device model.
//
//  `State` alone is ambiguous here (Moonlight's host State enum), so SwiftUI's is spelled out.
//

import SwiftUI

struct LauncherView: View {
    @EnvironmentObject private var model: LauncherModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @SwiftUI.State private var showSettings = false
    @SwiftUI.State private var showAddHost = false
    @SwiftUI.State private var newHostAddress = ""

    var body: some View {
        GeometryReader { geo in
            Group {
                if horizontalSizeClass == .regular && geo.size.width >= 600 {
                    HStack(spacing: 0) {
                        Sidebar(showSettings: $showSettings, showAddHost: $showAddHost)
                            .frame(width: 268)
                        Rectangle().fill(Theme.line).frame(width: 1)
                        detail(compact: false)
                    }
                } else {
                    detail(compact: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.ground.ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .overlay { BusyOverlay(message: model.busyMessage) }
        .sheet(isPresented: $showSettings) { SettingsView() }
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
        .confirmationDialog(model.runningAppChoice?.tapped.name ?? "",
                            isPresented: Binding(get: { model.runningAppChoice != nil }, set: { if !$0 { model.runningAppChoice = nil } }),
                            titleVisibility: .visible,
                            presenting: model.runningAppChoice) { choice in
            RunningAppActions(choice: choice)
        } message: { choice in
            if choice.tapped.id != choice.running.id {
                Text("\(choice.running.name ?? "Another app") is currently running")
            }
        }
    }

    @ViewBuilder
    private func detail(compact: Bool) -> some View {
        if let host = model.selectedHost {
            HostDetailView(host: host, compact: compact, showSettings: $showSettings, showAddHost: $showAddHost)
        } else if compact {
            CompactHostList(showSettings: $showSettings, showAddHost: $showAddHost)
        } else {
            EmptyState(icon: "desktopcomputer",
                       title: model.hosts.isEmpty ? "Searching for PCs on your network…" : "Choose a computer",
                       message: "Moonlight Next finds PCs running Sunshine or GeForce Experience on your network.")
        }
    }
}

// MARK: - Actions for a tap while another app is running (port of appLongClicked)

private struct RunningAppActions: View {
    @EnvironmentObject private var model: LauncherModel
    let choice: RunningAppChoice

    var body: some View {
        let same = choice.tapped.id == choice.running.id
        Button(same ? "Resume" : "Resume \(choice.running.name ?? "Running App")") {
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

// MARK: - Sidebar (unfolded)

private struct Sidebar: View {
    @EnvironmentObject private var model: LauncherModel
    @Binding var showSettings: Bool
    @Binding var showAddHost: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "moon")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Text("Moonlight Next")
                    .font(.system(size: 17, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 18)

            Theme.label("Computers")
                .padding(.horizontal, 8)
                .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.hosts, id: \.uuid) { host in
                        HostRow(host: host, selected: host === model.selectedHost) {
                            model.select(host, userInitiated: true)
                        }
                    }
                    if model.hosts.isEmpty {
                        Text("Searching…")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                    }
                }
            }

            SidebarButton(icon: "plus", title: "Add computer") { showAddHost = true }
            SidebarButton(icon: "gearshape", title: "Settings") { showSettings = true }
        }
        .padding(.top, 26)
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
    }
}

private struct SidebarButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16)).frame(width: 20)
                Text(title).font(.system(size: 15))
                Spacer()
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }
}

struct HostRow: View {
    let host: TemporaryHost
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: 0xA3A3AA))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name).font(.system(size: 15, weight: .medium))
                    Text(host.statusText).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                Circle().fill(host.state == .online ? Theme.online : Theme.offline).frame(width: 8, height: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Theme.raised : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color(hex: 0x2A2A32) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

// MARK: - Host list (folded, nothing selected)

private struct CompactHostList: View {
    @EnvironmentObject private var model: LauncherModel
    @Binding var showSettings: Bool
    @Binding var showAddHost: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    HStack(spacing: 10) {
                        Image(systemName: "moon").foregroundStyle(Theme.accent)
                        Text("Moonlight Next").font(.system(size: 20, weight: .semibold))
                    }
                    Spacer()
                    CircleIconButton(systemName: "plus", label: "Add computer") { showAddHost = true }
                    CircleIconButton(systemName: "gearshape", label: "Settings") { showSettings = true }
                }
                Theme.label("Computers")
                if !model.hosts.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(model.hosts, id: \.uuid) { host in
                            HostRow(host: host) { model.select(host, userInitiated: true) }
                        }
                    }
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line))
                } else {
                    Text("Searching for PCs on your network…")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
    }
}

// MARK: - Host page

private struct HostDetailView: View {
    @EnvironmentObject private var model: LauncherModel
    let host: TemporaryHost
    let compact: Bool
    @Binding var showSettings: Bool
    @Binding var showAddHost: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if compact { compactTopBar } else { header }

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
            .padding(.top, compact ? 18 : 26)
            .padding(.horizontal, compact ? 20 : 28)
            .padding(.bottom, 24)
        }
        .refreshable { model.select(host, userInitiated: false) }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(host.name).font(.system(size: 28, weight: .semibold))
                Text(host.statusText).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            Spacer()
            hostMenu
        }
    }

    private var compactTopBar: some View {
        HStack {
            Menu {
                ForEach(model.hosts, id: \.uuid) { other in
                    Button {
                        model.select(other, userInitiated: true)
                    } label: {
                        Label(other.name, systemImage: other === host ? "checkmark" : "desktopcomputer")
                    }
                }
                Divider()
                Button { model.deselectHost() } label: { Label("All computers", systemImage: "list.bullet") }
                Button { showAddHost = true } label: { Label("Add computer", systemImage: "plus") }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(host.state == .online ? Theme.online : Theme.offline).frame(width: 8, height: 8)
                    Text(host.name).font(.system(size: 16, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(Theme.text)
                .padding(.leading, 12)
                .padding(.trailing, 14)
                .frame(minHeight: 44)
                .overlay(Capsule().strokeBorder(Theme.lineStrong))
            }
            Spacer()
            hostMenu
            CircleIconButton(systemName: "gearshape", label: "Settings") { showSettings = true }
        }
    }

    private var hostMenu: some View {
        Menu {
            if host.state != .online {
                Button { model.wake(host) } label: { Label("Wake PC", systemImage: "power") }
            }
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
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(Theme.lineStrong))
        }
        .accessibilityLabel("More for \(host.name)")
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
                Text(app.name ?? "")
                    .font(.system(size: compact ? 15 : 16, weight: .medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Resume") { model.stream(app) }
                .buttonStyle(PillButtonStyle(primary: true))
            if !compact, let host = app.host {
                Button("Quit") { model.quitRunningApp(on: host) }
                    .buttonStyle(PillButtonStyle())
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
        .accessibilityLabel(app.name ?? "App")
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

/// Box art, or the app's name on a dark tile until art arrives.
private struct BoxArt: View {
    @EnvironmentObject private var model: LauncherModel
    let app: TemporaryApp
    let showTitle: Bool

    var body: some View {
        // Reading boxArtVersion re-renders this view when new art finishes decoding
        let _ = model.boxArtVersion
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Color(hex: 0x1A1A1E))
            if let image = model.boxArt(for: app) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if showTitle {
                Text(app.name ?? "")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
            }
        }
        .clipped()
    }
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
            Button("Test Network") { model.testNetwork() }.buttonStyle(PillButtonStyle())
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
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground.ignoresSafeArea())
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}
