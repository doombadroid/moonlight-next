//
//  SettingsView.swift
//  Moonlight Next
//
//  Port of SettingsViewController: same settings, ranges and capability checks,
//  saved through DataManager on every change.
//

import SwiftUI

/// Resolutions offered. 0x0 is "Native": resolved from the stream's window at launch.
private let resolutionOptions: [(label: String, width: Int, height: Int)] = [
    ("720p", 1280, 720),
    ("1080p", 1920, 1080),
    ("1440p", 2560, 1440),
    ("4K", 3840, 2160),
    ("Native", 0, 0),
]

/// Bitrate slider notches in Kbps (from SettingsViewController)
let bitrateTable = [500, 1000, 1500, 2000, 2500, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000,
                            12000, 15000, 18000, 20000, 30000, 40000, 50000, 60000, 70000, 80000,
                            100000, 120000, 150000, 200000, 250000, 300000, 400000, 500000, 600000, 800000]

/// Codec preference values (TemporarySettings' CODEC_PREF_* enum)
enum StreamCodec: Int, CaseIterable {
    case auto = 0, h264, hevc, av1

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        case .av1: return "AV1"
        }
    }
}

final class SettingsStore: ObservableObject {
    @Published var width: Int { didSet { save() } }
    @Published var height: Int { didSet { save() } }
    @Published var framerate: Int { didSet { save() } }
    @Published var bitrateIndex: Double { didSet { save() } }
    @Published var codec: Int { didSet { save() } }
    @Published var enableHdr: Bool { didSet { save() } }
    @Published var useFramePacing: Bool { didSet { save() } }
    @Published var absoluteTouchMode: Bool { didSet { save() } }
    @Published var onscreenControls: Int { didSet { save() } }
    @Published var multiController: Bool { didSet { save() } }
    @Published var swapABXYButtons: Bool { didSet { save() } }
    @Published var btMouseSupport: Bool { didSet { save() } }
    @Published var optimizeGames: Bool { didSet { save() } }
    @Published var playAudioOnPC: Bool { didSet { save() } }
    @Published var statsOverlay: Bool { didSet { save() } }
    /// Channel count: 2, 6 (5.1) or 8 (7.1)
    @Published var audioConfig: Int { didSet { save() } }

    let hevcSupported = MNBridge.hevcSupported()
    let av1Supported = MNBridge.av1Supported()
    let hdrSupported = MNBridge.hdrSupported()
    let yuv444Supported = MNBridge.yuv444Supported()
    let supports120 = UIScreen.main.maximumFramesPerSecond > 62

    init() {
        let s = DataManager().getSettings()!
        width = s.width.intValue
        height = s.height.intValue
        framerate = s.framerate.intValue
        // Snap to a slider notch
        let saved = s.bitrate.intValue
        bitrateIndex = Double(bitrateTable.firstIndex { $0 >= saved } ?? bitrateTable.count - 1)
        codec = (s.value(forKey: "preferredCodec") as? Int) ?? StreamCodec.auto.rawValue
        enableHdr = s.enableHdr
        useFramePacing = s.useFramePacing
        absoluteTouchMode = s.absoluteTouchMode
        onscreenControls = s.onscreenControls.intValue
        multiController = s.multiController
        swapABXYButtons = s.swapABXYButtons
        btMouseSupport = s.btMouseSupport
        optimizeGames = s.optimizeGames
        playAudioOnPC = s.playAudioOnPC
        statsOverlay = s.statsOverlay
        audioConfig = s.audioConfig.intValue
    }

    var bitrateKbps: Int { bitrateTable[Int(bitrateIndex)] }

    var codecs: [StreamCodec] {
        StreamCodec.allCases.filter { ($0 != .hevc || hevcSupported) && ($0 != .av1 || av1Supported) }
    }

    var resolutions: [(label: String, width: Int, height: Int)] {
        // 4K needs HEVC
        resolutionOptions.filter { $0.width != 3840 || hevcSupported }
    }

    var isCustomResolution: Bool {
        !resolutionOptions.contains { $0.width == width && $0.height == height }
    }

    /// Typed-in size: clamped to what hosts encode and rounded to even numbers.
    func setCustomResolution(width: Int, height: Int) {
        func even(_ v: Int, _ hi: Int) -> Int { min(max(v, 256), hi) & ~1 }
        setResolution(width: even(width, 7680), height: even(height, 4320))
    }

    func setResolution(width: Int, height: Int) {
        self.width = width
        self.height = height
        updateDefaultBitrate()
    }

    func setFramerate(_ fps: Int) {
        framerate = fps
        updateDefaultBitrate()
    }

    /// Default bitrate for the resolution and frame rate (logic from Moonlight Qt via SettingsViewController)
    private func updateDefaultBitrate() {
        var pixels = width * height
        if pixels == 0 {
            // Native: estimate from the screen
            let bounds = UIScreen.main.nativeBounds
            pixels = Int(bounds.width * bounds.height)
        }
        let fps = Float(framerate)
        // Don't scale bitrate linearly beyond 60 FPS
        let frameRateFactor = (fps <= 60 ? fps : sqrtf(fps / 60) * 60) / 30

        let resTable: [(pixels: Int, factor: Float)] = [
            (640 * 360, 1), (854 * 480, 2), (1280 * 720, 5), (1920 * 1080, 10), (2560 * 1440, 20), (3840 * 2160, 40),
        ]
        var resolutionFactor = resTable.last!.factor
        for (i, entry) in resTable.enumerated() where pixels <= entry.pixels {
            if pixels == entry.pixels || i == 0 {
                resolutionFactor = entry.factor
            } else {
                // Interpolate between this entry and the one below it
                let below = resTable[i - 1]
                resolutionFactor = Float(pixels - below.pixels) / Float(entry.pixels - below.pixels) * (entry.factor - below.factor) + below.factor
            }
            break
        }

        let defaultBitrate = min(Int((resolutionFactor * frameRateFactor).rounded()) * 1000, 100000)
        bitrateIndex = Double(bitrateTable.firstIndex { $0 >= defaultBitrate } ?? bitrateTable.count - 1)
    }

    private func save() {
        DataManager().saveSettings(withBitrate: bitrateKbps,
                                   framerate: framerate,
                                   height: height,
                                   width: width,
                                   audioConfig: audioConfig,
                                   onscreenControls: onscreenControls,
                                   optimizeGames: optimizeGames,
                                   multiController: multiController,
                                   swapABXYButtons: swapABXYButtons,
                                   audioOnPC: playAudioOnPC,
                                   preferredCodec: UInt32(codec),
                                   useFramePacing: useFramePacing,
                                   enableHdr: enableHdr && hdrSupported,
                                   btMouseSupport: btMouseSupport,
                                   absoluteTouchMode: absoluteTouchMode,
                                   statsOverlay: statsOverlay)
    }
}

/// One entry in Settings: a sidebar item on a wide screen, one or more sections in the list.
struct SettingsPage: Identifiable {
    let id: String
    let title: String
    let icon: String
    let content: AnyView

    init<Content: View>(_ id: String, _ title: String, icon: String, _ content: Content) {
        self.id = id
        self.title = title
        self.icon = icon
        self.content = AnyView(content)
    }
}

/// Compact width: one list with Favorites on top and collapsible sections. Wide (the Duo's inner
/// display, landscape): a sidebar of pages beside the selected page, like iPad Settings. Both
/// draw the same section views, so Favorites, search and controller navigation behave the same.
struct SettingsView: View {
    /// Opened from the stream menu: video settings wait for the next connection
    var inStream = false
    @StateObject private var store = SettingsStore()
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsIDs.favoritesKey) private var favorites = ""
    @AppStorage("mnSettingsPage") private var selectedPage = "video"
    @SwiftUI.State private var query = ""
    @SwiftUI.State private var showAbout = false

    /// Every section, in order. Each section file adds one line here.
    private var pages: [SettingsPage] {
        [
            SettingsPage("video", "Video", icon: "tv", VideoSettings(store: store, inStream: inStream)),
            SettingsPage("audio", "Audio", icon: "speaker.wave.2", AudioSettings(store: store)),
            SettingsPage("input", "Touch and input", icon: "hand.tap", InputSettings(store: store, inStream: inStream)),
            SettingsPage("controller", "Controller", icon: "gamecontroller", ControllerSettingsSection()),
            SettingsPage("gyro", "Gyro", icon: "gyroscope", GyroSettingsSection()),
            SettingsPage("controllerMouse", "Controller mouse", icon: "computermouse", ControllerMouseSettingsSection()),
            SettingsPage("controllerNavigation", "Controller navigation", icon: "dpad", ControllerNavigationSection()),
            SettingsPage("stream", "Stream", icon: "play.rectangle", StreamSettings(store: store)),
        ]
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                if geometry.size.width >= 700 {
                    HStack(spacing: 0) {
                        sidebar.frame(width: min(300, geometry.size.width * 0.32))
                        Rectangle().fill(Theme.line).frame(width: 1)
                        form(wide: true)
                    }
                } else {
                    form(wide: false)
                }
            }
            .background(Theme.ground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search settings")
            .navigationDestination(isPresented: $showAbout) {
                AboutView().navScreen(back: { showAbout = false })
            }
            .navScreen(back: { dismiss() })
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private func form(wide: Bool) -> some View {
        Form {
            if !query.isEmpty {
                Section {
                    allSections.environment(\.settingsMode, .search(query))
                } header: {
                    Theme.label("Results")
                } footer: {
                    Text("Settings whose name or tip mentions \u{201C}\(query)\u{201D}.")
                }
            } else if wide {
                if let page = pages.first(where: { $0.id == selectedPage }) {
                    page.content.environment(\.settingsMode, .page)
                } else {
                    favoritesSection.environment(\.settingsMode, .page)
                }
            } else {
                favoritesSection
                allSections
                Section {
                    aboutRow(pane: 1)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
    }

    private var allSections: some View {
        ForEach(pages) { $0.content }
    }

    private var favoritesSection: some View {
        SettingsSection("Favorites", id: "favorites") {
            if favorites.isEmpty {
                Text("Long-press a setting, or open its \(Image(systemName: "info.circle")), to pin it here.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            } else {
                allSections.environment(\.settingsMode, .favorites)
            }
        }
    }

    private func aboutRow(pane: Int) -> some View {
        Button {
            showAbout = true
        } label: {
            HStack {
                Label {
                    Text("About MoonLume").foregroundStyle(Theme.text)
                } icon: {
                    Image(systemName: "info.circle")
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
        }
        .navTarget(pane: pane) { showAbout = true }
    }

    private var sidebar: some View {
        List {
            Section {
                sidebarRow("favorites", "Favorites", icon: "star")
                ForEach(pages) { sidebarRow($0.id, $0.title, icon: $0.icon) }
            }
            Section {
                aboutRow(pane: 0)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
    }

    private func sidebarRow(_ id: String, _ title: String, icon: String) -> some View {
        let selected = query.isEmpty && selectedPage == id
        return Button {
            select(id)
        } label: {
            Label(title, systemImage: icon)
                .foregroundStyle(selected ? Theme.accent : Theme.text)
        }
        .listRowBackground(selected ? Theme.raised : nil)
        .navTarget(pane: 0) { select(id) }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func select(_ id: String) {
        selectedPage = id
        query = ""
    }
}

/// Settings over a running stream, from the stream menu (StreamFrameViewController is ObjC).
@objc final class MNSettingsSheet: NSObject {
    @objc static func makeViewController(onClose: @escaping () -> Void) -> UIViewController {
        UIHostingController(rootView: SettingsView(inStream: true).onDisappear(perform: onClose))
    }
}
