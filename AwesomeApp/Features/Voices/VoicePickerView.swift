import SwiftUI

struct VoicePickerView: View {
    @ObservedObject var viewModel: AppViewModel
    @StateObject private var previewController = VoicePreviewController()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            content
        }
        .accessibilityElement(children: .contain)
        .onDisappear {
            previewController.stop()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(LocalizedStringKey("voice_picker_description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            Spacer()
            if viewModel.isLoadingVoices {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingVoices && viewModel.voiceOptions.isEmpty {
            voiceLoadingState
        } else if viewModel.voiceOptions.isEmpty {
            voiceEmptyState
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.voiceOptions) { option in
                    VoiceOptionCard(
                        voice: option,
                        isSelected: option.id == viewModel.selectedVoiceId,
                        isPreviewing: option.id == previewController.currentlyPlayingVoiceId,
                        onSelect: {
                            viewModel.selectVoice(option)
                        },
                        onPreview: {
                            previewController.togglePreview(for: option)
                        }
                    )
                }
            }
        }
    }

    private var voiceLoadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(LocalizedStringKey("voice_picker_loading"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: UIRadius.tile, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var voiceEmptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey("voice_picker_empty"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let error = viewModel.voiceLoadErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(LocalizedStringKey("voice_picker_retry")) {
                viewModel.retryVoiceLoad()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

private struct VoiceOptionCard: View {
    let voice: VoiceOption
    let isSelected: Bool
    let isPreviewing: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(voice.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let description = voice.description, !description.isEmpty {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 12) {
                if let summary = voice.metadataSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if voice.hasPreview {
                    Button {
                        onPreview()
                    } label: {
                        Image(systemName: isPreviewing ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(isPreviewing ? Color.red : Color.accentColor)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIRadius.card, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIRadius.card, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: UIRadius.card, style: .continuous))
        .onTapGesture {
            onSelect()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
