//
//  InputSettings.swift
//  MoonLume
//
//  Settings › Input, and Touchpad, keyboard and mouse.
//

import SwiftUI

struct InputSettings: View {
    @ObservedObject var store: SettingsStore
    var inStream = false

    /// Read by the input deck and the on-screen controls on every press.
    @AppStorage("mnHapticsEnabled") private var hapticsEnabled = true
    @AppStorage("mnOSCPressHighlight") private var pressHighlight = true
    @AppStorage("mnTrackpadSpeed") private var trackpadSpeed = 2.0
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
        SettingsSection("Input", id: "input") {
            SettingChoice("Touch mode", id: MNTouchPrefs.touchModeKey,
                          tip: "Touchpad moves the PC's pointer like a laptop trackpad. Touchscreen clicks where you touch. Native passes every finger to the host as a real touch. Off ignores touches on the stream.") {
                Picker("Touch mode", selection: touchModeSelection) {
                    Text("Touchpad").tag(MNTouchMode.touchpad.rawValue)
                    Text("Touchscreen").tag(MNTouchMode.touchscreen.rawValue)
                    Text("Native").tag(MNTouchMode.native.rawValue)
                    Text("Off").tag(MNTouchMode.disabled.rawValue)
                }
            }
            SettingChoice("On-screen controls", id: "onscreenControls", note: store.absoluteTouchMode ? "Off in touchscreen mode" : nil,
                          tip: "A virtual gamepad over the stream. Auto shows all of it while no controller is connected, and only the buttons a connected controller lacks.") {
                Picker("On-screen controls", selection: $store.onscreenControls) {
                    Text("Off").tag(0)
                    Text("Auto").tag(1)
                    Text("Simple").tag(2)
                    Text("Full").tag(3)
                }
                .disabled(store.absoluteTouchMode)
            }
            SettingToggle("Multiple controllers", id: "multiController", isOn: $store.multiController,
                          tip: "Each controller is its own player. Off makes every controller player 1.")
            SettingToggle("Swap A/B and X/Y", id: "swapABXYButtons", isOn: $store.swapABXYButtons)
            SettingToggle("Citrix X1 mouse", id: "btMouseSupport", isOn: $store.btMouseSupport,
                          tip: "Support for the Citrix X1 Bluetooth mouse.")
            SettingToggle("Haptics on button presses", id: "mnHapticsEnabled", isOn: $hapticsEnabled)
            SettingToggle("Highlight pressed buttons", id: "mnOSCPressHighlight", isOn: $pressHighlight)
            SettingSlider("Trackpad speed", id: "mnTrackpadSpeed", value: $trackpadSpeed, in: 0.5...5)
        } footer: {
            Text(touchModeFooter)
        }

        SettingsSection("Touchpad, keyboard and mouse", id: "touchpad") {
            if touchModeSelection.wrappedValue == MNTouchMode.touchpad.rawValue {
                SettingSlider("Touchpad pointer speed", id: MNTouchPrefs.pointerSpeedKey, value: $touchpadPointerSpeed, in: 0.25...4)
                SettingToggle("Ignore touches at the top edge", id: MNTouchPrefs.topDeadZoneKey, isOn: $topDeadZone)
            }
            SettingSlider("Scroll speed", id: MNTouchPrefs.scrollSpeedKey, value: $scrollSpeed, in: 0.25...4)
            SettingToggle("Scroll momentum", id: MNTouchPrefs.momentumKey, isOn: $scrollMomentum)
            SettingToggle("Pinch to zoom", id: MNTouchPrefs.pinchZoomKey, isOn: $pinchZoom,
                          tip: "Pinch sends Ctrl + mouse wheel, which zooms in most desktop apps and browsers.")
            SettingToggle("Reverse scroll direction", id: MNTouchPrefs.reverseScrollKey, isOn: $reverseScroll)
            SettingChoice("Keyboard tap", id: MNTouchPrefs.keyboardFingersKey,
                          tip: "Tap the stream with this many fingers to open the on-screen keyboard.") {
                Picker("Keyboard tap", selection: $keyboardFingers) {
                    Text("3 fingers").tag(3)
                    Text("4").tag(4)
                    Text("5").tag(5)
                    Text("Off").tag(0)
                }
            }
            SettingChoice("Left-edge swipe", id: MNTouchPrefs.edgeSwipeKey) {
                Picker("Left-edge swipe", selection: $edgeSwipe) {
                    Text("Disconnect").tag(MNTouchPrefs.EdgeSwipe.disconnect.rawValue)
                    Text("Stream menu").tag(MNTouchPrefs.EdgeSwipe.menu.rawValue)
                    Text("Off").tag(MNTouchPrefs.EdgeSwipe.off.rawValue)
                }
            }
            SettingChoice("Mouse pointer", id: MNTouchPrefs.cursorModeKey,
                          tip: "A captured mouse moves the PC's pointer relatively, for games. Hidden and Visible send the pointer's position, for the desktop.\(inStream ? " Applies the next time you connect." : "")") {
                Picker("Mouse pointer", selection: $cursorMode) {
                    Text("Captured").tag(MNTouchPrefs.CursorMode.captured.rawValue)
                    Text("Hidden").tag(MNTouchPrefs.CursorMode.hidden.rawValue)
                    Text("Visible").tag(MNTouchPrefs.CursorMode.visible.rawValue)
                }
            }
        } footer: {
            Text("Scrolling and pinch apply to the touchpad mode and the keyboard deck's trackpad: tap, then hold to drag; two fingers scroll. With a hardware keyboard, Ctrl+Alt+Shift with D disconnects, Q quits the app, S opens settings, O shows stats, M frees or captures the mouse and C shows or hides the pointer.")
        }
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
}
