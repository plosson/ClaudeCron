import SwiftUI

struct SettingsView: View {
    @AppStorage("use24HourFormat") private var use24HourFormat = false
    @AppStorage("defaultWorkingDirectory") private var defaultWorkingDirectory = "~/Projects"
    @AppStorage("defaultModel") private var defaultModel = "sonnet"
    @AppStorage("autoScrollLogs") private var autoScrollLogs = true
    @AppStorage("defaultTerminal") private var defaultTerminal = "Terminal"

    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title2.bold())
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox {
                        Toggle("24-Hour Time Format", isOn: $use24HourFormat)
                        Text("Use 24-hour format (14:30) instead of 12-hour (2:30 PM)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    GroupBox("Advanced") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Default Working Directory").font(.subheadline.bold())
                                TextField("~/Projects", text: $defaultWorkingDirectory)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Default Model").font(.subheadline.bold())
                                Picker("", selection: $defaultModel) {
                                    Text("Opus").tag("opus")
                                    Text("Sonnet").tag("sonnet")
                                    Text("Haiku").tag("haiku")
                                }
                            }

                            Toggle(isOn: $autoScrollLogs) {
                                VStack(alignment: .leading) {
                                    Text("Auto-scroll Logs")
                                    Text("Automatically scroll to bottom of logs during live viewing")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Default Terminal/IDE").font(.subheadline.bold())
                                Picker("", selection: $defaultTerminal) {
                                    Text("Terminal").tag("Terminal")
                                    Text("iTerm").tag("iTerm")
                                }
                                Text("Choose which application to use when opening Claude sessions")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
}
