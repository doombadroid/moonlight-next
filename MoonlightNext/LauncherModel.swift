//
//  LauncherModel.swift
//  Moonlight Next
//
//  State and actions for the SwiftUI launcher. The logic is ported from
//  MainFrameViewController.m; the ObjC services (discovery, pairing, app list,
//  box art, Core Data) are used unchanged.
//

import UIKit
import Combine

struct LauncherAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Choice offered when an app is tapped while another app is running on the host.
struct RunningAppChoice: Identifiable {
    let id = UUID()
    let tapped: TemporaryApp
    let running: TemporaryApp
}

final class LauncherModel: NSObject, ObservableObject, DiscoveryCallback, PairCallback, AppAssetCallback {
    @Published private(set) var hosts: [TemporaryHost] = []
    @Published private(set) var selectedHost: TemporaryHost?
    @Published private(set) var apps: [TemporaryApp] = []
    @Published var showHiddenApps = false
    @Published var busyMessage: String?
    @Published var alert: LauncherAlert?
    @Published var pairingPIN: String?
    @Published var runningAppChoice: RunningAppChoice?
    @Published private(set) var boxArtVersion = 0

    /// The window streams are presented from; set by SceneDelegate.
    weak var window: UIWindow?

    private var discMan: DiscoveryManager!
    private var appManager: AppAssetManager!
    private let opQueue = OperationQueue()
    private var clientCert: Data?
    private var started = false
    private var background = false
    private var isStreaming = false
    private var pendingShortcutUUID: String?
    private var shortcutCompletion: ((Bool) -> Void)?

    private let boxArtCache = NSCache<NSString, UIImage>()
    private var boxArtLoading = Set<String>()

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        CryptoManager.generateKeyPairUsingSSL()
        _ = IdManager.getUniqueId()
        clientCert = CryptoManager.readCertFromFile()
        appManager = AppAssetManager(callback: self)

        retrieveSavedHosts()
        discMan = DiscoveryManager(hosts: hosts, andCallback: self)

        if hosts.count == 1, let only = hosts.first {
            select(only, userInitiated: false)
        }
    }

    func enterForeground() {
        background = false
        guard started, !isStreaming else { return }
        beginForegroundRefresh()
        handlePendingShortcut()
    }

    func enterBackground() {
        background = true
        guard started, !isStreaming else { return }
        discMan.stopDiscovery()
    }

    private func beginForegroundRefresh() {
        guard !background else { return }
        updateHosts()
        // Reset state first so we can rediscover hosts that were deleted before
        discMan.resetDiscoveryState()
        discMan.startDiscovery()
        // Refresh the app list (and running game) of the selected paired host
        if let host = selectedHost, host.pairState == .paired {
            select(host, userInitiated: false)
        }
    }

    /// Home-screen quick action. Returns false if no saved host matches.
    func openHost(uuid: String?, completion: ((Bool) -> Void)? = nil) {
        pendingShortcutUUID = uuid
        shortcutCompletion = completion
        if started && !background { handlePendingShortcut() }
    }

    private func handlePendingShortcut() {
        guard let uuid = pendingShortcutUUID else { return }
        pendingShortcutUUID = nil
        let match = hosts.first { $0.uuid == uuid }
        shortcutCompletion?(match != nil)
        shortcutCompletion = nil
        if let match, match !== selectedHost {
            select(match, userInitiated: false)
        }
    }

    // MARK: - Hosts

    private func retrieveSavedHosts() {
        let saved = (DataManager().getHosts() as? [TemporaryHost]) ?? []
        // Initialize the non-persistent host state
        for host in saved where host.activeAddress == nil {
            host.activeAddress = host.localAddress ?? host.externalAddress ?? host.address ?? host.ipv6Address
        }
        hosts = saved.sorted { $0.compareName($1) == .orderedAscending }
    }

    @objc(updateAllHosts:)
    func updateAllHosts(_ newHosts: [Any]!) {
        // Copy: the array can be modified before our main-thread dispatch runs
        let copy = (newHosts as? [TemporaryHost]) ?? []
        DispatchQueue.main.async {
            self.hosts = copy
            self.updateHosts()
        }
    }

    private func updateHosts() {
        hosts = hosts.sorted { $0.compareName($1) == .orderedAscending }
        if let selected = selectedHost, !hosts.contains(where: { $0 === selected }) {
            // Discovery hands back new objects; keep the selection on the same PC
            selectedHost = hosts.first { $0.uuid == selected.uuid }
        }
        for host in hosts {
            for case let app as TemporaryApp in host.appList {
                loadBoxArt(app)
            }
        }
        updateHostShortcuts()
        if selectedHost != nil { refreshApps() }
    }

    private func updateHostShortcuts() {
        // Pair state may be unknown before polling, but the app list persists for paired PCs
        UIApplication.shared.shortcutItems = hosts.filter { $0.appList.count > 0 }.map {
            UIApplicationShortcutItem(type: "PC", localizedTitle: $0.name, localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(type: .play),
                                      userInfo: ["UUID": $0.uuid as NSString])
        }
    }

    func deselectHost() {
        appManager?.stopRetrieving()
        showHiddenApps = false
        selectedHost = nil
        apps = []
    }

    /// Port of hostClicked:view:. userInitiated corresponds to a non-nil view upstream:
    /// only user taps show errors or start pairing.
    func select(_ host: TemporaryHost, userInitiated: Bool) {
        if selectedHost !== host {
            showHiddenApps = false
        }
        selectedHost = host
        refreshApps()

        // Offline PCs show their offline page (wake, test network) instead of hanging here
        if host.state == .offline && userInitiated {
            return
        }

        // Fast path: online, paired and a cached app list. Not taken when refreshing
        // after a stream, since serverinfo is needed for the running game.
        if host.state == .online && host.pairState == .paired && host.appList.count > 0 && userInitiated {
            alreadyPaired()
            return
        }

        if userInitiated || host.appList.count == 0 {
            busyMessage = "Connecting to \(host.name)…"
        }
        DispatchQueue.global().async {
            // Wait for the PC's status to be known
            var waited = 0
            while host.state == .unknown && waited < 15 {
                sleep(1)
                waited += 1
            }
            if host.state != .online {
                DispatchQueue.main.async { self.busyMessage = nil }
                return
            }

            self.discMan.pauseDiscovery(for: host)
            let error = MNBridge.refreshServerInfo(for: host)
            self.discMan.resumeDiscovery(for: host)

            if let error {
                DispatchQueue.main.async {
                    self.busyMessage = nil
                    host.state = .offline
                    self.objectWillChange.send()
                    if userInitiated && host === self.selectedHost {
                        self.alert = LauncherAlert(title: "Connection Failed", message: error)
                    }
                }
            } else if host.pairState == .paired {
                self.alreadyPaired()
            } else if userInitiated {
                // Polling the server while pairing causes the server to screw up
                self.discMan.stopDiscoveryBlocking()
                let pairManager = PairManager(manager: HttpManager(host: host), clientCert: self.clientCert, callback: self)
                self.opQueue.addOperation(pairManager!)
            } else {
                DispatchQueue.main.async {
                    self.busyMessage = nil
                    self.objectWillChange.send()
                }
            }
        }
    }

    /// Asks to pair the selected (online, unpaired) host.
    func pairSelectedHost() {
        if let host = selectedHost {
            select(host, userInitiated: true)
        }
    }

    func cancelPairing() {
        pairingPIN = nil
        discMan.startDiscovery()
    }

    func wake(_ host: TemporaryHost) {
        guard let mac = host.mac, mac != "00:00:00:00:00:00" else {
            alert = LauncherAlert(title: "Wake-on-LAN", message: "Host MAC unknown, unable to send WOL Packet")
            return
        }
        DispatchQueue.global().async { WakeOnLanManager.wake(host) }
        alert = LauncherAlert(title: "Wake-on-LAN", message: "Sent a wake-up request. It may take a few moments for the PC to wake. If it never wakes up, make sure it's set up for Wake-on-LAN.")
    }

    func testNetwork() {
        busyMessage = "Testing your network…"
        DispatchQueue.global().async {
            let message = MNBridge.runNetworkTest()
            DispatchQueue.main.async {
                self.busyMessage = nil
                self.alert = LauncherAlert(title: "Network Test Complete", message: message)
            }
        }
    }

    func addHost(address rawAddress: String) {
        let address = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        busyMessage = "Looking for \(address)…"
        DispatchQueue.global(qos: .userInitiated).async {
            self.discMan.discoverHost(address) { host, error in
                if let host {
                    DispatchQueue.main.async {
                        self.busyMessage = nil
                        if !self.hosts.contains(where: { $0 === host }) {
                            self.hosts.append(host)
                        }
                        self.updateHosts()
                        self.select(host, userInitiated: false)
                    }
                } else {
                    let message = (error ?? "Unable to find the PC.") + MNBridge.addHostPortBlockingNote()
                    DispatchQueue.main.async {
                        self.busyMessage = nil
                        self.alert = LauncherAlert(title: "Add Computer", message: message)
                    }
                }
            }
        }
    }

    func remove(_ host: TemporaryHost) {
        discMan.removeHost(fromDiscovery: host)
        DataManager().remove(host)
        hosts.removeAll { $0 === host }
        if selectedHost === host { deselectHost() }
        updateHosts()
    }

    // MARK: - Pairing (PairCallback)

    @objc(startPairing:)
    func startPairing(_ pin: String!) {
        // Synchronous so the PIN is up before any failure callback can arrive
        DispatchQueue.main.sync {
            self.busyMessage = nil
            self.pairingPIN = pin
        }
    }

    @objc(pairSuccessful:)
    func pairSuccessful(_ serverCert: Data!) {
        DispatchQueue.main.async {
            // Store the cert from pairing with the host
            self.selectedHost?.serverCert = serverCert
            self.pairingPIN = nil
            self.discMan.startDiscovery()
            self.alreadyPaired()
        }
    }

    @objc(pairFailed:)
    func pairFailed(_ message: String!) {
        DispatchQueue.main.async {
            let wasPairing = self.pairingPIN != nil
            self.pairingPIN = nil
            self.busyMessage = nil
            self.discMan.startDiscovery()
            if wasPairing {
                self.alert = LauncherAlert(title: "Pairing Failed", message: message ?? "")
            }
        }
    }

    // MARK: - Apps

    /// Port of alreadyPaired: show the cached app list, then refresh it from the PC.
    @objc func alreadyPaired() {
        DispatchQueue.main.async {
            guard let host = self.selectedHost else {
                self.busyMessage = nil
                return
            }
            if host.appList.count > 0 {
                self.refreshApps()
                self.busyMessage = nil
            }
            DispatchQueue.global().async {
                // Exempt this host from discovery while handling the applist query
                self.discMan.pauseDiscovery(for: host)
                let response = ConnectionHelper.getAppList(for: host)
                self.discMan.resumeDiscovery(for: host)

                let list = response?.getAppList()
                DispatchQueue.main.async {
                    self.busyMessage = nil
                    guard let response, response.isStatusOk(), let list else {
                        if host === self.selectedHost {
                            self.alert = LauncherAlert(title: "Connection Interrupted", message: response?.statusMessage ?? "")
                        }
                        host.state = .offline
                        self.objectWillChange.send()
                        return
                    }
                    self.updateAppList(list.compactMap { $0 as? TemporaryApp }, for: host)
                    if host === self.selectedHost {
                        self.refreshApps()
                        self.appManager.stopRetrieving()
                        self.appManager.retrieveAssets(from: host)
                    }
                }
            }
        }
    }

    /// Port of updateApplist:forHost: — merge the PC's list into the saved one.
    private func updateAppList(_ newList: [TemporaryApp], for host: TemporaryHost) {
        let database = DataManager()
        var merged = host.appList.compactMap { $0 as? TemporaryApp }

        for app in newList {
            if let saved = merged.first(where: { $0.id == app.id }) {
                saved.name = app.name
                saved.hdrSupported = app.hdrSupported
                // Don't propagate hidden, because we want the local data to prevail
            } else {
                app.host = host
                merged.append(app)
            }
        }

        // Remove the database record of apps the PC no longer has, or the
        // appList constraint is violated
        let newIDs = Set(newList.compactMap { $0.id })
        for app in merged where !newIDs.contains(app.id ?? "") {
            database.remove(app)
        }
        merged.removeAll { !newIDs.contains($0.id ?? "") }

        host.appList = Set(merged.map(AnyHashable.init))
        database.updateApps(forExistingHost: host)
        updateHostShortcuts()
    }

    private func refreshApps() {
        guard let host = selectedHost else {
            apps = []
            return
        }
        apps = host.appList.compactMap { $0 as? TemporaryApp }
            .filter { showHiddenApps || !$0.hidden }
            .sorted { $0.compareName($1) == .orderedAscending }
        apps.forEach(loadBoxArt)
    }

    func setShowHiddenApps(_ show: Bool) {
        showHiddenApps = show
        refreshApps()
    }

    func runningApp(on host: TemporaryHost) -> TemporaryApp? {
        host.appList.compactMap { $0 as? TemporaryApp }.first { $0.id == host.currentGame }
    }

    func toggleHidden(_ app: TemporaryApp) {
        guard let host = app.host else { return }
        app.hidden.toggle()
        // Port of updateAppEntry:forHost:
        host.appList = Set(host.appList)
        DataManager().updateApps(forExistingHost: host)
        objectWillChange.send()
    }

    /// Port of appClicked: stream directly unless something else is running.
    func tapped(_ app: TemporaryApp) {
        appManager.stopRetrieving()
        if let host = app.host, let running = runningApp(on: host) {
            runningAppChoice = RunningAppChoice(tapped: app, running: running)
        } else {
            stream(app)
        }
    }

    /// Quits the running app; then streams `next` if given.
    func quitRunningApp(on host: TemporaryHost, thenStream next: TemporaryApp? = nil) {
        busyMessage = "Quitting…"
        DispatchQueue.global().async {
            // Exempt this host from discovery while handling the quit operation
            self.discMan.pauseDiscovery(for: host)
            let error = MNBridge.quitApp(on: host)
            self.discMan.resumeDiscovery(for: host)
            DispatchQueue.main.async {
                self.busyMessage = nil
                self.refreshApps()
                if let error {
                    self.alert = LauncherAlert(title: "Quitting App Failed", message: error)
                } else if let next {
                    self.stream(next)
                }
            }
        }
    }

    // MARK: - Streaming

    func stream(_ app: TemporaryApp) {
        guard let window, let root = window.rootViewController, let host = app.host else { return }
        appManager.stopRetrieving()

        let config = MNBridge.streamConfig(for: app, window: window)
        let streamVC = MNBridge.streamController(with: config) { [weak self, weak root] quitApp in
            root?.dismiss(animated: true) {
                guard let self else { return }
                self.isStreaming = false
                if quitApp {
                    self.quitRunningApp(on: host)
                }
                self.beginForegroundRefresh()
            }
        }

        // The launcher's discovery must not run during the stream
        isStreaming = true
        discMan.stopDiscovery()
        // A confirmation dialog or sheet may still be up (or dismissing); clear it first
        if root.presentedViewController != nil {
            root.dismiss(animated: false) { root.present(streamVC, animated: true) }
        } else {
            root.present(streamVC, animated: true)
        }
    }

    // MARK: - Box art (AppAssetCallback)

    @objc(receivedAssetForApp:)
    func receivedAsset(for app: TemporaryApp!) {
        guard let app else { return }
        boxArtCache.removeObject(forKey: boxArtKey(app))
        DispatchQueue.main.async { self.loadBoxArt(app) }
    }

    func boxArt(for app: TemporaryApp) -> UIImage? {
        boxArtCache.object(forKey: boxArtKey(app))
    }

    private func boxArtKey(_ app: TemporaryApp) -> NSString {
        "\(app.host?.uuid ?? "")/\(app.id ?? "")" as NSString
    }

    /// Decodes box art off the main thread so scrolling stays smooth.
    private func loadBoxArt(_ app: TemporaryApp) {
        let key = boxArtKey(app)
        guard boxArtCache.object(forKey: key) == nil, !boxArtLoading.contains(key as String) else { return }
        boxArtLoading.insert(key as String)
        DispatchQueue.global(qos: .utility).async {
            let image = UIImage(contentsOfFile: AppAssetManager.boxArtPath(for: app))?.preparingForDisplay()
            DispatchQueue.main.async {
                self.boxArtLoading.remove(key as String)
                if let image {
                    self.boxArtCache.setObject(image, forKey: key)
                    self.boxArtVersion += 1
                }
            }
        }
    }
}
