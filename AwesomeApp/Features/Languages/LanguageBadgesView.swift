import SwiftUI

struct LanguageBadgeList: View {
    let codes: [String]

    private var inlineScroll: Bool { codes.count > 1 }

    var body: some View {
        Group {
            if codes.isEmpty {
                Text(LocalizedStringKey("project_detail_no_languages"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if inlineScroll {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(codes, id: \.self) { code in
                                LanguageChip(languageCode: code)
                            }
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                    }
                    .padding(.horizontal, -6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .applyScrollClipDisabled()
                } else {
                    BadgeWrapLayout(spacing: 10, lineSpacing: 8) {
                        ForEach(codes, id: \.self) { code in
                            LanguageChip(languageCode: code)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.trailing, 12)
    }
}

struct LanguageChip: View {
    let languageCode: String
    var isSelected: Bool = false

    private var presentation: LanguagePresentation { LanguagePresentation(languageCode: languageCode) }

    var body: some View {
        HStack(spacing: 8) {
            Text(presentation.flag)
            Text(presentation.shortLabel)
                .font(.footnote.weight(.semibold))
        }
        .textCase(.uppercase)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(presentation.gradient)
        )
        .foregroundStyle(Color.white)
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
    }

    private var borderColor: Color { isSelected ? Color.accentColor : Color.white.opacity(0.25) }
    private var borderWidth: CGFloat { isSelected ? 2 : 1 }
}

struct LanguagePresentation {
    let flag: String
    let shortLabel: String
    let gradient: LinearGradient

    init(languageCode: String) {
        let normalized = languageCode.lowercased()
        let base = normalized.split(separator: "-").first.map(String.init) ?? normalized
        let region = LanguagePresentation.regionOverrides[base] ?? base
        self.flag = LanguagePresentation.flagEmoji(for: region) ?? "🌐"
        self.shortLabel = (base.isEmpty ? "lang" : base).uppercased()

        let accent: Color
        switch base {
        case "en": accent = .blue
        case "es": accent = .orange
        case "ru": accent = .purple
        case "fr": accent = .pink
        case "de": accent = .teal
        case "pt": accent = .green
        default: accent = .gray
        }
        self.gradient = LinearGradient(colors: [accent.opacity(0.9), accent.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private static let regionOverrides: [String: String] = [
        "en": "us",
        "es": "es",
        "ru": "ru",
        "fr": "fr",
        "de": "de",
        "pt": "pt"
    ]

    private static func flagEmoji(for regionCode: String) -> String? {
        let trimmed = regionCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count == 2 else { return nil }
        var scalars = String.UnicodeScalarView()
        for scalar in trimmed.unicodeScalars {
            guard let flagScalar = UnicodeScalar(127397 + scalar.value) else { return nil }
            scalars.append(flagScalar)
        }
        return String(scalars)
    }
}

struct BadgeWrapLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        layout(subviews: subviews, proposal: proposal).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let layoutInfo = layout(subviews: subviews, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
        for (index, frame) in layoutInfo.frames.enumerated() where index < subviews.count {
            let origin = CGPoint(x: bounds.minX + frame.origin.x, y: bounds.minY + frame.origin.y)
            subviews[index].place(at: origin, proposal: ProposedViewSize(frame.size))
        }
    }

    private func layout(subviews: Subviews, proposal: ProposedViewSize) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var frames: [CGRect] = []
        var requiredWidth: CGFloat = 0

        for subview in subviews {
            let fitting = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: proposal.height))
            if currentX > 0 && currentX + fitting.width > maxWidth && maxWidth.isFinite {
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }

            frames.append(CGRect(origin: CGPoint(x: currentX, y: currentY), size: fitting))
            currentX += fitting.width + spacing
            lineHeight = max(lineHeight, fitting.height)
            requiredWidth = max(requiredWidth, min(maxWidth, currentX))
        }

        let totalHeight = currentY + lineHeight
        let finalWidth = maxWidth.isFinite ? maxWidth : requiredWidth
        return (CGSize(width: finalWidth, height: totalHeight), frames)
    }
}

// Allows capsule edges to render fully at the start/end of horizontal scroll containers.
private extension View {
    @ViewBuilder
    func applyScrollClipDisabled() -> some View {
        if #available(iOS 17.0, *) {
            self.scrollClipDisabled()
        } else {
            self
        }
    }
}
