import KeyboardShortcuts
import ServiceManagement
import Sparkle
import SwiftUI

struct SettingsView: View {
    let updater: SPUUpdater

    @State private var launchAtLogin = false
    @State private var loginMessage: String?
    @State private var checksForUpdates = false

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }
                if let loginMessage {
                    Text(loginMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                KeyboardShortcuts.Recorder("Toggle window", name: .togglePanel)
            }

            Section {
                Toggle("Automatically check for updates", isOn: $checksForUpdates)
                    .onChange(of: checksForUpdates) { _, enabled in
                        updater.automaticallyChecksForUpdates = enabled
                    }
                LabeledContent("Version", value: Self.version)
            }

            Section {
                Text("Inspired by Hotlist by PQINA.")
                Link("pqina.nl/hotlist", destination: URL(string: "https://pqina.nl/hotlist")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 340)
        .onAppear {
            refreshLoginStatus()
            checksForUpdates = updater.automaticallyChecksForUpdates
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func refreshLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLogin = true
            loginMessage = nil
        case .requiresApproval:
            launchAtLogin = false
            loginMessage = "Allow Hem in System Settings › Login Items."
        default:
            launchAtLogin = false
            loginMessage = nil
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            loginMessage = nil
            refreshLoginStatus()
        } catch {
            loginMessage = error.localizedDescription
            refreshLoginStatus()
        }
    }
}
