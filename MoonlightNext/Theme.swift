//
//  Theme.swift
//  Moonlight Next
//
//  "Eclipse" design tokens: true-black OLED, one cool accent.
//

import SwiftUI

enum Theme {
    static let ground = Color(hex: 0x000000)
    static let surface = Color(hex: 0x0D0D10)
    static let raised = Color(hex: 0x121216)
    static let line = Color(hex: 0x1C1C20)
    static let lineStrong = Color(hex: 0x26262B)
    static let text = Color(hex: 0xF2F2F2)
    static let textSecondary = Color(hex: 0xC9C9CF)
    static let muted = Color(hex: 0x8A8A90)
    static let accent = Color(hex: 0x8AB4FF)
    static let online = Color(hex: 0x4ADE80)
    static let offline = Color(hex: 0x55555C)

    static let tileRadius: CGFloat = 10
    static let cardRadius: CGFloat = 16

    /// Small caps section label ("COMPUTERS", "VIDEO")
    static func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium))
            .tracking(1.8)
            .foregroundStyle(Color(hex: 0x74747B))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Pill button: filled accent (primary) or hairline outline.
struct PillButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: primary ? .semibold : .regular))
            .foregroundStyle(primary ? Color.black : Color(hex: 0xE4E4E8))
            .padding(.horizontal, primary ? 22 : 18)
            .frame(minHeight: 44)
            .background {
                Capsule().fill(primary ? Theme.accent : Color.clear)
                Capsule().strokeBorder(primary ? Color.clear : Color(hex: 0x2A2A30))
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// 44pt circular hairline icon button.
struct CircleIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(Theme.lineStrong))
        }
        .accessibilityLabel(label)
    }
}
