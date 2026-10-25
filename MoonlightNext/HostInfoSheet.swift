//
//  HostInfoSheet.swift
//  Moonlight Next
//
//  A computer's details: addresses, MAC, pairing and what the host software reports,
//  each copyable. Opened from a computer's long-press menu or the host page's ••• menu.
//

import SwiftUI

struct HostInfoSheet: View {
    let host: TemporaryHost
    @Environment(\.dismiss) private var dismiss
    @SwiftUI.State private var copied: String?

    private struct Row {
        let section: String
        let label: String
        let value: String
        init(_ section: String, _ label: String, _ value: String) {
            self.section = section
            self.label = label
            self.value = value
        }
    }

    private var infoRows: [Row] {
        var rows = [
            Row("Computer", "Name", host.name),
            Row("Computer", "Status", host.statusText),
            Row("Computer", "Pairing", host.pairState == .paired ? "Paired" : host.pairState == .unpaired ? "Not paired" : "Unknown"),
        ]
        // Only known once the host has answered (serverinfo)
        if host.state == .online {
            rows.append(Row("Computer", "Host software", host.isNvidiaServerSoftware ? "GeForce Experience" : "Sunshine"))
        }
        if let codecs = host.codecSummary {
            rows.append(Row("Computer", "Host codecs", codecs))
        }
        let addresses: [(String, String?)] = [
            ("Connected via", host.activeAddress),
            ("Local", host.localAddress),
            ("Remote", host.externalAddress),
            ("IPv6", host.ipv6Address),
            ("Added manually", host.address),
        ]
        for case let (label, value?) in addresses where !value.isEmpty {
            rows.append(Row("Network", label, value))
        }
        if let mac = host.mac, !mac.isEmpty, mac != "00:00:00:00:00:00" {
            rows.append(Row("Network", "MAC address", mac.uppercased()))
        }
        rows.append(Row("Network", "HTTPS port", String(host.httpsPort)))
        rows.append(Row("Identity", "Unique ID", host.uuid))
        return rows
    }

    var body: some View {
        let rows = infoRows
        NavigationStack {
            List {
                ForEach(["Computer", "Network", "Identity"], id: \.self) { section in
                    Section {
                        ForEach(rows.filter { $0.section == section }, id: \.label) { row in
                            copyRow(row.label, row.value)
                        }
                    } header: {
                        Theme.label(section)
                    }
                }
                Section {
                } footer: {
                    Text("Tap a row to copy it. Sunshine doesn't report its version or GPU to clients, so they aren't shown.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .navigationTitle(host.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = rows.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
                        copied = "all"
                    } label: {
                        Label(copied == "all" ? "Copied" : "Copy All", systemImage: copied == "all" ? "checkmark" : "doc.on.doc")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        // A controller's B closes it (it opens from a computer's options on a controller too)
        .navScreen(back: { dismiss() })
    }

    private func copyRow(_ label: String, _ value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            copied = label
        } label: {
            HStack(spacing: 12) {
                Text(label).foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: copied == label ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(copied == label ? Theme.online : Theme.muted)
                    .frame(width: 16)
            }
        }
        .listRowBackground(Theme.surface)
        .accessibilityLabel("\(label), \(value)")
        .accessibilityHint("Copies the value")
    }
}

extension TemporaryHost {
    /// The codecs the host can encode, from serverinfo's ServerCodecModeSupport (SCM_* flags
    /// in moonlight-common-c's Limelight.h). Nil before the host has reported them.
    var codecSummary: String? {
        let scm = serverCodecModeSupport
        guard scm != 0 else { return nil }
        var codecs: [String] = []
        if scm & 0x0000_0001 != 0 { codecs.append("H.264") }
        if scm & 0x0000_0100 != 0 { codecs.append(scm & 0x0000_0200 != 0 ? "HEVC (10-bit)" : "HEVC") }
        if scm & 0x0001_0000 != 0 { codecs.append(scm & 0x0002_0000 != 0 ? "AV1 (10-bit)" : "AV1") }
        if scm & 0x007C_0000 != 0 { codecs.append("4:4:4") }
        return codecs.isEmpty ? nil : codecs.joined(separator: ", ")
    }
}
