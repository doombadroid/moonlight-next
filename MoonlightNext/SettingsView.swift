//
//  SettingsView.swift
//  Moonlight Next
//
//  Port of SettingsViewController: same settings, ranges and capability checks,
//  saved through DataManager on every change.
//

import AVKit
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
private let bitrateTable = [500, 1000, 1500, 2000, 2500, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000,
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

struct SettingsView: View {
    /// Opened from the stream menu: video settings wait for the next connection
    var inStream = false
    @StateObject private var store = SettingsStore()
    @Environment(\.dismiss) private var dismiss
    /// Read by the input deck and the on-screen controls on every press.
    @AppStorage("mnHapticsEnabled") private var hapticsEnabled = true
    @AppStorage("mnOSCPressHighlight") private var pressHighlight = true
    @AppStorage("mnTrackpadSpeed") private var trackpadSpeed = 2.0
    @AppStorage("mnPictureInPicture") private var pictureInPicture = true
    @AppStorage(MNTouchPrefs.touchModeKey) private var touchMode = MNTouchMode.touchpad.rawValue
    @AppStorage(MNTouchPrefs.pointerSpeedKey) private var touchpadPointerSpeed = 1.0
    @AppStorage(MNTouchPrefs.scrollSpeedKey) private var scrollSpeed = 1.0
    @AppStorage(MNTouchPrefs.momentumKey) private var scrollMomentum = true
    @AppStorage(MNTouchPrefs.pinchZoomKey) private var pinchZoom = true
    @AppStorage(MNTouchPrefs.reverseScrollKey) private var reverseScroll = false
    @AppStorage(MNTouchPrefs.topDeadZoneKey) private var topDeadZone = true
    @AppStorage(MNTouchPrefs.keyboardFingersKey) private var keyboardFingers = 3
    @AppStorage(MNTouchPrefs.edgeSwipeKey) private var edgeSwipe = MNTouchPrefs.EdgeSwipe.disconnect.rawValue
    @AppStorage(MNTouchPrefs.cursorModeKey) private var cursorMode = MNTouchPrefs.CursorMode.captured.rawValue

    /// Touchscreen is the older absoluteTouchMode setting; the other modes live in mnTouchMode
    private var touchModeSelection: Binding<Int> {
        Binding(get: {
            if store.absoluteTouchMode { return MNTouchMode.touchscreen.rawValue }
            return touchMode == MNTouchMode.native.rawValue || touchMode == MNTouchMode.disabled.rawValue ? touchMode : MNTouchMode.touchpad.rawValue
        }, set: {
            store.absoluteTouchMode = $0 == MNTouchMode.touchscreen.rawValue
            touchMode = $0
        })
    }
    // Video, audio and stream options (read by MNBridge, Connection and the stream screen)
    @AppStorage("mnResolutionSafeArea") private var safeAreaResolution = false
    @AppStorage("mnYUV444") private var yuv444 = false
    @AppStorage("mnFullColorRange") private var fullColorRange = false
    @AppStorage("mnStatsDetailed") private var statsDetailed = true
    // Unset until chosen: then the old on/off pacing setting decides (on = Balanced)
    @AppStorage("mnFramePacingMode") private var framePacingMode: Int?
    @AppStorage("mnFrameQueueDepth") private var frameQueueDepth = 2
    @AppStorage("mnVideoRenderer") private var videoRenderer = 0
    @AppStorage("mnFrameInterpolation") private var frameInterpolation = false
    @AppStorage(MNAudio.volumeKey) private var streamVolume = 1.0
    @AppStorage(MNAudio.mixKey) private var mixWithOthers = false
    @AppStorage(MNAudio.muteInBackgroundKey) private var muteInBackground = false
    @AppStorage(MNAudio.backgroundMinutesKey) private var backgroundMinutes = 0
    @AppStorage(MNExternalDisplay.enabledKey) private var externalDisplayOnly = false
    @State private var showCustomResolution = false
    @State private var customWidth = ""
    @State private var customHeight = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    resolutionRow
                    choice("Frame rate") {
                        Picker("Frame rate", selection: Binding(get: { store.framerate }, set: { store.setFramerate($0) })) {
                            Text("30").tag(30)
                            Text("60").tag(60)
                            if store.supports120 { Text("120").tag(120) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Bitrate")
                            Spacer()
                            Text(String(format: "%.1f Mb/s", Double(store.bitrateKbps) / 1000))
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(Theme.accent)
                        }
                        Slider(value: $store.bitrateIndex, in: 0...Double(bitrateTable.count - 1), step: 1)
                            .accessibilityValue(String(format: "%.1f megabits per second", Double(store.bitrateKbps) / 1000))
                    }
                    .padding(.vertical, 4)
                    choice("Codec") {
                        Picker("Codec", selection: $store.codec) {
                            ForEach(store.codecs, id: \.self) { Text($0.label).tag($0.rawValue) }
                        }
                    }
                    if store.hdrSupported {
                        Toggle("HDR", isOn: $store.enableHdr)
                    }
                    if store.yuv444Supported && [StreamCodec.auto.rawValue, StreamCodec.hevc.rawValue].contains(store.codec) {
                        Toggle("Full color (4:4:4)", isOn: $yuv444)
                    }
                    Toggle("Full color range", isOn: $fullColorRange)
                    choice("Frame pacing") {
                        Picker("Frame pacing", selection: Binding(
                            get: { framePacingMode ?? (store.useFramePacing ? 1 : 0) },
                            set: { framePacingMode = $0; store.useFramePacing = $0 != 0 })) {
                            Text("Lowest latency").tag(0)
                            Text("Balanced").tag(1)
                            Text("Smoothest").tag(2)
                        }
                    }
                    if framePacingMode == 2 {
                        choice("Frames queued") {
                            Picker("Frames queued", selection: $frameQueueDepth) {
                                ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                            }
                        }
                    }
                } header: {
                    Theme.label("Video")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if inStream {
                            Text("Video, sound channels and resolution apply the next time you connect. Controls, gyro, haptics, volume and trackpad speed apply now.")
                        }
                        Text("Full color (4:4:4) keeps desktop text sharp. It uses HEVC, and the PC's GPU encoder must support HEVC 4:4:4; if it doesn't, the stream quietly stays at normal color. Full color range sends 0–255 levels for deeper blacks; turn it off if blacks look crushed. Over 150 Mb/s needs a fast, close Wi-Fi 6 or wired PC.")
                    }
                }

                Section {
                    choice("Renderer") {
                        Picker("Renderer", selection: $videoRenderer) {
                            Text("System").tag(0)
                            Text("VideoToolbox").tag(1)
                        }
                    }
                    if videoRenderer == 1 && MNFrameInterpolator.isSupported {
                        Toggle("Frame interpolation (x2)", isOn: $frameInterpolation)
                    }
                } header: {
                    Theme.label("Decoder")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Lowest latency shows every frame as soon as it arrives. Balanced holds one frame back when frames bunch up. Smoothest shows one frame per screen refresh from a queue: each queued frame adds a frame of latency and rides out a Wi-Fi hiccup.")
                        Text("System lets iOS decode inside the video layer. VideoToolbox decodes the frames itself and shows the decode time in the stats. It's new, so switch back to System if the picture breaks up.\(inStream ? " Applies the next time you connect." : "")")
                        if videoRenderer == 1 && MNFrameInterpolator.isSupported {
                            Text("Frame interpolation draws a frame between every two, so a 60 fps stream plays at 120 fps on this screen. It uses more battery and adds about half a frame of latency (8 ms at 60 fps), and only works when the stream's frame rate is at most half the screen's refresh rate.")
                        }
                    }
                }

                Section {
                    choice("Sound") {
                        Picker("Sound", selection: $store.audioConfig) {
                            Text("Stereo").tag(2)
                            Text("5.1").tag(6)
                            Text("7.1").tag(8)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Stream volume")
                            Spacer()
                            Text("\(Int((streamVolume * 100).rounded()))%").foregroundStyle(Theme.muted)
                        }
                        Slider(value: $streamVolume, in: 0...1, step: 0.05)
                            .onChange(of: streamVolume) { MNAudio.reload() }
                    }
                    Toggle("Play audio on PC", isOn: $store.playAudioOnPC)
                    Toggle("Let other apps keep playing", isOn: $mixWithOthers)
                    Toggle("Mute when in background", isOn: $muteInBackground)
                } header: {
                    Theme.label("Audio")
                } footer: {
                    Text("5.1 and 7.1 need a surround setup on the PC; on iOS 18 and later AirPods and other headphones play them as spatial audio. With other apps playing, picture in picture only opens from the ••• menu. Mute applies while the stream stays connected in the background.")
                }

                Section {
                    choice("Touch mode") {
                        Picker("Touch mode", selection: touchModeSelection) {
                            Text("Touchpad").tag(MNTouchMode.touchpad.rawValue)
                            Text("Touchscreen").tag(MNTouchMode.touchscreen.rawValue)
                            Text("Native").tag(MNTouchMode.native.rawValue)
                            Text("Off").tag(MNTouchMode.disabled.rawValue)
                        }
                    }
                    choice("On-screen controls", note: store.absoluteTouchMode ? "Off in touchscreen mode" : nil) {
                        Picker("On-screen controls", selection: $store.onscreenControls) {
                            Text("Off").tag(0)
                            Text("Auto").tag(1)
                            Text("Simple").tag(2)
                            Text("Full").tag(3)
                        }
                        .disabled(store.absoluteTouchMode)
                    }
                    Toggle("Multiple controllers", isOn: $store.multiController)
                    Toggle("Swap A/B and X/Y", isOn: $store.swapABXYButtons)
                    Toggle("Citrix X1 mouse", isOn: $store.btMouseSupport)
                    Toggle("Haptics on button presses", isOn: $hapticsEnabled)
                    Toggle("Highlight pressed buttons", isOn: $pressHighlight)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Trackpad speed")
                            Spacer()
                            Text(String(format: "%.2g×", trackpadSpeed)).foregroundStyle(Theme.muted)
                        }
                        Slider(value: $trackpadSpeed, in: 0.5...5, step: 0.25)
                    }
                } header: {
                    Theme.label("Input")
                } footer: {
                    Text(touchModeFooter)
                }

                Section {
                    if touchModeSelection.wrappedValue == MNTouchMode.touchpad.rawValue {
                        slider("Touchpad pointer speed", value: $touchpadPointerSpeed, in: 0.25...4, step: 0.25)
                        Toggle("Ignore touches at the top edge", isOn: $topDeadZone)
                    }
                    slider("Scroll speed", value: $scrollSpeed, in: 0.25...4, step: 0.25)
                    Toggle("Scroll momentum", isOn: $scrollMomentum)
                    Toggle("Pinch to zoom", isOn: $pinchZoom)
                    Toggle("Reverse scroll direction", isOn: $reverseScroll)
                    choice("Keyboard tap") {
                        Picker("Keyboard tap", selection: $keyboardFingers) {
                            Text("3 fingers").tag(3)
                            Text("4").tag(4)
                            Text("5").tag(5)
                            Text("Off").tag(0)
                        }
                    }
                    choice("Left-edge swipe") {
                        Picker("Left-edge swipe", selection: $edgeSwipe) {
                            Text("Disconnect").tag(MNTouchPrefs.EdgeSwipe.disconnect.rawValue)
                            Text("Stream menu").tag(MNTouchPrefs.EdgeSwipe.menu.rawValue)
                            Text("Off").tag(MNTouchPrefs.EdgeSwipe.off.rawValue)
                        }
                    }
                    choice("Mouse pointer") {
                        Picker("Mouse pointer", selection: $cursorMode) {
                            Text("Captured").tag(MNTouchPrefs.CursorMode.captured.rawValue)
                            Text("Hidden").tag(MNTouchPrefs.CursorMode.hidden.rawValue)
                            Text("Visible").tag(MNTouchPrefs.CursorMode.visible.rawValue)
                        }
                    }
                } header: {
                    Theme.label("Touchpad, keyboard and mouse")
                } footer: {
                    Text("Scrolling and pinch apply to the touchpad mode and the keyboard deck's trackpad: tap, then hold to drag; two fingers scroll; pinch sends Ctrl + wheel to zoom. The keyboard tap opens the on-screen keyboard. A captured mouse moves the host pointer relatively, for games; hidden or visible send the pointer's position, for the desktop. With a hardware keyboard, Ctrl+Alt+Shift with D disconnects, Q quits the app, S opens settings, O shows stats, M frees or captures the mouse and C shows or hides the pointer.\(inStream ? " The mouse pointer setting applies the next time you connect." : "")")
                }

                TouchExtrasSettings()
                ControllerSettingsSections()

                ControllerNavigationSection()

                Section {
                    Toggle("Optimize game settings", isOn: $store.optimizeGames)
                    choice("Stats") {
                        Picker("Stats", selection: Binding(
                            get: { store.statsOverlay ? (statsDetailed ? 2 : 1) : 0 },
                            set: { store.statsOverlay = $0 > 0; if $0 > 0 { statsDetailed = $0 == 2 } })) {
                            Text("Off").tag(0)
                            Text("Simple").tag(1)
                            Text("Detailed").tag(2)
                        }
                    }
                    if AVPictureInPictureController.isPictureInPictureSupported() {
                        Toggle("Picture in picture", isOn: $pictureInPicture)
                    }
                    HStack {
                        Text("Stay connected in background")
                        Spacer()
                        Picker("Stay connected in background", selection: $backgroundMinutes) {
                            Text("Off").tag(0)
                            Text("1 min").tag(1)
                            Text("5 min").tag(5)
                            Text("15 min").tag(15)
                            Text("30 min").tag(30)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    Toggle("Video on external display", isOn: $externalDisplayOnly)
                        .onChange(of: externalDisplayOnly) { MNExternalDisplay.shared.update() }
                } header: {
                    Theme.label("Stream")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if AVPictureInPictureController.isPictureInPictureSupported() {
                            Text("Picture in picture keeps the stream playing in a small window when you leave the app; you can also open it from the ••• menu. Close the window to end the stream.")
                        }
                        Text("Without picture in picture, leaving the app ends the stream unless it stays connected for the time chosen. With a USB-C or AirPlay screen connected, \"Video on external display\" shows the game there while this screen keeps the controls and keyboard; Native resolution then matches that screen.")
                    }
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About MoonLume", systemImage: "info.circle")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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

    private var touchModeFooter: String {
        var text: String
        switch MNTouchMode(rawValue: touchModeSelection.wrappedValue) {
        case .native:
            text = "Native sends every finger to the host as a real touch, for touch games and Windows touch gestures. It needs a Windows or Linux host (Sunshine on macOS has no touch input); elsewhere it works like Touchscreen."
        case .disabled:
            text = "Touches on the stream do nothing, so a palm can't click. On-screen controls and the ••• menu still work, and the menu can turn touch back on."
        default:
            text = "Touch can also be turned off for a moment from the ••• menu."
        }
        if inStream {
            text += " Touch mode applies the next time you connect."
        }
        return text
    }

    /// A labelled slider row with its value as a multiplier.
    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2g×", value.wrappedValue)).foregroundStyle(Theme.muted)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    /// Resolution menu: presets, Native, Safe area (Native clear of the cut-outs) and a typed size.
    private var resolutionRow: some View {
        HStack {
            Text("Resolution")
            Spacer()
            Picker("Resolution", selection: Binding(
                get: {
                    if store.isCustomResolution { return -1 }
                    if store.width == 0 && safeAreaResolution { return -3 }
                    return store.resolutions.firstIndex { $0.width == store.width && $0.height == store.height } ?? -1
                },
                set: { tag in
                    switch tag {
                    case -2:
                        customWidth = store.width > 0 ? String(store.width) : ""
                        customHeight = store.height > 0 ? String(store.height) : ""
                        showCustomResolution = true
                    case -3:
                        safeAreaResolution = true
                        store.setResolution(width: 0, height: 0)
                    case 0..<store.resolutions.count:
                        safeAreaResolution = false
                        let r = store.resolutions[tag]
                        store.setResolution(width: r.width, height: r.height)
                    default:
                        break
                    }
                })) {
                ForEach(store.resolutions.indices, id: \.self) { Text(store.resolutions[$0].label).tag($0) }
                Text("Safe area").tag(-3)
                if store.isCustomResolution {
                    Text("\(store.width)×\(store.height)").tag(-1)
                }
                Text("Custom…").tag(-2)
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .alert("Custom resolution", isPresented: $showCustomResolution) {
            TextField("Width", text: $customWidth).keyboardType(.numberPad)
            TextField("Height", text: $customHeight).keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Set") {
                if let w = Int(customWidth), let h = Int(customHeight) {
                    safeAreaResolution = false
                    store.setCustomResolution(width: w, height: h)
                }
            }
        } message: {
            Text("Width and height in pixels. Above 4096 needs HEVC.")
        }
    }

    /// A labelled segmented control row.
    private func choice<P: View>(_ title: String, note: String? = nil, @ViewBuilder picker: () -> P) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                if let note {
                    Text(note).font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
            }
            picker().pickerStyle(.segmented).labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

/// Settings over a running stream, from the stream menu (StreamFrameViewController is ObjC).
@objc final class MNSettingsSheet: NSObject {
    @objc static func makeViewController(onClose: @escaping () -> Void) -> UIViewController {
        UIHostingController(rootView: SettingsView(inStream: true).onDisappear(perform: onClose))
    }
}
