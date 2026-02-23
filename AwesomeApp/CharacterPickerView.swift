import SwiftUI

struct CharacterPickerView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isUploadSheetPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(LocalizedStringKey("character_picker_description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                CharacterSectionHeader(title: LocalizedStringKey("character_section_default"))
                CharacterOptionRow(
                    option: viewModel.dynamicCharacterOption,
                    isSelected: viewModel.isOptionSelected(viewModel.dynamicCharacterOption),
                    action: {
                        viewModel.selectCharacter(option: viewModel.dynamicCharacterOption)
                        dismiss()
                    }
                )

                if viewModel.isLoadingCharacters && viewModel.characterOptionsGlobal.isEmpty && viewModel.characterOptionsUser.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(LocalizedStringKey("character_loading"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
                }

                if viewModel.isAuthenticated {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            CharacterSectionHeader(title: LocalizedStringKey("character_section_mine"))
                            Spacer()
                            Button {
                                isUploadSheetPresented = true
                            } label: {
                                Image(systemName: "tray.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(Text(LocalizedStringKey("character_upload_button_label")))
                        }
                        if viewModel.characterOptionsUser.isEmpty {
                            Text(LocalizedStringKey("character_upload_empty_state"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !viewModel.characterOptionsUser.isEmpty {
                        ForEach(viewModel.characterOptionsUser) { option in
                            CharacterOptionRow(
                                option: option,
                                isSelected: viewModel.isOptionSelected(option),
                                action: {
                                    viewModel.selectCharacter(option: option)
                                    dismiss()
                                }
                            )
                        }
                    }

                    if !viewModel.characterOptionsGlobal.isEmpty {
                        CharacterSectionHeader(title: LocalizedStringKey("character_section_global"))
                        ForEach(viewModel.characterOptionsGlobal) { option in
                            CharacterOptionRow(
                                option: option,
                                isSelected: viewModel.isOptionSelected(option),
                                action: {
                                    viewModel.selectCharacter(option: option)
                                    dismiss()
                                }
                            )
                        }
                    }
                }

                if let error = viewModel.characterLoadErrorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                        Button("Retry") {
                            viewModel.refreshCharacterOptions(force: true)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .task {
            if viewModel.characterOptionsGlobal.isEmpty && viewModel.characterOptionsUser.isEmpty {
                viewModel.refreshCharacterOptions(force: true)
            }
        }
        .sheet(isPresented: $isUploadSheetPresented) {
            CharacterUploadSheet(viewModel: viewModel)
        }
    }
}

private struct CharacterSectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CharacterOptionRow: View {
    let option: CharacterOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                CharacterThumbnailView(url: option.imageURL, status: option.status, isDynamic: option.source == .dynamic)
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else if option.source == .dynamic {
                        Text(LocalizedStringKey("character_dynamic_description"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if option.status == .processing {
                    ProgressView()
                        .controlSize(.small)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: UIRadius.tile, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .disabled(!option.isSelectable)
        .opacity(option.isSelectable ? 1 : 0.5)
    }
}

private struct CharacterThumbnailView: View {
    let url: URL?
    let status: CharacterOption.Status
    let isDynamic: Bool

    var body: some View {
        ZStack {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: UIRadius.chip, style: .continuous))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: UIRadius.chip, style: .continuous)
            .fill(Color(.tertiarySystemBackground))
            .overlay(
                Image(systemName: isDynamic ? "sparkles" : "person.crop.square")
                    .font(.title3)
                    .foregroundStyle(isDynamic ? .teal : .secondary)
            )
    }
}
