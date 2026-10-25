//
//  TouchExtrasSettings.swift
//  MoonLume
//
//  Settings › Touchscreen and native touch, Soft keyboard, and the dummy-input workaround
//  (MNTouchExtras in TouchExtras.swift holds the keys and what they mean).
//

import SwiftUI

struct TouchExtrasSettings: View {
    @AppStorage(MNTouchExtras.twoFingerKey) private var twoFinger = true
    @AppStorage(MNTouchExtras.clickOnLiftKey) private var clickOnLift = false
    @AppStorage(MNTouchExtras.dragHoldKey) private var dragHold = 0.1
    @AppStorage(MNTouchExtras.nativeSpeedKey) private var nativeSpeed = 1.0
    @AppStorage(MNTouchExtras.nativeSplitKey) private var nativeSplit = 0.5
    @AppStorage(MNTouchExtras.keyboardHeightKey) private var keyboardHeight = 0.0
    @AppStorage(MNTouchExtras.globeEscapeKey) private var globeEscape = true
    @AppStorage(MNTouchExtras.dummyInputKey) private var dummyInput = false

    var body: some View {
        SettingsSection("Touchscreen and native touch", id: "touchExtras") {
            SettingToggle("Two fingers scroll and right-click", id: MNTouchExtras.twoFingerKey, isOn: $twoFinger,
                          tip: "In Touchscreen mode, two fingers scroll, pinch to zoom and tap for a right click.")
            SettingToggle("Click when the finger lifts", id: MNTouchExtras.clickOnLiftKey, isOn: $clickOnLift,
                          tip: "In Touchscreen mode, a tap clicks, a finger that rests a moment and then moves drags, and one that moves straight away only moves the pointer, so swiping doesn't click.")
            if clickOnLift {
                SettingSlider("Rest before a drag", id: MNTouchExtras.dragHoldKey, value: $dragHold, in: 0.05...0.5,
                              step: 0.05, format: "%.2f s")
            }
            row("Native: right-side swipe speed", id: MNTouchExtras.nativeSpeedKey,
                value: nativeSpeed == 1 ? "Off" : String(format: "%.2g×", nativeSpeed),
                tip: "In Native mode, fingers that land on the right side move the host's touch faster than they travel, for camera swipes in touch games. At the screen edge the touch lifts and lands again where it started.") {
                Slider(value: $nativeSpeed, in: 0.5...4, step: 0.25)
            }
            if nativeSpeed != 1 {
                SettingSlider("Fast side starts at", id: MNTouchExtras.nativeSplitKey, value: $nativeSplit, in: 0.2...0.8,
                              step: 0.05, format: "%.0f%% across", scale: 100)
            }
        } footer: {
            Text("Applies the next time you connect.")
        }

        SettingsSection("Soft keyboard", id: "softKeyboard") {
            SettingRow("Keys above the keyboard", id: MNTouchExtras.keyBarKey,
                       tip: "The key row sits above the on-screen keyboard. Ctrl, Alt, Shift and Win stay held until tapped again, so Ctrl then C sends Ctrl+C.") { label in
                NavigationLink {
                    KeyBarKeysView()
                } label: {
                    label
                }
            }
            row("Keyboard height", id: MNTouchExtras.keyboardHeightKey,
                value: keyboardHeight == 0 ? "Auto" : "\(Int((keyboardHeight * 100).rounded()))% of screen",
                tip: "Set a height if the stream lifts too far or not enough when the keyboard opens. Some floating and third-party keyboards report the wrong size.") {
                Slider(value: $keyboardHeight, in: 0...0.7, step: 0.05)
            }
            SettingToggle("Globe key sends Escape", id: MNTouchExtras.globeEscapeKey, isOn: $globeEscape,
                          tip: "When off, a hardware keyboard's Globe key switches language as usual.")
        }

        SettingsSection("Stutter workaround", id: "stutterWorkaround") {
            SettingToggle("Send dummy input", id: MNTouchExtras.dummyInputKey, isOn: $dummyInput,
                          tip: "Some phones and routers let Wi-Fi doze between packets while you aren't touching anything, which shows up as stutter that goes away while a finger moves. This sends a harmless, empty key release to the host every frame to keep the connection awake. It uses a little more battery.")
        } footer: {
            Text("Leave it off unless you see stutter that stops while a finger moves. Applies the next time you connect.")
        }
    }

    private func row<S: View>(_ title: String, id: String, value: String, tip: String? = nil,
                              @ViewBuilder slider: @escaping () -> S) -> some View {
        SettingRow(title, id: id, tip: tip) { label in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    label
                    Spacer()
                    Text(value).foregroundStyle(Theme.muted)
                }
                slider()
            }
        }
    }
}

/// Which keys the row above the soft keyboard shows.
private struct KeyBarKeysView: View {
    @AppStorage(MNTouchExtras.keyBarKey) private var keys = MNTouchExtras.keyBarDefault

    var body: some View {
        Form {
            Section {
                ForEach(MNTouchExtras.keyBarChoices, id: \.self) { vk in
                    Toggle(WidgetCatalog.keyName(vk), isOn: Binding(
                        get: { chosen.contains(vk) },
                        set: { on in
                            var set = chosen
                            if on { set.insert(vk) } else { set.remove(vk) }
                            keys = MNTouchExtras.keyBarChoices.filter(set.contains).map(String.init).joined(separator: ",")
                        }))
                }
            } footer: {
                Text("Shown left to right in this order. Takes effect the next time the keyboard opens.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
        .navigationTitle("Keyboard keys")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chosen: Set<Int> {
        Set(keys.split(separator: ",").compactMap { Int($0) })
    }
}
