//
//  ControllerSettings.swift
//  MoonLume
//
//  Controller, gyro and controller-mouse settings: the preferences ControllerSupport reads when
//  it reports player 1 to the host, and their Settings sections.
//

import SwiftUI

/// What player 1 (the phone, plus any physical pad merged with it) looks like to the host.
@objc final class MNControllerPrefs: NSObject {
    enum Emulated: Int { case automatic = 0, xbox = 1, playStation = 2 }
    enum Motion: Int { case automatic = 0, phone = 1, controller = 2, off = 3 }

    static let emulatedKey = "mnEmulatedController"
    static let motionKey = "mnMotionSource"

    static var emulated: Emulated { Emulated(rawValue: UserDefaults.standard.integer(forKey: emulatedKey)) ?? .automatic }
    static var motion: Motion { Motion(rawValue: UserDefaults.standard.integer(forKey: motionKey)) ?? .automatic }

    // LI_CTYPE_XBOX, LI_CTYPE_PS
    private static let typeXbox: UInt8 = 0x01
    private static let typePlayStation: UInt8 = 0x02

    /// Motion › Off: no motion reaches the host, from the phone or a controller.
    @objc static var motionOff: Bool { motion == .off }

    /// Automatic keeps what ControllerSupport detected (a physical pad's own type, Xbox for the
    /// on-screen controls).
    @objc(reportedType:) static func reportedType(_ detected: UInt8) -> UInt8 {
        switch emulated {
        case .automatic: return detected
        case .xbox: return typeXbox
        case .playStation: return typePlayStation
        }
    }

    /// Only a PlayStation pad has motion sensors on the host (a virtual DualShock 4 or DualSense).
    @objc(usesPhoneMotionForType:padHasGyro:) static func usesPhoneMotion(type: UInt8, padHasGyro: Bool) -> Bool {
        guard type == typePlayStation else { return false }
        switch motion {
        case .phone: return true
        case .automatic: return !padHasGyro
        case .controller, .off: return false
        }
    }
}

/// Settings › Controller, Gyro and Controller mouse.
struct ControllerSettingsSections: View {
    @AppStorage(MNControllerPrefs.emulatedKey) private var emulated = MNControllerPrefs.Emulated.automatic.rawValue
    @AppStorage(MNControllerPrefs.motionKey) private var motionSource = MNControllerPrefs.Motion.automatic.rawValue
    @AppStorage(MNRumble.targetKey) private var rumbleTarget = MNRumble.Target.automatic.rawValue
    @AppStorage(MNRumble.phoneFallbackKey) private var phoneRumble = true
    @AppStorage(MNRumble.swapKey) private var swapMotors = false
    @AppStorage(MNAdaptiveTriggers.enabledKey) private var adaptiveTriggers = true

    @AppStorage(GyroSettings.modeKey) private var gyroMode = GyroSettings.Mode.off.rawValue
    @AppStorage(GyroSettings.sourceKey) private var gyroSource = GyroSettings.Source.phone.rawValue
    @AppStorage(GyroSettings.activationKey) private var gyroActivation = GyroSettings.Activation.always.rawValue
    @AppStorage(GyroSettings.buttonKey) private var gyroButton = GyroSettings.Button.none.rawValue
    @AppStorage(GyroSettings.buttonModeKey) private var gyroButtonMode = GyroSettings.ButtonMode.hold.rawValue
    @AppStorage(GyroSettings.sensitivityKey) private var gyroSensitivity = 1.5
    @AppStorage(GyroSettings.sensitivityXKey) private var gyroSensitivityX = 1.0
    @AppStorage(GyroSettings.sensitivityYKey) private var gyroSensitivityY = 1.0
    @AppStorage(GyroSettings.invertYKey) private var gyroInvertY = false
    @AppStorage(GyroSettings.minStickKey) private var gyroMinStick = 0.0
    @AppStorage(GyroSettings.steeringKey) private var steering = false
    @AppStorage(GyroSettings.steeringSensitivityKey) private var steeringSensitivity = 1.0

    @AppStorage(ControllerMouseSettings.chordKey) private var mouseChord = true
    @AppStorage(ControllerMouseSettings.leftStickKey) private var mouseLeftStick = false
    @AppStorage(ControllerMouseSettings.clicksKey) private var mouseClicks = ControllerMouseSettings.Clicks.faceButtons.rawValue
    @AppStorage(ControllerMouseSettings.speedKey) private var mouseSpeed = 1.0

    @State private var calibration: String?

    var body: some View {
        Section {
            choice("Emulated controller") {
                Picker("Emulated controller", selection: $emulated) {
                    Text("Automatic").tag(MNControllerPrefs.Emulated.automatic.rawValue)
                    Text("Xbox").tag(MNControllerPrefs.Emulated.xbox.rawValue)
                    Text("PlayStation").tag(MNControllerPrefs.Emulated.playStation.rawValue)
                }
            }
            choice("Motion sensors", note: emulated == MNControllerPrefs.Emulated.xbox.rawValue ? "Needs PlayStation" : nil) {
                Picker("Motion sensors", selection: $motionSource) {
                    Text("Auto").tag(MNControllerPrefs.Motion.automatic.rawValue)
                    Text("Phone").tag(MNControllerPrefs.Motion.phone.rawValue)
                    Text("Controller").tag(MNControllerPrefs.Motion.controller.rawValue)
                    Text("Off").tag(MNControllerPrefs.Motion.off.rawValue)
                }
            }
            choice("Rumble") {
                Picker("Rumble", selection: $rumbleTarget) {
                    Text("Auto").tag(MNRumble.Target.automatic.rawValue)
                    Text("Phone").tag(MNRumble.Target.phone.rawValue)
                    Text("Off").tag(MNRumble.Target.off.rawValue)
                }
            }
            if rumbleTarget == MNRumble.Target.automatic.rawValue {
                Toggle("Phone rumble without a controller", isOn: $phoneRumble)
            }
            Toggle("Swap rumble motors", isOn: $swapMotors)
            Toggle("DualSense adaptive triggers", isOn: $adaptiveTriggers)
        } header: {
            Theme.label("Controller")
        } footer: {
            Text("PlayStation makes the host create a DualShock or DualSense, so games and Steam Input can use the phone's motion sensors as the pad's gyro (Auto uses a connected controller's own gyro when it has one). It needs a Windows or Linux host: Sunshine on macOS has no virtual controller. Adaptive triggers reach a real DualSense only when the host emulates one, in practice Sunshine on Linux. Controller type and motion apply the next time you connect.")
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
                choice("Aim with") {
                    Picker("Aim with", selection: $gyroSource) {
                        Text("Phone").tag(GyroSettings.Source.phone.rawValue)
                        Text("Controller's gyro").tag(GyroSettings.Source.controller.rawValue)
                    }
                }
                choice("Active") {
                    Picker("Active", selection: $gyroActivation) {
                        Text("Always").tag(GyroSettings.Activation.always.rawValue)
                        Text("While L2 is held").tag(GyroSettings.Activation.whileAiming.rawValue)
                    }
                }
                Picker("Gyro button", selection: $gyroButton) {
                    ForEach(GyroSettings.Button.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
                if gyroButton != GyroSettings.Button.none.rawValue {
                    choice("Button") {
                        Picker("Button", selection: $gyroButtonMode) {
                            Text("Hold to aim").tag(GyroSettings.ButtonMode.hold.rawValue)
                            Text("Toggle").tag(GyroSettings.ButtonMode.toggle.rawValue)
                            Text("Hold to pause").tag(GyroSettings.ButtonMode.holdToPause.rawValue)
                        }
                    }
                }
                slider("Sensitivity", value: $gyroSensitivity, in: 0.25...4)
                slider("Horizontal", value: $gyroSensitivityX, in: 0.25...2)
                slider("Vertical", value: $gyroSensitivityY, in: 0.25...2)
                Toggle("Invert up/down", isOn: $gyroInvertY)
            }
            Toggle("Tilt to steer", isOn: $steering)
            if steering {
                slider("Steering sensitivity", value: $steeringSensitivity, in: 0.5...3)
            }
            if steering || gyroMode == GyroSettings.Mode.rightStick.rawValue {
                slider("Minimum stick offset", value: $gyroMinStick, in: 0...0.4, step: 0.05, format: "%.0f%%", scale: 100)
            }
            Button {
                calibration = "Keep still…"
                MNGyro.shared.calibrate { ok in
                    calibration = ok ? "Calibrated" : "It moved. Lay it down and try again."
                }
            } label: {
                HStack {
                    Text("Calibrate drift")
                    Spacer()
                    if let calibration { Text(calibration).font(.system(size: 13)).foregroundStyle(Theme.muted) }
                }
            }
        } header: {
            Theme.label("Gyro")
        } footer: {
            Text("Turn the phone, or the controller's gyro, to aim. Mouse suits most PC games and the desktop; right stick suits games that only take a controller. The gyro button is on a physical controller and still reaches the game. Tilt to steer turns the phone's roll, like a wheel, into the left stick. Minimum stick offset gets small movements past a game's stick deadzone. For Calibrate drift, lay the phone and controller down for two seconds. Pause gyro from the ••• menu while streaming.")
        }

        Section {
            Toggle("Select + R3 toggles it", isOn: $mouseChord)
            choice("Pointer stick") {
                Picker("Pointer stick", selection: $mouseLeftStick) {
                    Text("Right").tag(false)
                    Text("Left").tag(true)
                }
            }
            choice("Left / right click") {
                Picker("Left / right click", selection: $mouseClicks) {
                    Text("A / B").tag(ControllerMouseSettings.Clicks.faceButtons.rawValue)
                    Text("R1 / L1").tag(ControllerMouseSettings.Clicks.shoulders.rawValue)
                    Text("R2 / L2").tag(ControllerMouseSettings.Clicks.triggers.rawValue)
                }
            }
            slider("Pointer speed", value: $mouseSpeed, in: 0.25...3)
        } header: {
            Theme.label("Controller mouse")
        } footer: {
            Text("Drive the PC's pointer with a controller: one stick moves it, the other scrolls. While it's on, the game doesn't see the controller. Turn it on with Select + R3 or from the ••• menu.")
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

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 0.25,
                        format: String = "%.2g×", scale: Double = 1) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value.wrappedValue * scale)).foregroundStyle(Theme.muted)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
