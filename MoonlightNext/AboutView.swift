//
//  AboutView.swift
//  Moonlight Next
//
//  Version, where MoonLume comes from and the licences it ships under. Reached from Settings.
//

import SwiftUI

struct AboutView: View {
    static let repoURL = URL(string: "https://github.com/doombadroid/moonlight-next")!
    static let gplURL = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!
    static let sideStoreSource = "https://raw.githubusercontent.com/doombadroid/moonlight-next/master/sidestore-source.json"

    @SwiftUI.State private var copiedSource = false
    @Environment(\.openURL) private var openURL

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (build \(build))"
    }

    private let credits: [(name: String, license: String, url: String, note: String)] = [
        ("Moonlight for iOS", "GPLv3", "https://github.com/moonlight-stream/moonlight-ios",
         "MoonLume is a fork of it: streaming, pairing and input."),
        ("moonlight-common-c", "GPLv3", "https://github.com/moonlight-stream/moonlight-common-c",
         "The streaming protocol."),
        ("VoidLink", "GPLv3", "https://github.com/TrueZhuangJia/moonlight-ios-NativeMultiTouchPassthrough",
         "Another Moonlight fork, used as a reference; some code is adapted from it and marked in the source."),
        ("SDL2", "zlib", "https://www.libsdl.org", "Audio output."),
        ("Opus", "BSD", "https://opus-codec.org", "Audio decoding."),
        ("FFmpeg", "LGPL 2.1+", "https://ffmpeg.org", "Video parsing."),
        ("OpenSSL", "Apache 2.0", "https://www.openssl.org", "Pairing and encryption."),
    ]

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.accent)
                    Text("MoonLume").font(.system(size: 22, weight: .semibold))
                    Text(version)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .textSelection(.enabled)
                    Text("Game streaming for Sunshine and GeForce Experience hosts, built for the iPhone Duo.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                Link(destination: Self.repoURL) {
                    row("Source code", detail: "github.com/doombadroid/moonlight-next", icon: "chevron.left.forwardslash.chevron.right")
                }
                .navTarget { openURL(Self.repoURL) }
                Button(action: copySideStoreSource) {
                    row("SideStore source", detail: copiedSource ? "Copied" : "Copy URL", icon: copiedSource ? "checkmark" : "doc.on.doc")
                }
                .navTarget(activate: copySideStoreSource)
            } header: {
                Theme.label("Get MoonLume")
            } footer: {
                Text("Add the copied URL in SideStore under Sources to get updates.")
            }

            Section {
                ForEach(credits, id: \.name) { credit in
                    Link(destination: URL(string: credit.url)!) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(credit.name).foregroundStyle(Theme.text)
                                Spacer()
                                Text(credit.license)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Theme.accent)
                            }
                            Text(credit.note).font(.system(size: 13)).foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 2)
                    }
                    .navTarget { openURL(URL(string: credit.url)!) }
                }
            } header: {
                Theme.label("Credits and licences")
            } footer: {
                Link("MoonLume is free software under the GNU General Public License v3.",
                     destination: Self.gplURL)
                    .navTarget { openURL(Self.gplURL) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func copySideStoreSource() {
        UIPasteboard.general.string = Self.sideStoreSource
        copiedSource = true
    }

    private func row(_ title: String, detail: String, icon: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.text)
            Spacer()
            Text(detail).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1)
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
    }
}
