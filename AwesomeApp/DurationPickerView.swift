import SwiftUI

struct DurationPickerView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedStringKey("duration_picker_description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVStack(spacing: 12) {
                ForEach(DurationOption.allCases) { option in
                    DurationRow(
                        option: option,
                        isSelected: viewModel.selectedDurationSeconds == option.rawValue,
                        onSelect: {
                            viewModel.selectDuration(option)
                        }
                    )
                }
            }

            Text(LocalizedStringKey("duration_picker_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
}

private struct DurationRow: View {
    let option: DurationOption
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.shortLabel)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(option.spokenLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(option.spokenLabel))
    }
}
