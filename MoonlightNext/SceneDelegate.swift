//
//  SceneDelegate.swift
//  Moonlight Next
//
//  Apps built with the iOS 27 SDK must use the scene life cycle or they fail to launch.
//  The window, foreground/background handling and home-screen shortcuts live here;
//  the Core Data stack stays in AppDelegate.
//

import UIKit
import SwiftUI

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let model = LauncherModel()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(red: 0x2A / 255, green: 0x2A / 255, blue: 0x32 / 255, alpha: 1)

        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = .dark
        window.backgroundColor = .black
        window.tintColor = UIColor(Theme.accent)
        let root = UIHostingController(rootView: LauncherView().environmentObject(model))
        root.view.backgroundColor = .black
        window.rootViewController = root
        self.window = window
        model.window = window
        LauncherModel.current = model
        window.makeKeyAndVisible()

        model.start()
        if let shortcut = connectionOptions.shortcutItem {
            model.openHost(uuid: shortcut.userInfo?["UUID"] as? String)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        model.openHost(uuid: shortcutItem.userInfo?["UUID"] as? String, completion: completionHandler)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        model.enterForeground()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        model.enterBackground()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        (UIApplication.shared.delegate as? AppDelegate)?.saveContext()
    }
}
