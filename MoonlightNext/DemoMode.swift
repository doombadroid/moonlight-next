//
//  DemoMode.swift
//  Moonlight Next
//
//  Demo mode for App Store screenshots in a simulator that can't reach a PC. Only on with the
//  launch argument `-MNDemoMode YES` (UserDefaults' argument domain: nothing is saved). The
//  launcher then shows one made-up PC and never starts discovery, pairing or any network
//  request, and a stream shows a bundled still (asset DemoStreamFrame) instead of connecting.
//  Art: tools/gen-demo-art.py.
//

import UIKit

@objc(MNDemo) final class MNDemo: NSObject {
    @objc static let isOn: Bool = {
        switch UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["MNDemoMode"] {
        case let value as Bool: return value
        case let value as String: return (value as NSString).boolValue
        case let value as NSNumber: return value.boolValue
        default: return false
        }
    }()

    /// The demo PC: paired and online, with SuperTuxKart running.
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
        let apps = [("1", "Desktop", "Desktop"), ("2", "SuperTuxKart", "SuperTuxKart"),
                    ("3", "Xonotic", "Xonotic"), ("4", "0 A.D.", "0AD")].map { id, name, asset in
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
