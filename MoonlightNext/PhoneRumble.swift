//
//  PhoneRumble.swift
//  MoonLume
//
//  Game rumble on the phone itself: when no physical controller is connected (on-screen
//  controls or the input deck), or always when Settings › Controller › Rumble is Phone. The host's two motors map to one continuous Core Haptics
//  event: the stronger motor sets the intensity, and the high-frequency motor's share sets
//  the sharpness.
//

import CoreHaptics
import Foundation

@objc enum MNRumbleRoute: Int {
    case controller, phone, none
}

/// Where the host's rumble goes (Settings › Controller › Rumble).
@objc final class MNRumble: NSObject {
    enum Target: Int { case automatic = 0, phone = 1, off = 2 }

    static let targetKey = "mnRumbleTarget"
    static let swapKey = "mnRumbleSwap"
    /// Phone rumble when player 1 has no physical controller (on unless turned off)
    static let phoneFallbackKey = "mnPhoneRumble"

    static var target: Target { Target(rawValue: UserDefaults.standard.integer(forKey: targetKey)) ?? .automatic }
    @objc static var swapMotors: Bool { UserDefaults.standard.bool(forKey: swapKey) }
    static var phoneFallback: Bool { UserDefaults.standard.object(forKey: phoneFallbackKey) as? Bool ?? true }

    /// Only player 1 can rumble the phone; other players' pads keep their own rumble unless it's off.
    @objc static func route(forPlayer player: Int, hasController: Bool) -> MNRumbleRoute {
        switch target {
        case .off: return .none
        case _ where player != 0: return .controller
        case .phone: return .phone
        case .automatic: return hasController ? .controller : (phoneFallback ? .phone : .none)
        }
    }
}

@objc final class MNPhoneRumble: NSObject {
    @objc static let shared = MNPhoneRumble()

    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var running = false
    /// Between a stream's start and end (main thread). Host rumble that arrives later, from the
    /// connection's thread while it shuts down, is dropped instead of looping on in the launcher.
    private var active = false

    private override init() {
        super.init()
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.playsHapticsOnly = true
        engine?.resetHandler = { [weak self] in
            self?.player = nil
            self?.running = false
        }
    }

    /// Called by ControllerSupport with the host's motor levels (0...65535); may be off the main thread.
    @objc(setLow:high:) func set(low: UInt16, high: UInt16) {
        DispatchQueue.main.async {
            guard self.active else { return }
            self.apply(low: low, high: high)
        }
    }

    /// Silences the phone; any thread.
    @objc func stop() {
        DispatchQueue.main.async { self.apply(low: 0, high: 0) }
    }

    /// A stream starts; main thread.
    @objc func start() {
        active = true
    }

    /// The stream ends: silent now and for any rumble still queued. Main thread.
    @objc func end() {
        active = false
        apply(low: 0, high: 0)
    }

    private func apply(low: UInt16, high: UInt16) {
        guard let engine else { return }
        let intensity = Float(max(low, high)) / 65535
        guard intensity > 0.02 else {
            if running {
                try? player?.stop(atTime: CHHapticTimeImmediate)
                running = false
            }
            return
        }
        let total = Float(low) + Float(high)
        let sharpness = total > 0 ? Float(high) / total : 0.5
        do {
            if player == nil {
                // One long continuous event; levels change through dynamic parameters
                let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                ], relativeTime: 0, duration: 30)
                player = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [event], parameters: []))
                player?.loopEnabled = true
            }
            try engine.start()
            if !running {
                try player?.start(atTime: CHHapticTimeImmediate)
                running = true
            }
            try player?.sendParameters([
                CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0),
                CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: sharpness - 0.5, relativeTime: 0),
            ], atTime: CHHapticTimeImmediate)
        } catch {
            player = nil
            running = false
        }
    }
}
