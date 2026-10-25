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
        Section {
            Toggle("Two fingers scroll and right-click", isOn: $twoFinger)
            Toggle("Click when the finger lifts", isOn: $clickOnLift)
            if clickOnLift {
                row("Rest before a drag", value: String(format: "%.2f s", dragHold)) {
                    Slider(value: $dragHold, in: 0.05...0.5, step: 0.05)
                }
            }
            row("Native: right-side swipe speed", value: nativeSpeed == 1 ? "Off" : String(format: "%.2g×", nativeSpeed)) {
                Slider(value: $nativeSpeed, in: 0.5...4, step: 0.25)
            }
            if nativeSpeed != 1 {
                row("Fast side starts at", value: "\(Int((nativeSplit * 100).rounded()))% across") {
                    Slider(value: $nativeSplit, in: 0.2...0.8, step: 0.05)
                }
            }
        } header: {
            Theme.label("Touchscreen and native touch")
        } footer: {
            Text("In Touchscreen mode, two fingers scroll, pinch to zoom and tap for a right click. Click when the finger lifts: a tap clicks, a finger that rests a moment and then moves drags, and one that moves straight away only moves the pointer, so swiping doesn't click. In Native mode, fingers that land on the right side can move the host's touch faster than they travel, for camera swipes in touch games; at the screen edge the touch lifts and lands again where it started. Applies the next time you connect.")
        }

        Section {
            NavigationLink {
                KeyBarKeysView()
            } label: {
                Text("Keys above the keyboard")
            }
            row("Keyboard height", value: keyboardHeight == 0 ? "Auto" : "\(Int((keyboardHeight * 100).rounded()))% of screen") {
                Slider(value: $keyboardHeight, in: 0...0.7, step: 0.05)
            }
            Toggle("Globe key sends Escape", isOn: $globeEscape)
        } header: {
            Theme.label("Soft keyboard")
        } footer: {
            Text("The key row sits above the on-screen keyboard; Ctrl, Alt, Shift and Win stay held until tapped again, so Ctrl then C sends Ctrl+C. Set a keyboard height if the stream lifts too far or not enough when the keyboard opens (some floating and third-party keyboards report the wrong size). With Globe as Escape off, a hardware keyboard's Globe key switches language as usual.")
        }

        Section {
            Toggle("Send dummy input", isOn: $dummyInput)
        } header: {
            Theme.label("Stutter workaround")
        } footer: {
            Text("Some phones and routers let Wi-Fi doze between packets while you aren't touching anything, which shows up as stutter that goes away while a finger moves. This sends a harmless, empty key release to the host every frame to keep the connection awake. Leave it off unless you see that pattern; it uses a little more battery. Applies the next time you connect.")
        }
    }

    private func row<S: View>(_ title: String, value: String, @ViewBuilder slider: () -> S) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(value).foregroundStyle(Theme.muted)
            }
            slider()
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
