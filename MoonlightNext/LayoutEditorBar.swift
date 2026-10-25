//
//  LayoutEditorBar.swift
//  MoonLume
//
//  The bar shown while rearranging the on-screen controls: drag hint, Reset, Cancel, and
//  Save for this game or for every game. The dragging itself lives in OnScreenControls.
//

import SwiftUI
import UIKit

@objc final class MNLayoutEditorBar: NSObject {
    @objc static func makeViewController(hasGameLayout: Bool,
                                         onReset: @escaping () -> Void,
                                         onSave: @escaping (_ thisGame: Bool) -> Void,
                                         onCancel: @escaping () -> Void) -> UIViewController {
        let host = UIHostingController(rootView: LayoutEditorBar(hasGameLayout: hasGameLayout,
                                                                 onReset: onReset, onSave: onSave, onCancel: onCancel))
        host.view.backgroundColor = .clear
        host.sizingOptions = .intrinsicContentSize
        return host
    }
}

private struct LayoutEditorBar: View {
    let hasGameLayout: Bool
    let onReset: () -> Void
    let onSave: (Bool) -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Drag controls to move them")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 6)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Button("Reset", action: onReset).buttonStyle(PillButtonStyle())
            Button("Cancel", action: onCancel).buttonStyle(PillButtonStyle())
            Menu {
                Button("Save for this game") { onSave(true) }
                Button(hasGameLayout ? "Save for all games (replaces this game's)" : "Save for all games") { onSave(false) }
            } label: {
                Text("Save")
            }
            .buttonStyle(PillButtonStyle(primary: true))
        }
        .padding(6)
        .background(Capsule().fill(Color.black.opacity(0.78)))
        .overlay(Capsule().strokeBorder(Theme.lineStrong))
        .environment(\.colorScheme, .dark)
    }
}
