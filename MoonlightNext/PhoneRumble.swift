//
//  PhoneRumble.swift
//  MoonLume
//
//  Game rumble on the phone itself when no physical controller is connected (on-screen
//  controls or the input deck). The host's two motors map to one continuous Core Haptics
//  event: the stronger motor sets the intensity, and the high-frequency motor's share sets
//  the sharpness.
//

import CoreHaptics
import Foundation

@objc final class MNPhoneRumble: NSObject {
    @objc static let shared = MNPhoneRumble()

    /// Settings › Input › Phone rumble (on unless turned off)
    static var enabled: Bool { UserDefaults.standard.object(forKey: "mnPhoneRumble") as? Bool ?? true }

    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var running = false

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
        DispatchQueue.main.async { self.apply(low: low, high: high) }
    }

    @objc func stop() {
        DispatchQueue.main.async { self.apply(low: 0, high: 0) }
    }

    private func apply(low: UInt16, high: UInt16) {
        guard let engine else { return }
        let intensity = Float(max(low, high)) / 65535
        guard intensity > 0.02, MNPhoneRumble.enabled else {
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
