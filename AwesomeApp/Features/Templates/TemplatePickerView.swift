import SwiftUI

struct TemplatePickerView: View {
    @ObservedObject var viewModel: AppViewModel
    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(LocalizedStringKey("template_picker_description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if viewModel.isLoadingTemplates && viewModel.templateOptions.isEmpty {
                    loadingState
                } else if viewModel.templateOptions.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, alignment: .center, spacing: 12) {
                        ForEach(viewModel.templateOptions) { option in
                            TemplateCardView(
                                option: option,
                                isSelected: option.id == viewModel.selectedTemplateId
                            ) {
                                viewModel.selectTemplate(option)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .onAppear {
            if viewModel.templateOptions.isEmpty {
                viewModel.refreshTemplateOptions(force: true)
            }
        }
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(LocalizedStringKey("template_picker_loading"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("template_picker_empty"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let error = viewModel.templateLoadErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(LocalizedStringKey("template_picker_retry")) {
                viewModel.retryTemplateLoad()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TemplateCardView: View {
    let option: TemplateOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                TemplatePreviewImage(url: option.previewImageURL)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if let metadata = option.metadataSummary {
                        Text(metadata)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: UIRadius.tile, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIRadius.tile, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct TemplatePreviewImage: View {
    let url: URL?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: UIRadius.chip, style: .continuous)
                .fill(Color(.secondarySystemBackground))
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: "film")
                            .resizable()
                            .scaledToFit()
                            .padding(16)
                            .foregroundStyle(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: UIRadius.chip, style: .continuous))
            } else {
                Image(systemName: "film")
                    .resizable()
                    .scaledToFit()
                    .padding(16)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .clipped()
    }
}
