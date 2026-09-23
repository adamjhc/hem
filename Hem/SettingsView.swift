import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @State private var launchAtLogin = false
    @State private var loginMessage: String?

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
                Text("Inspired by Hotlist by PQINA.")
                Link("pqina.nl/hotlist", destination: URL(string: "https://pqina.nl/hotlist")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 260)
        .onAppear(perform: refreshLoginStatus)
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
