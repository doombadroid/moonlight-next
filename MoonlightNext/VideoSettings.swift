//
//  VideoSettings.swift
//  MoonLume
//
//  Settings › Video and Decoder.
//

import SwiftUI

struct VideoSettings: View {
    @ObservedObject var store: SettingsStore
    var inStream = false

    @AppStorage("mnResolutionSafeArea") private var safeAreaResolution = false
    @AppStorage("mnYUV444") private var yuv444 = false
    @AppStorage("mnFullColorRange") private var fullColorRange = false
    // Unset until chosen: then the old on/off pacing setting decides (on = Balanced)
    @AppStorage("mnFramePacingMode") private var framePacingMode: Int?
    @AppStorage("mnFrameQueueDepth") private var frameQueueDepth = 2
    @AppStorage("mnVideoRenderer") private var videoRenderer = 0
    @AppStorage("mnFrameInterpolation") private var frameInterpolation = false
    @SwiftUI.State private var showCustomResolution = false
    @SwiftUI.State private var customWidth = ""
    @SwiftUI.State private var customHeight = ""

    var body: some View {
        SettingsSection("Video", id: "video") {
            resolutionRow
            SettingChoice("Frame rate", id: "framerate") {
                Picker("Frame rate", selection: Binding(get: { store.framerate }, set: { store.setFramerate($0) })) {
                    Text("30").tag(30)
                    Text("60").tag(60)
                    if store.supports120 { Text("120").tag(120) }
                }
            }
            SettingRow("Bitrate", id: "bitrate",
                       tip: "Higher looks sharper but needs a faster network. Changing the resolution or frame rate resets it to a suggested value. Over 150 Mb/s needs a fast, close Wi-Fi 6 or wired PC.") { label in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        label
                        Spacer()
                        Text(String(format: "%.1f Mb/s", Double(store.bitrateKbps) / 1000))
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }
                    Slider(value: $store.bitrateIndex, in: 0...Double(bitrateTable.count - 1), step: 1)
                        .accessibilityValue(String(format: "%.1f megabits per second", Double(store.bitrateKbps) / 1000))
                }
                .padding(.vertical, 4)
            }
            SettingChoice("Codec", id: "codec",
                          tip: "Auto picks the best codec both the PC and this phone support. HEVC and AV1 look better at the same bitrate; AV1 needs a recent GPU in the PC.") {
                Picker("Codec", selection: $store.codec) {
                    ForEach(store.codecs, id: \.self) { Text($0.label).tag($0.rawValue) }
                }
            }
            if store.hdrSupported {
                SettingToggle("HDR", id: "enableHdr", isOn: $store.enableHdr,
                              tip: "Needs HDR turned on in the PC's display settings, and a game or desktop in HDR.")
            }
            if store.yuv444Supported && [StreamCodec.auto.rawValue, StreamCodec.hevc.rawValue].contains(store.codec) {
                SettingToggle("Full color (4:4:4)", id: "mnYUV444", isOn: $yuv444,
                              tip: "Keeps desktop text sharp. It uses HEVC, and the PC's GPU encoder must support HEVC 4:4:4; if it doesn't, the stream quietly stays at normal color.")
            }
            SettingToggle("Full color range", id: "mnFullColorRange", isOn: $fullColorRange,
                          tip: "Sends 0–255 levels for deeper blacks. Turn it off if blacks look crushed.")
            SettingChoice("Frame pacing", id: "mnFramePacingMode",
                          tip: "Lowest latency shows every frame as soon as it arrives. Balanced holds one frame back when frames bunch up. Smoothest shows one frame per screen refresh from a queue: each queued frame adds a frame of latency and rides out a Wi-Fi hiccup.") {
                Picker("Frame pacing", selection: Binding(
                    get: { framePacingMode ?? (store.useFramePacing ? 1 : 0) },
                    set: { framePacingMode = $0; store.useFramePacing = $0 != 0 })) {
                    Text("Lowest latency").tag(0)
                    Text("Balanced").tag(1)
                    Text("Smoothest").tag(2)
                }
            }
            if framePacingMode == 2 {
                SettingChoice("Frames queued", id: "mnFrameQueueDepth") {
                    Picker("Frames queued", selection: $frameQueueDepth) {
                        ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
                    }
                }
            }
        } footer: {
            if inStream {
                Text("Video, sound channels and resolution apply the next time you connect. Controls, gyro, haptics, volume and trackpad speed apply now.")
            }
        }

        SettingsSection("Decoder", id: "decoder") {
            SettingChoice("Renderer", id: "mnVideoRenderer",
                          tip: "System lets iOS decode inside the video layer. VideoToolbox decodes the frames itself and shows the decode time in the stats. It's new, so switch back to System if the picture breaks up.") {
                Picker("Renderer", selection: $videoRenderer) {
                    Text("System").tag(0)
                    Text("VideoToolbox").tag(1)
                }
            }
            if videoRenderer == 1 && MNFrameInterpolator.isSupported {
                SettingToggle("Frame interpolation (x2)", id: "mnFrameInterpolation", isOn: $frameInterpolation,
                              tip: "Draws a frame between every two, so a 60 fps stream plays at 120 fps on this screen. It uses more battery and adds about half a frame of latency (8 ms at 60 fps), and only works when the stream's frame rate is at most half the screen's refresh rate.")
            }
        } footer: {
            if inStream {
                Text("The renderer applies the next time you connect.")
            }
        }
    }

    /// Resolution menu: presets, Native, Safe area (Native clear of the cut-outs) and a typed size.
    private var resolutionRow: some View {
        SettingRow("Resolution", id: "resolution",
                   tip: "Native matches the screen the video plays on. Safe area is Native without the camera cut-out and rounded corners. Custom takes any size; above 4096 needs HEVC.") { label in
            HStack {
                label
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
    }
}
