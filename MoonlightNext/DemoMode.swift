//
//  DemoMode.swift
//  Moonlight Next
//
//  Demo mode for App Store screenshots in a simulator that can't reach a PC. Only on with the
//  launch argument `-MNDemoMode YES`, and only in the simulator: hosts are kept out of storage,
//  but settings and layout edits made in demo mode are saved as usual, so it's meant for a
//  throwaway simulator (on a device it would need an in-memory Core Data store and its own
//  UserDefaults suite). The launcher shows one made-up PC and never starts discovery, pairing
//  or any network request, and a stream shows a bundled still (asset DemoStreamFrame).
//  Art: tools/gen-demo-art.py.
//

import UIKit

@objc(MNDemo) final class MNDemo: NSObject {
    private static var arguments: [String: Any] {
        UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    }

    @objc static let isOn: Bool = {
        #if targetEnvironment(simulator)
        switch MNDemo.arguments["MNDemoMode"] {
        case let value as Bool: return value
        case let value as String: return (value as NSString).boolValue
        case let value as NSNumber: return value.boolValue
        default: return false
        }
        #else
        return false
        #endif
    }()

    /// `-MNDemoSettingsAnchor gyro-header`: Settings opens scrolled to that section's header
    /// (`<id>-header`), or to its first row (`<id>`)
    static var settingsAnchor: String? { isOn ? arguments["MNDemoSettingsAnchor"] as? String : nil }

    /// The demo PC: paired and online, with Duskline Rally (a made-up game) running.
    static func makeHost() -> (TemporaryHost, [String: UIImage]) {
        let host = TemporaryHost()
        host.name = "Gaming PC"
        host.uuid = "00000000-0000-0000-0000-00000000DE70"
        host.address = "192.168.1.20"
        host.localAddress = "192.168.1.20"
        host.activeAddress = "192.168.1.20"
        host.httpsPort = 47984
        host.state = .online
        host.pairState = .paired

        var art: [String: UIImage] = [:]
        let apps = [("1", "Desktop", "Desktop"), ("2", "Duskline Rally", "DusklineRally"),
                    ("3", "Prism Arena", "PrismArena"), ("4", "Ember Ages", "EmberAges")].map { id, name, asset in
            let app = TemporaryApp()
            app.id = id
            app.name = name
            app.host = host
            art[id] = UIImage(named: "DemoArt-\(asset)")
            return app
        }
        host.appList = Set(apps.map(AnyHashable.init))
        host.currentGame = "2"
        return (host, art)
    }
}
