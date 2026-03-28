import SwiftUI

// MARK: - Avatar Configuration

struct AvatarConfig: Codable, Equatable {
    var hairStyle: Int = 0
    var hairColor: Int = 0
    var skinTone: Int = 0
    var hasGlasses: Bool = false
    var shirtColor: Int = 0
    var pantsColor: Int = 0
    var shoeColor: Int = 0

    static let hairStyleCount = 8
    static let hairColorCount = 6
    static let skinToneCount = 5
    static let shirtColorCount = 8
    static let pantsColorCount = 6
    static let shoeColorCount = 4

    static let hairStyleNames = [
        "Short", "Long", "Cap", "Beanie", "Mohawk", "Afro", "Side Swept", "Bald"
    ]

    /// Generate a deterministic avatar from a seed string
    static func generate(from seed: String) -> AvatarConfig {
        var h = seed.utf8.reduce(0) { (($0 &<< 5) &- $0) &+ Int($1) }
        func next(_ max: Int) -> Int {
            h = h &* 1103515245 &+ 12345
            return abs(h / 65536) % max
        }
        return AvatarConfig(
            hairStyle: next(hairStyleCount),
            hairColor: next(hairColorCount),
            skinTone: next(skinToneCount),
            hasGlasses: next(3) == 0,
            shirtColor: next(shirtColorCount),
            pantsColor: next(pantsColorCount),
            shoeColor: next(shoeColorCount)
        )
    }
}

// MARK: - Color Palette

enum AvatarPalette {
    static let skinTones: [Color] = [
        Color(red: 1.00, green: 0.87, blue: 0.75),
        Color(red: 0.94, green: 0.76, blue: 0.60),
        Color(red: 0.82, green: 0.64, blue: 0.48),
        Color(red: 0.70, green: 0.49, blue: 0.35),
        Color(red: 0.55, green: 0.36, blue: 0.25),
    ]

    static let hairColors: [Color] = [
        Color(red: 0.25, green: 0.15, blue: 0.10),
        Color(red: 0.10, green: 0.10, blue: 0.10),
        Color(red: 0.85, green: 0.70, blue: 0.40),
        Color(red: 0.70, green: 0.25, blue: 0.15),
        Color(red: 0.60, green: 0.55, blue: 0.50),
        Color(red: 0.30, green: 0.50, blue: 0.80),
    ]

    static let shirtColors: [Color] = [
        Color(red: 0.90, green: 0.30, blue: 0.30),
        Color(red: 0.30, green: 0.55, blue: 0.90),
        Color(red: 0.30, green: 0.75, blue: 0.45),
        Color(red: 0.95, green: 0.75, blue: 0.20),
        Color(red: 0.65, green: 0.35, blue: 0.80),
        Color(red: 0.95, green: 0.55, blue: 0.20),
        Color(red: 0.25, green: 0.70, blue: 0.70),
        Color(red: 0.90, green: 0.45, blue: 0.60),
    ]

    static let pantsColors: [Color] = [
        Color(red: 0.20, green: 0.25, blue: 0.40),
        Color(red: 0.20, green: 0.20, blue: 0.20),
        Color(red: 0.50, green: 0.50, blue: 0.50),
        Color(red: 0.45, green: 0.35, blue: 0.25),
        Color(red: 0.35, green: 0.40, blue: 0.30),
        Color(red: 0.35, green: 0.50, blue: 0.70),
    ]

    static let shoeColors: [Color] = [
        Color(red: 0.15, green: 0.15, blue: 0.15),
        Color(red: 0.50, green: 0.35, blue: 0.20),
        Color(red: 0.90, green: 0.90, blue: 0.90),
        Color(red: 0.80, green: 0.25, blue: 0.25),
    ]
}

// MARK: - Pixel Avatar View

struct PixelAvatarView: View {
    let config: AvatarConfig
    var pixelSize: CGFloat = 3

    private let cols = 11
    private let rows = 15

    private var skin: Color {
        AvatarPalette.skinTones[config.skinTone % AvatarPalette.skinTones.count]
    }
    private var hair: Color {
        AvatarPalette.hairColors[config.hairColor % AvatarPalette.hairColors.count]
    }
    private var shirt: Color {
        AvatarPalette.shirtColors[config.shirtColor % AvatarPalette.shirtColors.count]
    }
    private var pants: Color {
        AvatarPalette.pantsColors[config.pantsColor % AvatarPalette.pantsColors.count]
    }
    private var shoes: Color {
        AvatarPalette.shoeColors[config.shoeColor % AvatarPalette.shoeColors.count]
    }

    var body: some View {
        Canvas { context, _ in
            let grid = buildGrid()
            for y in 0..<rows {
                for x in 0..<cols {
                    guard let color = grid[y][x] else { continue }
                    let rect = CGRect(
                        x: CGFloat(x) * pixelSize,
                        y: CGFloat(y) * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(cols) * pixelSize, height: CGFloat(rows) * pixelSize)
    }

    // MARK: - Grid Assembly

    private func buildGrid() -> [[Color?]] {
        var grid = Array(repeating: Array<Color?>(repeating: nil, count: cols), count: rows)

        func set(_ pixels: [(Int, Int)], _ color: Color) {
            for (x, y) in pixels where x >= 0 && x < cols && y >= 0 && y < rows {
                grid[y][x] = color
            }
        }

        // Face
        set([
            (4, 2), (5, 2), (6, 2),
            (3, 3), (5, 3), (7, 3),
            (3, 4), (4, 4), (5, 4), (6, 4), (7, 4),
            (3, 5), (4, 5), (6, 5), (7, 5),
        ], skin)

        // Eyes
        set([(4, 3), (6, 3)], Color(white: 0.15))

        // Mouth
        set([(5, 5)], Color(red: 0.75, green: 0.42, blue: 0.42))

        // Shirt
        set([
            (4, 6), (5, 6), (6, 6),
            (3, 7), (4, 7), (5, 7), (6, 7), (7, 7),
            (2, 8), (3, 8), (4, 8), (5, 8), (6, 8), (7, 8), (8, 8),
            (2, 9), (3, 9), (4, 9), (5, 9), (6, 9), (7, 9), (8, 9),
            (3, 10), (4, 10), (5, 10), (6, 10), (7, 10),
        ], shirt)

        // Arms
        set([(1, 9), (9, 9)], skin)

        // Pants
        set([
            (4, 11), (5, 11), (6, 11),
            (3, 12), (4, 12), (6, 12), (7, 12),
            (3, 13), (4, 13), (6, 13), (7, 13),
        ], pants)

        // Shoes
        set([(3, 14), (4, 14), (6, 14), (7, 14)], shoes)

        // Hair (drawn on top of face)
        set(hairPixels(style: config.hairStyle % AvatarConfig.hairStyleCount), hair)

        // Glasses (drawn on top of everything at eye level)
        if config.hasGlasses {
            set([(3, 3), (5, 3), (7, 3)], Color(white: 0.25))
        }

        return grid
    }

    // MARK: - Hair Styles

    private func hairPixels(style: Int) -> [(Int, Int)] {
        switch style {
        case 0: // Short
            return [
                (4, 0), (5, 0), (6, 0),
                (3, 1), (4, 1), (5, 1), (6, 1), (7, 1),
                (2, 2), (3, 2), (7, 2), (8, 2),
                (2, 3), (8, 3),
            ]
        case 1: // Long
            return [
                (4, 0), (5, 0), (6, 0),
                (3, 1), (4, 1), (5, 1), (6, 1), (7, 1),
                (2, 2), (3, 2), (7, 2), (8, 2),
                (2, 3), (8, 3),
                (2, 4), (8, 4),
                (2, 5), (8, 5),
            ]
        case 2: // Cap
            return [
                (2, 0), (3, 0), (4, 0), (5, 0), (6, 0), (7, 0), (8, 0), (9, 0),
                (3, 1), (4, 1), (5, 1), (6, 1), (7, 1),
                (3, 2), (7, 2),
            ]
        case 3: // Beanie
            return [
                (4, 0), (5, 0), (6, 0),
                (3, 1), (4, 1), (5, 1), (6, 1), (7, 1),
                (2, 2), (3, 2), (4, 2), (5, 2), (6, 2), (7, 2), (8, 2),
            ]
        case 4: // Mohawk
            return [
                (5, 0),
                (4, 1), (5, 1), (6, 1),
                (5, 2),
            ]
        case 5: // Afro
            return [
                (3, 0), (4, 0), (5, 0), (6, 0), (7, 0),
                (2, 0), (8, 0),
                (1, 1), (2, 1), (3, 1), (4, 1), (5, 1), (6, 1), (7, 1), (8, 1), (9, 1),
                (1, 2), (2, 2), (3, 2), (7, 2), (8, 2), (9, 2),
                (1, 3), (2, 3), (8, 3), (9, 3),
            ]
        case 6: // Side Swept
            return [
                (4, 0), (5, 0), (6, 0), (7, 0),
                (3, 1), (4, 1), (5, 1), (6, 1), (7, 1), (8, 1),
                (2, 2), (3, 2), (7, 2), (8, 2), (9, 2),
                (2, 3), (8, 3), (9, 3),
            ]
        case 7: // Bald
            return []
        default:
            return []
        }
    }
}

// MARK: - Preview

#Preview("Avatar Gallery") {
    let seeds = ["task-1", "cleanup", "daily-report", "monitor", "backup", "deploy", "test-runner", "lint"]
    HStack(spacing: 16) {
        ForEach(seeds, id: \.self) { seed in
            VStack(spacing: 4) {
                PixelAvatarView(config: .generate(from: seed), pixelSize: 4)
                Text(seed)
                    .font(.caption2)
            }
        }
    }
    .padding()
}

#Preview("Hair Styles") {
    HStack(spacing: 12) {
        ForEach(0..<AvatarConfig.hairStyleCount, id: \.self) { style in
            VStack(spacing: 4) {
                PixelAvatarView(
                    config: AvatarConfig(hairStyle: style, hairColor: 0, skinTone: 1, shirtColor: 1, pantsColor: 0),
                    pixelSize: 4
                )
                Text(AvatarConfig.hairStyleNames[style])
                    .font(.caption2)
            }
        }
    }
    .padding()
}
