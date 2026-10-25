//
//  StreamAudio.swift
//  MoonLume
//
//  Audio settings the ObjC audio renderer (Connection.m) reads while streaming: stream
//  volume, mixing with other apps, and muting while kept alive in the background.
//

import Foundation

@objc final class MNAudio: NSObject {
    static let volumeKey = "mnStreamVolume"
    static let mixKey = "mnMixWithOthers"
    static let muteInBackgroundKey = "mnMuteInBackground"
    static let backgroundMinutesKey = "mnBackgroundMinutes"

    private static var volume = savedVolume()

    private static func savedVolume() -> Float {
        Float(UserDefaults.standard.object(forKey: volumeKey) as? Double ?? 1)
    }

    /// Re-reads the volume; Settings calls this as the slider moves.
    @objc static func reload() { volume = savedVolume() }

    /// Set while the stream runs in the background without picture in picture and
    /// "Mute in background" is on.
    @objc static var backgroundMuted = false

    /// Gain applied to every decoded sample. The slider is squared so it feels even to the ear.
    @objc static var outputGain: Float { backgroundMuted ? 0 : volume * volume }

    /// Settings › Audio › Let other apps keep playing (off: the stream pauses them)
    @objc static var mixWithOthers: Bool { UserDefaults.standard.bool(forKey: mixKey) }

    @objc static var muteInBackground: Bool { UserDefaults.standard.bool(forKey: muteInBackgroundKey) }

    /// Settings › Stream › Stay connected in background, in minutes (0 = end the stream)
    @objc static var backgroundMinutes: Int { UserDefaults.standard.integer(forKey: backgroundMinutesKey) }
}
