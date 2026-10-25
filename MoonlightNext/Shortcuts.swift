//
//  Shortcuts.swift
//  MoonLume
//
//  "Open PC" for Shortcuts, Siri, Spotlight and the Action button. It opens the app on a
//  saved PC's game list, the same as the home-screen quick action.
//

import AppIntents

struct PCEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "PC"
    static let defaultQuery = PCQuery()

    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PCQuery: EntityQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [PCEntity] {
        savedPCs().filter { identifiers.contains($0.id) }
    }

    @MainActor func suggestedEntities() async throws -> [PCEntity] { savedPCs() }

    @MainActor private func savedPCs() -> [PCEntity] {
        ((DataManager().getHosts() as? [TemporaryHost]) ?? [])
            .map { PCEntity(id: $0.uuid, name: $0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct OpenPCIntent: AppIntent {
    static let title: LocalizedStringResource = "Open PC"
    static let description = IntentDescription("Opens MoonLume on a PC's games.")
    static let openAppWhenRun = true

    @Parameter(title: "PC") var pc: PCEntity

    @MainActor func perform() async throws -> some IntentResult {
        LauncherModel.current?.openHost(uuid: pc.id)
        return .result()
    }
}

struct MoonLumeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenPCIntent(),
                    phrases: ["Open \(\.$pc) in \(.applicationName)", "Stream \(\.$pc) with \(.applicationName)"],
                    shortTitle: "Open PC",
                    systemImageName: "play.display")
    }
}
