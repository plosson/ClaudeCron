import SwiftUI

struct TaskCardView: View {
    let task: ClaudeTask
    @State private var breatheOpacity: Double = 0.4
    @State private var isHovered = false
    @State private var isPressed = false

    private var isRunning: Bool {
        task.runs.contains { $0.runStatus == .running }
    }

    private var hasFailed: Bool {
        guard let latest = task.runs.sorted(by: { $0.startedAt > $1.startedAt }).first else { return false }
        return latest.runStatus == .failed
    }

    private var statusColor: Color {
        if isRunning { return .blue }
        if hasFailed { return .red }
        if !task.isEnabled { return .gray }
        return .green
    }

    private var nextRunDate: Date? {
        ScheduleCalculator.nextRuns(for: task.schedule, count: 1).first
    }

    var body: some View {
        HStack(spacing: 0) {
            // Colored left border for running/failed states
            if isRunning || hasFailed {
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [statusColor, statusColor.opacity(0.5)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }

            HStack(alignment: .top, spacing: 10) {
                // Avatar
                PixelAvatarView(config: task.avatarConfig, pixelSize: 3)
                    .opacity(task.isEnabled ? 1.0 : 0.4)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    // Top row: status dot + name + model badge
                    HStack(spacing: 8) {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [statusColor, statusColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 8, height: 8)
                            .opacity(isRunning ? breatheOpacity : 1.0)
                            .animation(
                                isRunning
                                    ? .easeInOut(duration: 1.5).repeatForever(autoreverses: true)
                                    : .default,
                                value: breatheOpacity
                            )
                            .onAppear {
                                if isRunning { breatheOpacity = 1.0 }
                            }
                            .onChange(of: isRunning) { _, running in
                                breatheOpacity = running ? 1.0 : 0.4
                            }

                        Text(task.name)
                            .font(.system(.body, weight: .semibold))
                            .lineLimit(1)

                        Spacer()

                        Text(task.model)
                            .font(.caption2)
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.cyan.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    // Description
                    if !task.taskDescription.isEmpty {
                        Text(task.taskDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    // Schedule + next run
                    HStack {
                        Text(task.schedule.displaySummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let next = nextRunDate {
                            Spacer()
                            Text("Next: \(next, format: .dateTime.month(.abbreviated).day().hour().minute())")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(height: 150, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(isHovered ? 0.12 : 0.06), radius: isHovered ? 12 : 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.secondary.opacity(isHovered ? 0.2 : 0.1), lineWidth: 0.5)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
