// CLIInstaller.swift
// One-click install of the bundled statusbar CLI onto the user's PATH.
// Homebrew installs link the binary themselves; this covers direct downloads.

import SwiftUI

enum CLIInstaller {
    static let linkPath = "/usr/local/bin/statusbar"
    static let brewPaths = ["/opt/homebrew/bin/statusbar", "/usr/local/bin/statusbar"]

    static var bundledCLIPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/statusbar-cli").path
    }

    /// Any resolvable `statusbar` on the standard prefixes counts as installed.
    static var isInstalled: Bool {
        brewPaths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Symlink the bundled CLI into /usr/local/bin, prompting once for admin rights.
    static func install() -> Bool {
        let source = bundledCLIPath
        guard !source.contains("'"), !source.contains("\\"), !source.contains("\"") else { return false }
        let shell = "mkdir -p /usr/local/bin && ln -sf '\(source)' '\(linkPath)'"
        let script = "do shell script \"\(shell.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

struct CLIInstallSection: View {
    @State private var installed = CLIInstaller.isInstalled
    @State private var failed = false

    var body: some View {
        Section("Command Line") {
            LabeledContent("statusbar CLI") {
                if installed {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                } else {
                    Button("Install…") {
                        failed = false
                        installed = CLIInstaller.install() && CLIInstaller.isInstalled
                        failed = !installed
                    }
                }
            }
            Text(
                installed
                    ? "Run statusbar from any terminal — statusbar help shows every command."
                    : failed
                        ? "Install was cancelled or failed — nothing was changed."
                        : "Links the bundled CLI to \(CLIInstaller.linkPath). Asks for your password once."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}
