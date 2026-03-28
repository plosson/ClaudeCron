import SwiftUI

struct AvatarPickerView: View {
    @Binding var config: AvatarConfig
    var onReset: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            // Large preview
            PixelAvatarView(config: config, pixelSize: 5)
                .padding(.top, 8)

            // Hair style picker (mini avatars)
            traitSection("HAIR STYLE") {
                HStack(spacing: 6) {
                    ForEach(0..<AvatarConfig.hairStyleCount, id: \.self) { style in
                        let preview = configWith(hairStyle: style)
                        Button(action: { config.hairStyle = style }) {
                            VStack(spacing: 2) {
                                PixelAvatarView(config: preview, pixelSize: 2)
                                Text(AvatarConfig.hairStyleNames[style])
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(config.hairStyle == style ? Color.accentColor.opacity(0.15) : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(config.hairStyle == style ? Color.accentColor : .clear)
                        )
                    }
                }
            }

            // Color pickers
            colorRow("HAIR COLOR", colors: AvatarPalette.hairColors, selection: $config.hairColor)
            colorRow("SKIN TONE", colors: AvatarPalette.skinTones, selection: $config.skinTone)

            // Glasses toggle
            traitSection("ACCESSORIES") {
                Toggle("Glasses", isOn: $config.hasGlasses)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            colorRow("SHIRT", colors: AvatarPalette.shirtColors, selection: $config.shirtColor)
            colorRow("PANTS", colors: AvatarPalette.pantsColors, selection: $config.pantsColor)
            colorRow("SHOES", colors: AvatarPalette.shoeColors, selection: $config.shoeColor)

            // Actions
            HStack {
                Button("Randomize") {
                    config = .generate(from: UUID().uuidString)
                }
                .controlSize(.small)

                if let onReset {
                    Button("Reset") {
                        onReset()
                    }
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: - Helpers

    private func configWith(hairStyle: Int) -> AvatarConfig {
        var c = config
        c.hairStyle = hairStyle
        return c
    }

    private func traitSection<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .tracking(0.5)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func colorRow(_ label: String, colors: [Color], selection: Binding<Int>) -> some View {
        traitSection(label) {
            HStack(spacing: 6) {
                ForEach(0..<colors.count, id: \.self) { i in
                    Circle()
                        .fill(colors[i])
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    selection.wrappedValue == i ? Color.primary : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    selection.wrappedValue == i ? Color.white : Color.clear,
                                    lineWidth: 1
                                )
                                .padding(2)
                        )
                        .onTapGesture { selection.wrappedValue = i }
                        .contentShape(Circle())
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var config = AvatarConfig.generate(from: "test")
    AvatarPickerView(config: $config, onReset: { config = .generate(from: "test") })
}
