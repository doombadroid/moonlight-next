//
//  StreamSettings.swift
//  MoonLume
//
//  Settings › Audio and Stream.
//

import AVKit
import SwiftUI

struct AudioSettings: View {
    @ObservedObject var store: SettingsStore

    @AppStorage(MNAudio.volumeKey) private var streamVolume = 1.0
    @AppStorage(MNAudio.mixKey) private var mixWithOthers = MNAudio.mixWithOthers
    @AppStorage(MNAudio.muteInBackgroundKey) private var muteInBackground = false

    var body: some View {
        SettingsSection("Audio", id: "audio") {
            SettingChoice("Sound", id: "audioConfig",
                          tip: "5.1 and 7.1 need a surround setup on the PC. On iOS 18 and later, AirPods and other headphones play them as spatial audio.") {
                Picker("Sound", selection: $store.audioConfig) {
                    Text("Stereo").tag(2)
                    Text("5.1").tag(6)
                    Text("7.1").tag(8)
                }
            }
            SettingSlider("Stream volume", id: MNAudio.volumeKey,
                          value: Binding(get: { streamVolume }, set: { streamVolume = $0; MNAudio.reload() }),
                          in: 0...1, step: 0.05, format: "%.0f%%", scale: 100)
            SettingToggle("Play audio on PC", id: "playAudioOnPC", isOn: $store.playAudioOnPC)
            SettingToggle("Let other apps keep playing", id: MNAudio.mixKey, isOn: $mixWithOthers,
                          tip: "Mixes the stream with music or other apps' sound. While other apps play, picture in picture only opens from the ••• menu.")
            SettingToggle("Mute when in background", id: MNAudio.muteInBackgroundKey, isOn: $muteInBackground,
                          tip: "Applies while the stream stays connected in the background.")
        }
    }
}

struct StreamSettings: View {
    @ObservedObject var store: SettingsStore

    @AppStorage("mnStatsDetailed") private var statsDetailed = true
    @AppStorage("mnPictureInPicture") private var pictureInPicture = true
    @AppStorage(MNAudio.backgroundMinutesKey) private var backgroundMinutes = 0
    @AppStorage(MNExternalDisplay.enabledKey) private var externalDisplayOnly = false

    var body: some View {
        SettingsSection("Stream", id: "stream") {
            SettingToggle("Optimize game settings", id: "optimizeGames", isOn: $store.optimizeGames,
                          tip: "Lets the host change the game's settings to suit the stream, on hosts that support it.")
            SettingChoice("Stats", id: "statsOverlay") {
                Picker("Stats", selection: Binding(
                    get: { store.statsOverlay ? (statsDetailed ? 2 : 1) : 0 },
                    set: { store.statsOverlay = $0 > 0; if $0 > 0 { statsDetailed = $0 == 2 } })) {
                    Text("Off").tag(0)
                    Text("Simple").tag(1)
                    Text("Detailed").tag(2)
                }
            }
            if AVPictureInPictureController.isPictureInPictureSupported() {
                SettingToggle("Picture in picture", id: "mnPictureInPicture", isOn: $pictureInPicture,
                              tip: "Keeps the stream playing in a small window when you leave the app; you can also open it from the ••• menu. Close the window to end the stream.")
            }
            SettingRow("Stay connected in background", id: MNAudio.backgroundMinutesKey,
                       tip: "Without picture in picture, leaving the app ends the stream unless it stays connected for the time chosen.") { label in
                HStack {
                    label
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
            }
            SettingToggle("Video on external display", id: MNExternalDisplay.enabledKey,
                          isOn: Binding(get: { externalDisplayOnly }, set: { externalDisplayOnly = $0; MNExternalDisplay.shared.update() }),
                          tip: "With a USB-C or AirPlay screen connected, the game shows there while this screen keeps the controls and keyboard. Native resolution then matches that screen.")
        }
    }
}
