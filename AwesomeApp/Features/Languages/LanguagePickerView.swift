import SwiftUI

struct LanguagePickerView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedStringKey("language_picker_multi_explainer"))
                .font(.callout)
                .foregroundStyle(.primary)

            Text(LocalizedStringKey("language_picker_description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            AllLanguagesRow(
                isSelected: viewModel.hasAllLanguagesSelected,
                toggle: viewModel.toggleAllLanguages
            )

            ForEach(TargetLanguage.allCases) { language in
                LanguageRow(
                    language: language,
                    isSelected: viewModel.isLanguageSelected(language),
                    toggle: { viewModel.toggleLanguage(language) }
                )
            }

            Text(LocalizedStringKey("language_picker_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
}

private struct LanguageRow: View {
    let language: TargetLanguage
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button {
            toggle()
        } label: {
            HStack(spacing: 12) {
                Text(language.flag)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.label)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(language.rawValue.uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.7))
                    .accessibilityLabel(isSelected ? "Selected" : "Not selected")
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(isSelected ? "Tap to remove language" : "Tap to add language"))
    }
}

private struct AllLanguagesRow: View {
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey("language_picker_select_all"))
                        .font(.body.weight(.semibold))
                    Text(LocalizedStringKey("language_summary_all"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.7))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey("language_picker_select_all")))
        .accessibilityHint(Text(isSelected ? "Tap to reset to default language" : "Tap to select all languages"))
    }
}
