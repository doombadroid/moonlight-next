//
//  ControllerNavigationViews.swift
//  MoonLume
//
//  Settings › Controller navigation, and the sheet shown the first time a controller connects:
//  it explains the buttons and the quick menu, and offers to turn navigation off or pick the
//  quick menu button.
//

import GameController
import SwiftUI

/// Settings › Controller navigation.
struct ControllerNavigationSection: View {
    @AppStorage(ControllerNavSettings.enabledKey) private var enabled = true
    @AppStorage(ControllerNavSettings.hintsKey) private var hints = true
    @AppStorage(QuickMenuSettings.buttonKey) private var quickMenuButton = QuickMenuSettings.Button.guide.rawValue

    var body: some View {
        Section {
            Toggle("Navigate MoonLume with a controller", isOn: $enabled)
            if enabled {
                Toggle("Button hints", isOn: $hints)
            }
            QuickMenuButtonPicker(selection: $quickMenuButton)
        } header: {
            Theme.label("Controller navigation")
        } footer: {
            Text("The d-pad or left stick moves through computers, apps and settings: A selects, B goes back, X shows an app's or computer's options, Y or Menu opens Settings, and L1 and R1 switch between the computer list and the apps. Touching the screen hides the focus ring. In a stream, hold the quick menu button for half a second: tilt a stick to pick, let go to choose (Quit needs A), B cancels. A short press still reaches the game. Guide uses Select + Start on controllers without one.")
        }
    }
}

struct QuickMenuButtonPicker: View {
    @Binding var selection: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick menu button")
            Picker("Quick menu button", selection: $selection) {
                ForEach(QuickMenuSettings.Button.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

/// First connection of a controller.
struct ControllerWizard: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ControllerNavSettings.enabledKey) private var enabled = true
    @AppStorage(QuickMenuSettings.buttonKey) private var quickMenuButton = QuickMenuSettings.Button.guide.rawValue

    private let pad = MNControllerNav.pad

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Navigate MoonLume with it", isOn: $enabled)
                    if enabled {
                        row(pad?.dpad.sfSymbolsName ?? "dpad", "Move between computers, apps and settings")
                        row(MNControllerNav.symbol(for: .a, pad: pad), "Select")
                        row(MNControllerNav.symbol(for: .b, pad: pad), "Back, or close a sheet")
                        row(MNControllerNav.symbol(for: .x, pad: pad), "Options for an app or computer")
                        row(MNControllerNav.symbol(for: .y, pad: pad), "Settings")
                        row(pad?.rightShoulder.sfSymbolsName ?? "r1.rectangle.roundedbottom", "Switch between computers and apps (L1, R1)")
                    }
                } header: {
                    Theme.label(pad?.controller?.vendorName ?? "Controller")
                } footer: {
                    Text("Touching the screen hides the focus ring; press any button to bring it back.")
                }

                Section {
                    QuickMenuButtonPicker(selection: $quickMenuButton)
                } header: {
                    Theme.label("In a stream")
                } footer: {
                    Text(quickMenuButton == QuickMenuSettings.Button.off.rawValue
                         ? "The quick menu is off. The ••• button on the stream has the same actions."
                         : "Hold \(QuickMenuSettings.buttonName(for: pad)) for half a second for the quick menu: disconnect, quit, keyboard, stats, settings, picture in picture, controller mouse, gyro and control editing. Tilt a stick to pick and let go to choose; Quit needs A. A short press still reaches the game.")
                }

                Section {
                    Button("Done") { dismiss() }
                        .navTarget { dismiss() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .navigationTitle("Controller connected")
            .navigationBarTitleDisplayMode(.inline)
            .navScreen(back: { dismiss() })
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
            Text(text).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
        }
    }
}
