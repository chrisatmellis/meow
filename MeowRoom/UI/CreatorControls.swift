import SwiftUI

struct SliderRow: View {
    let title: String
    @Binding var value: Float
    var range: ClosedRange<Float> = 0...1
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.0f%%", (value - range.lowerBound) / (range.upperBound - range.lowerBound) * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .tint(.accentColor)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ColorRow: View {
    let title: String
    @Binding var color: RGBColor
    var presets: [UInt32] = []

    private var binding: Binding<Color> {
        Binding(get: { color.color },
                set: { newValue in color = RGBColor(uiColor: UIColor(newValue)) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                ColorPicker("", selection: binding, supportsOpacity: false)
                    .labelsHidden()
            }
            if !presets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { hex in
                            let c = RGBColor(hex: hex)
                            Circle()
                                .fill(c.color)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle().strokeBorder(
                                        c == color ? Color.accentColor : Color.white.opacity(0.25),
                                        lineWidth: c == color ? 2.5 : 1)
                                )
                                .onTapGesture { color = c }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Horizontal chips for picking an enum case.
struct ChipPicker<T: Hashable & Identifiable>: View {
    let title: String
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options) { option in
                        let isSelected = option == selection
                        Text(label(option))
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(isSelected
                                               ? Color.accentColor.opacity(0.35)
                                               : Color.white.opacity(0.08))
                            )
                            .overlay(
                                Capsule().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
                            )
                            .onTapGesture { selection = option }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

enum ColorPalettes {
    static let coat: [UInt32] = [
        0x1A1514, 0x3B2F2A, 0x6B5647, 0x8C6E4E, 0xA8845A, 0xC79E68,
        0xD9C39A, 0xF0E7D6, 0x76808C, 0x9AA0A8, 0xC08B45, 0xB0603A,
        0xE0B27A, 0x4A3628, 0x2E3A46, 0xEDE2CE
    ]
    static let eyes: [UInt32] = [
        0xC8A93A, 0xB07A2E, 0xD08A1E, 0x8FA34A, 0x5FA24A, 0x63A05C,
        0x4FA6D6, 0x5C9AD6, 0x7FBFD6, 0x9C8B2E, 0x6E8B3D, 0xAE8ED6,
        0xCFCFCF, 0xB9552E
    ]
    static let skin: [UInt32] = [
        0xE4A9A0, 0xD98F8A, 0xC98A84, 0xB07A74, 0x8A6C74, 0x5B4136,
        0x3A2E2C, 0x1A1414, 0xF0C7BE
    ]
    static let collar: [UInt32] = [
        0xB03A48, 0xC4576A, 0x2B4B6F, 0x3E6B3A, 0x8A7256, 0xE0B441,
        0x5A4A6E, 0x1A1514, 0xF0E7D6
    ]
}
