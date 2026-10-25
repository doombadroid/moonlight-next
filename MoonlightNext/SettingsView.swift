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
    @AppStorage("mnTrackpadSpeed") private var trackpadSpeed = 2.0
    @AppStorage("mnPhoneRumble") private var phoneRumble = true
    @AppStorage("mnPictureInPicture") private var pictureInPicture = true
    @AppStorage(GyroSettings.modeKey) private var gyroMode = GyroSettings.Mode.off.rawValue
    @AppStorage(GyroSettings.activationKey) private var gyroActivation = GyroSettings.Activation.always.rawValue
    @AppStorage(GyroSettings.sensitivityKey) private var gyroSensitivity = 1.5
    @AppStorage(GyroSettings.invertYKey) private var gyroInvertY = false

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
                        Picker("Touch mode", selection: $store.absoluteTouchMode) {
                            Text("Touchpad").tag(false)
                            Text("Touchscreen").tag(true)
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
                    Toggle("Phone rumble without a controller", isOn: $phoneRumble)
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
                }

                Section {
                    choice("Gyro aiming") {
                        Picker("Gyro aiming", selection: $gyroMode) {
                            Text("Off").tag(GyroSettings.Mode.off.rawValue)
                            Text("Mouse").tag(GyroSettings.Mode.mouse.rawValue)
                            Text("Right stick").tag(GyroSettings.Mode.rightStick.rawValue)
                        }
                    }
                    if gyroMode != GyroSettings.Mode.off.rawValue {
                        choice("Active") {
                            Picker("Active", selection: $gyroActivation) {
                                Text("Always").tag(GyroSettings.Activation.always.rawValue)
                                Text("While L2 is held").tag(GyroSettings.Activation.whileAiming.rawValue)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Sensitivity")
                                Spacer()
                                Text(String(format: "%.2g×", gyroSensitivity)).foregroundStyle(Theme.muted)
                            }
                            Slider(value: $gyroSensitivity, in: 0.25...4, step: 0.25)
                        }
                        Toggle("Invert up/down", isOn: $gyroInvertY)
                    }
                } header: {
                    Theme.label("Gyro")
                } footer: {
                    Text("Turn the phone to aim. Mouse suits most PC games and the desktop; right stick suits games that only take a controller. Pause it from the ••• menu while streaming.")
                }

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
