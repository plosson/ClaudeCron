import SwiftUI

struct SettingsView: View {
    @AppStorage("use24HourFormat") private var use24HourFormat = false
    @AppStorage("defaultWorkingDirectory") private var defaultWorkingDirectory = "~/Projects"
    @AppStorage("defaultModel") private var defaultModel = "sonnet"
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
                    TextField("Claude executable path", text: $claudeExecutablePath, prompt: Text(detectedPath ?? "Auto-detect"))
                    if !claudeExecutablePath.isEmpty {
                        Button(action: { claudeExecutablePath = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear to use auto-detection")
                    }
                }
                if claudeExecutablePath.isEmpty, let detected = detectedPath {
                    Text("Detected: \(detected)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if claudeExecutablePath.isEmpty {
                    Text("Auto-detection active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
