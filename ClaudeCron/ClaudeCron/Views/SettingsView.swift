import SwiftUI

struct SettingsView: View {
    @AppStorage("use24HourFormat") private var use24HourFormat = false
    @AppStorage("defaultWorkingDirectory") private var defaultWorkingDirectory = "~/Projects"
    @AppStorage("defaultModel") private var defaultModel = "opus"
    @AppStorage("autoScrollLogs") private var autoScrollLogs = true
    @AppStorage("claudeExecutablePath") private var claudeExecutablePath = ""
    @Environment(UpdateService.self) private var updateService
    @State private var detectedPath: String?

    var onClose: (() -> Void)?

    var body: some View {
        Form {
            Section("General") {
                Toggle("24-hour time format", isOn: $use24HourFormat)

                Picker("Default model", selection: $defaultModel) {
                    Text("Opus").tag("opus")
                    Text("Sonnet").tag("sonnet")
                    Text("Haiku").tag("haiku")
                }

                Toggle("Auto-scroll logs", isOn: $autoScrollLogs)
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updateService.automaticallyChecksForUpdates },
                    set: { updateService.automaticallyChecksForUpdates = $0 }
                ))

                Button("Check for Updates Now") {
                    updateService.checkForUpdates()
                }
                .disabled(!updateService.canCheckForUpdates)
            }

            Section("Advanced") {
                TextField("Default working directory", text: $defaultWorkingDirectory)

                HStack {
                    TextField("Claude executable path", text: Binding(
                        get: { claudeExecutablePath.isEmpty ? (detectedPath ?? "") : claudeExecutablePath },
                        set: { claudeExecutablePath = $0 }
                    ))
                    if !claudeExecutablePath.isEmpty {
                        Button(action: { claudeExecutablePath = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear to use auto-detection")
                    }
                }
                if claudeExecutablePath.isEmpty {
                    if detectedPath != nil {
                        Text("Auto-detected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not found")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 420)
        .onAppear {
            detectedPath = ClaudeService.shared.autoDetectClaudePath()
        }
    }
}
