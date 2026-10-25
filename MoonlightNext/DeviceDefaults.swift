//
//  DeviceDefaults.swift
//  Moonlight Next
//
//  First-run stream settings tuned to this device: the panel's native resolution, 120 fps
//  on a ProMotion screen, HEVC when it decodes in hardware, and the matching bitrate.
//  The idea comes from VoidLink's changeDefaultSettings (MainFrameViewController.m).
//

import UIKit

extension SettingsStore {
    private static let tunedKey = "mnDeviceDefaultsApplied"

    /// Runs once. Leaves settings alone if the user has saved any video settings, which we
    /// recognise as anything other than the database defaults (1280×720, 60 fps, 10 Mb/s).
    static func applyDeviceDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: tunedKey) else { return }
        defaults.set(true, forKey: tunedKey)

        guard let saved = DataManager().getSettings(),
              saved.width.intValue == 1280, saved.height.intValue == 720,
              saved.framerate.intValue == 60, saved.bitrate.intValue == 10000 else { return }

        let store = SettingsStore()
        if store.hevcSupported { store.codec = StreamCodec.hevc.rawValue }
        store.framerate = store.supports120 ? 120 : 60
        // Native follows the window at launch (folded, unfolded or an external screen);
        // this also sets the bitrate for the screen and frame rate.
        store.setResolution(width: 0, height: 0)
    }
}
