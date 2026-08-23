import SwiftUI

struct DotMatrixText: View {
    let text: String
    var dotSize: CGFloat = 2.5
    var dotSpacing: CGFloat = 1.5
    var color: Color = .white
    var inactiveColor: Color = .clear

    var body: some View {
        let characters = Array(text)
        let glyphWidth = dotSize * 5 + dotSpacing * 4
        let glyphHeight = dotSize * 7 + dotSpacing * 6
        let characterSpacing = dotSpacing * 2.4
        let totalWidth = glyphWidth * CGFloat(characters.count)
            + characterSpacing * CGFloat(max(0, characters.count - 1))

        Canvas { context, _ in
            for (characterIndex, character) in characters.enumerated() {
                let rows = DotMatrixGlyphs.pattern(for: character)
                let characterX = CGFloat(characterIndex) * (glyphWidth + characterSpacing)

                for row in 0..<7 {
                    for column in 0..<5 {
                        let isActive = rows[row][column] == "1"
                        if !isActive && inactiveColor == .clear { continue }
                        let rect = CGRect(
                            x: characterX + CGFloat(column) * (dotSize + dotSpacing),
                            y: CGFloat(row) * (dotSize + dotSpacing),
                            width: dotSize,
                            height: dotSize
                        )
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(isActive ? color : inactiveColor)
                        )
                    }
                }
            }
        }
        .frame(width: totalWidth, height: glyphHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

struct DotMatrixProgressBar: View {
    let progress: Double
    private let segmentCount = 20

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<segmentCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(color(for: index))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 5)
        .accessibilityLabel("剩余额度进度")
        .accessibilityValue("\(Int(progress * 100))%")
    }

    private func color(for index: Int) -> Color {
        let isFilled = Double(index + 1) / Double(segmentCount) <= progress
        if isFilled {
            return Color(red: 0.30, green: 0.96, blue: 0.67)
        }
        return Color.white.opacity(0.14)
    }
}

private enum DotMatrixGlyphs {
    private static let blank = ["00000", "00000", "00000", "00000", "00000", "00000", "00000"]

    static func pattern(for character: Character) -> [[Character]] {
        let key = Character(String(character).uppercased())
        return (patterns[key] ?? patterns["?"] ?? blank).map(Array.init)
    }

    private static let patterns: [Character: [String]] = [
        " ": blank,
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
        "6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
        "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
        "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
        "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
        "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
        "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
        "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
        "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
        "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
        "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
        "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
        "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
        "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
        "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
        "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
        "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
        "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
        "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
        "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
        "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
        "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
        "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
        "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
        "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
        "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
        "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
        "%": ["11001", "11010", "00010", "00100", "01000", "01011", "10011"],
        "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
        ":": ["00000", "00100", "00100", "00000", "00100", "00100", "00000"],
        ".": ["00000", "00000", "00000", "00000", "00000", "00110", "00110"],
        "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
        "?": ["01110", "10001", "00001", "00010", "00100", "00000", "00100"]
    ]
}
