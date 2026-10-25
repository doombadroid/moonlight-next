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
    static let stickMinimumKey = "mnStickMinimum"

    static var emulated: Emulated { Emulated(rawValue: UserDefaults.standard.integer(forKey: emulatedKey)) ?? .automatic }
    static var motion: Motion { Motion(rawValue: UserDefaults.standard.integer(forKey: motionKey)) ?? .automatic }

    // LI_CTYPE_XBOX, LI_CTYPE_PS
    private static let typeXbox: UInt8 = 0x01
    private static let typePlayStation: UInt8 = 0x02

    /// Physical sticks' anti-deadzone, 0...0.4 of full travel
    @objc static var stickMinimum: Double { UserDefaults.standard.double(forKey: stickMinimumKey) }

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

/// Settings › Controller.
struct ControllerSettingsSection: View {
    @AppStorage(MNControllerPrefs.emulatedKey) private var emulated = MNControllerPrefs.Emulated.automatic.rawValue
    @AppStorage(MNControllerPrefs.motionKey) private var motionSource = MNControllerPrefs.Motion.automatic.rawValue
    @AppStorage(MNRumble.targetKey) private var rumbleTarget = MNRumble.Target.automatic.rawValue
    @AppStorage(MNRumble.phoneFallbackKey) private var phoneRumble = true
    @AppStorage(MNRumble.swapKey) private var swapMotors = false
    @AppStorage(MNAdaptiveTriggers.enabledKey) private var adaptiveTriggers = true
    @AppStorage(MNControllerPrefs.stickMinimumKey) private var stickMinimum = 0.0

    var body: some View {
        SettingsSection("Controller", id: "controller") {
            SettingChoice("Emulated controller", id: MNControllerPrefs.emulatedKey,
                          tip: "PlayStation makes the host create a DualShock or DualSense, so games and Steam Input can use the phone's motion sensors as the pad's gyro. It needs a Windows or Linux host: Sunshine on macOS has no virtual controller.") {
                Picker("Emulated controller", selection: $emulated) {
                    Text("Automatic").tag(MNControllerPrefs.Emulated.automatic.rawValue)
                    Text("Xbox").tag(MNControllerPrefs.Emulated.xbox.rawValue)
                    Text("PlayStation").tag(MNControllerPrefs.Emulated.playStation.rawValue)
                }
            }
            SettingChoice("Motion sensors", id: MNControllerPrefs.motionKey,
                          note: emulated == MNControllerPrefs.Emulated.xbox.rawValue ? "Needs PlayStation" : nil,
                          tip: "Which gyro the host's virtual PlayStation pad reports. Auto uses a connected controller's own gyro when it has one, otherwise the phone's.") {
                Picker("Motion sensors", selection: $motionSource) {
                    Text("Auto").tag(MNControllerPrefs.Motion.automatic.rawValue)
                    Text("Phone").tag(MNControllerPrefs.Motion.phone.rawValue)
                    Text("Controller").tag(MNControllerPrefs.Motion.controller.rawValue)
                    Text("Off").tag(MNControllerPrefs.Motion.off.rawValue)
                }
            }
            SettingChoice("Rumble", id: MNRumble.targetKey) {
                Picker("Rumble", selection: $rumbleTarget) {
                    Text("Auto").tag(MNRumble.Target.automatic.rawValue)
                    Text("Phone").tag(MNRumble.Target.phone.rawValue)
                    Text("Off").tag(MNRumble.Target.off.rawValue)
                }
            }
            if rumbleTarget == MNRumble.Target.automatic.rawValue {
                SettingToggle("Phone rumble without a controller", id: MNRumble.phoneFallbackKey, isOn: $phoneRumble)
            }
            SettingToggle("Swap rumble motors", id: MNRumble.swapKey, isOn: $swapMotors)
            SettingToggle("DualSense adaptive triggers", id: MNAdaptiveTriggers.enabledKey, isOn: $adaptiveTriggers,
                          tip: "Trigger resistance reaches a real DualSense only when the host emulates one, in practice Sunshine on Linux.")
            SettingSlider("Stick minimum offset", id: MNControllerPrefs.stickMinimumKey, value: $stickMinimum, in: 0...0.4,
                          step: 0.05, format: "%.0f%%", scale: 100,
                          tip: "Lifts a controller's small stick movements past a game's deadzone.")
        } footer: {
            Text("Controller type and motion apply the next time you connect.")
        }
    }
}

/// Settings › Gyro.
struct GyroSettingsSection: View {
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

    @SwiftUI.State private var calibration: String?

    var body: some View {
        SettingsSection("Gyro", id: "gyro") {
            SettingChoice("Gyro aiming", id: GyroSettings.modeKey,
                          tip: "Turn the phone, or the controller's gyro, to aim. Mouse suits most PC games and the desktop; right stick suits games that only take a controller.",
                          learnMore: "http://gyrowiki.jibbsmart.com") {
                Picker("Gyro aiming", selection: $gyroMode) {
                    Text("Off").tag(GyroSettings.Mode.off.rawValue)
                    Text("Mouse").tag(GyroSettings.Mode.mouse.rawValue)
                    Text("Right stick").tag(GyroSettings.Mode.rightStick.rawValue)
                }
            }
            if gyroMode != GyroSettings.Mode.off.rawValue {
                SettingChoice("Aim with", id: GyroSettings.sourceKey) {
                    Picker("Aim with", selection: $gyroSource) {
                        Text("Phone").tag(GyroSettings.Source.phone.rawValue)
                        Text("Controller's gyro").tag(GyroSettings.Source.controller.rawValue)
                    }
                }
                SettingChoice("Active", id: GyroSettings.activationKey) {
                    Picker("Active", selection: $gyroActivation) {
                        Text("Always").tag(GyroSettings.Activation.always.rawValue)
                        Text("While L2 is held").tag(GyroSettings.Activation.whileAiming.rawValue)
                    }
                }
                SettingRow("Gyro button", id: GyroSettings.buttonKey,
                           tip: "A button on a physical controller that turns gyro aiming on or off. It still reaches the game.") { label in
                    HStack {
                        label
                        Spacer()
                        Picker("Gyro button", selection: $gyroButton) {
                            ForEach(GyroSettings.Button.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
                if gyroButton != GyroSettings.Button.none.rawValue {
                    SettingChoice("Button", id: GyroSettings.buttonModeKey) {
                        Picker("Button", selection: $gyroButtonMode) {
                            Text("Hold to aim").tag(GyroSettings.ButtonMode.hold.rawValue)
                            Text("Toggle").tag(GyroSettings.ButtonMode.toggle.rawValue)
                            Text("Hold to pause").tag(GyroSettings.ButtonMode.holdToPause.rawValue)
                        }
                    }
                }
                SettingSlider("Sensitivity", id: GyroSettings.sensitivityKey, value: $gyroSensitivity, in: 0.25...4)
                SettingSlider("Horizontal", id: GyroSettings.sensitivityXKey, value: $gyroSensitivityX, in: 0.25...2)
                SettingSlider("Vertical", id: GyroSettings.sensitivityYKey, value: $gyroSensitivityY, in: 0.25...2)
                SettingToggle("Invert up/down", id: GyroSettings.invertYKey, isOn: $gyroInvertY)
            }
            SettingToggle("Tilt to steer", id: GyroSettings.steeringKey, isOn: $steering,
                          tip: "Turns the phone's roll, like a wheel, into the left stick.")
            if steering {
                SettingSlider("Steering sensitivity", id: GyroSettings.steeringSensitivityKey, value: $steeringSensitivity, in: 0.5...3)
            }
            if steering || gyroMode == GyroSettings.Mode.rightStick.rawValue {
                SettingSlider("Minimum stick offset", id: GyroSettings.minStickKey, value: $gyroMinStick, in: 0...0.4,
                              step: 0.05, format: "%.0f%%", scale: 100,
                              tip: "Gets small gyro movements past a game's stick deadzone.")
            }
            SettingRow("Calibrate drift", id: "gyroCalibrate",
                       tip: "Lay the phone and controller down for two seconds, then calibrate.") { label in
                HStack {
                    label
                    Spacer()
                    if let calibration { Text(calibration).font(.system(size: 13)).foregroundStyle(Theme.muted) }
                    Button("Calibrate", action: calibrate)
                        .buttonStyle(.borderless)
                        .navTarget(activate: calibrate)
                }
            }
        } footer: {
            Text("Pause gyro from the ••• menu while streaming.")
        }
    }

    private func calibrate() {
        calibration = "Keep still…"
        MNGyro.shared.calibrate { ok in
            calibration = ok ? "Calibrated" : "It moved. Lay it down and try again."
        }
    }
}

/// Settings › Controller mouse.
struct ControllerMouseSettingsSection: View {
    @AppStorage(ControllerMouseSettings.chordKey) private var mouseChord = true
    @AppStorage(ControllerMouseSettings.leftStickKey) private var mouseLeftStick = false
    @AppStorage(ControllerMouseSettings.clicksKey) private var mouseClicks = ControllerMouseSettings.Clicks.faceButtons.rawValue
    @AppStorage(ControllerMouseSettings.speedKey) private var mouseSpeed = 1.0

    var body: some View {
        SettingsSection("Controller mouse", id: "controllerMouse") {
            SettingToggle("Select + R3 toggles it", id: ControllerMouseSettings.chordKey, isOn: $mouseChord)
            SettingChoice("Pointer stick", id: ControllerMouseSettings.leftStickKey) {
                Picker("Pointer stick", selection: $mouseLeftStick) {
                    Text("Right").tag(false)
                    Text("Left").tag(true)
                }
            }
            SettingChoice("Left / right click", id: ControllerMouseSettings.clicksKey) {
                Picker("Left / right click", selection: $mouseClicks) {
                    Text("A / B").tag(ControllerMouseSettings.Clicks.faceButtons.rawValue)
                    Text("R1 / L1").tag(ControllerMouseSettings.Clicks.shoulders.rawValue)
                    Text("R2 / L2").tag(ControllerMouseSettings.Clicks.triggers.rawValue)
                }
            }
            SettingSlider("Pointer speed", id: ControllerMouseSettings.speedKey, value: $mouseSpeed, in: 0.25...3)
        } footer: {
            Text("Drive the PC's pointer with a controller: one stick moves it, the other scrolls. While it's on, the game doesn't see the controller. Turn it on with Select + R3 or from the ••• menu.")
        }
    }
}
