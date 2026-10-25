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
                            100000, 120000, 150000]

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
    private let audioConfig: Int

    let hevcSupported = MNBridge.hevcSupported()
    let av1Supported = MNBridge.av1Supported()
    let hdrSupported = MNBridge.hdrSupported()
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    choice("Resolution", note: store.isCustomResolution ? "Custom \(store.width)×\(store.height)" : (store.width == 0 ? "Fits the screen you stream on" : nil)) {
                        Picker("Resolution", selection: Binding(
                            get: { store.isCustomResolution ? -1 : store.resolutions.firstIndex { $0.width == store.width && $0.height == store.height } ?? -1 },
                            set: { let r = store.resolutions[$0]; store.setResolution(width: r.width, height: r.height) })) {
                            ForEach(store.resolutions.indices, id: \.self) { Text(store.resolutions[$0].label).tag($0) }
                        }
                    }
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
                    choice("Frame pacing") {
                        Picker("Frame pacing", selection: $store.useFramePacing) {
                            Text("Lowest latency").tag(false)
                            Text("Smoothest video").tag(true)
                        }
                    }
                } header: {
                    Theme.label("Video")
                } footer: {
                    if inStream {
                        Text("Video changes apply the next time you connect. Controls, gyro, haptics and trackpad speed apply now.")
                    }
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

                ControllerSettingsSections()

                Section {
                    Toggle("Optimize game settings", isOn: $store.optimizeGames)
                    Toggle("Play audio on PC", isOn: $store.playAudioOnPC)
                    Toggle("Stats overlay", isOn: $store.statsOverlay)
                    if AVPictureInPictureController.isPictureInPictureSupported() {
                        Toggle("Picture in picture", isOn: $pictureInPicture)
                    }
                } header: {
                    Theme.label("Stream")
                } footer: {
                    if AVPictureInPictureController.isPictureInPictureSupported() {
                        Text("Picture in picture keeps the stream playing in a small window when you leave the app. Close the window to end the stream. With it on, the stream pauses music from other apps.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
