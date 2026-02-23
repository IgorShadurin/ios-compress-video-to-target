import SwiftUI
import AVKit
import UIKit

struct ProjectListView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.projectSummaries.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(viewModel.projectSummaries) { project in
                            Button {
                                viewModel.openProjectDetail(project)
                            } label: {
                                ProjectSummaryRow(project: project)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { viewModel.refreshProjectSummaries(force: true) }
                }
            }
            .navigationTitle(Text(LocalizedStringKey("projects_title")))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.large)
                    }
                    .accessibilityLabel(Text(LocalizedStringKey("projects_close")))
                }
                ToolbarItem(placement: .primaryAction) {
                    if viewModel.isLoadingProjects {
                        ProgressView()
                    } else {
                        Button {
                            viewModel.refreshProjectSummaries(force: true)
                        } label: {
                            Image(systemName: "arrow.clockwise" )
                        }
                        .accessibilityLabel(Text(LocalizedStringKey("projects_refresh")))
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if viewModel.isLoadingProjects && !viewModel.projectSummaries.isEmpty {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .padding(.bottom, 12)
                }
            }
            .sheet(isPresented: $viewModel.isProjectDetailPresented) {
                ProjectDetailView(
                    detail: viewModel.selectedProjectDetail,
                    isLoading: viewModel.isProjectDetailPresented && viewModel.isLoadingProjectDetail,
                    errorMessage: viewModel.projectDetailError,
                    player: viewModel.projectDetailPlayer,
                    playerStatus: viewModel.projectDetailPlayerStatus,
                    downloadPhase: viewModel.projectDetailDownloadPhase,
                    defaultVoiceName: viewModel.defaultVoiceName,
                    selectedLanguage: viewModel.selectedProjectDetailLanguage,
                    onSelectLanguage: viewModel.selectProjectDetailLanguage,
                    onRefresh: viewModel.reloadSelectedProjectDetail,
                    onClose: viewModel.dismissProjectDetail,
                    onDownload: {
                        Task {
                            await viewModel.downloadSelectedProjectVideo()
                        }
                    },
                    downloadProgress: viewModel.downloadProgress,
                    onDownloadAll: {
                        Task {
                            await viewModel.downloadAllProjectVideos()
                        }
                    }
                )
            }
        }
        .task {
            viewModel.refreshProjectSummaries(force: true)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey("projects_empty_title"))
                .font(.headline)
            Text(LocalizedStringKey("projects_empty_caption"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                viewModel.refreshProjectSummaries(force: true)
            } label: {
                Label {
                    Text(LocalizedStringKey("projects_refresh"))
                } icon: {
                    Image(systemName: "arrow.clockwise" )
                }
            }
        }
        .padding()
    }
}

struct ProjectSummaryRow: View {
    let project: AppViewModel.ProjectSummary

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(project.status.tintColor)
                .frame(width: 10, height: 10)
            Text(project.title)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(project.title)
            + Text(", ")
            + Text(project.status.localizedKey)
        )
    }
}

struct ProjectDetailView: View {
    let detail: AppViewModel.ProjectDetail?
    let isLoading: Bool
    let errorMessage: String?
    let player: AVPlayer?
    let playerStatus: PlayerStatus
    let downloadPhase: AppViewModel.DownloadPhase
    let defaultVoiceName: String
    let selectedLanguage: String?
    let onSelectLanguage: (String) -> Void
    let onRefresh: () -> Void
    let onClose: () -> Void
    let onDownload: () -> Void
    let downloadProgress: DownloadProgress?
    let onDownloadAll: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var didCopyProjectID = false

    var body: some View {
        NavigationStack {
            content
                .padding()
                .navigationTitle(Text(LocalizedStringKey("project_detail_title")))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: close) {
                            Image(systemName: "xmark.circle.fill")
                                .imageScale(.large)
                        }
                        .accessibilityLabel(Text(LocalizedStringKey("project_detail_close")))
                    }
                    ToolbarItem(placement: .primaryAction) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Button(action: onRefresh) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .accessibilityLabel(Text(LocalizedStringKey("project_detail_refresh")))
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && detail == nil {
            VStack(spacing: 16) {
                ProgressView()
                Text(LocalizedStringKey("project_detail_loading"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if let detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(for: detail)
                    statusSection(for: detail)
                    creationMetadataSection(for: detail)
                    videoSection(for: detail)
                    promptSection(for: detail)
                    metadataSection(for: detail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        } else if let errorMessage {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(LocalizedStringKey("project_detail_error_title"))
                    .font(.headline)
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button(action: onRefresh) {
                    Label {
                        Text(LocalizedStringKey("project_detail_retry"))
                    } icon: {
                        Image(systemName: "arrow.clockwise" )
                    }
                }
            }
            .padding()
        } else {
            Text(LocalizedStringKey("project_detail_empty"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(for detail: AppViewModel.ProjectDetail) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(detail.title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
    }

    private func statusSection(for detail: AppViewModel.ProjectDetail) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(detail.status.tintColor)
                .frame(width: 14, height: 14)
            Text(detail.status.localizedKey)
                .font(.headline)
            Spacer()
        }
    }

    @ViewBuilder
    private func creationMetadataSection(for detail: AppViewModel.ProjectDetail) -> some View {
        let badges = metadataBadges(for: detail)
        if badges.isEmpty {
            EmptyView()
        } else {
            BadgeWrapLayout(spacing: 8, lineSpacing: 8) {
                ForEach(badges) { badge in
                    MetadataBadgeView(badge: badge)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 12)
        }
    }

    private func promptSection(for detail: AppViewModel.ProjectDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey("project_detail_prompt_label"))
                .font(.subheadline.weight(.semibold))
            if let prompt = detail.prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.body)
                    .multilineTextAlignment(.leading)
            } else {
                Text(LocalizedStringKey("project_detail_no_prompt"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

private func languagesSection(for detail: AppViewModel.ProjectDetail) -> some View {
    let isSelectable = detail.status.isComplete && detail.languages.count > 1
    let playableCodes: Set<String> = Set(detail.languageVariants.compactMap { variant in
        variant.finalVideoURL != nil ? variant.languageCode : nil
    })

    return VStack(alignment: .leading, spacing: 8) {
        Text(LocalizedStringKey("project_detail_languages_label"))
            .font(.subheadline.weight(.semibold))
        if isSelectable {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(detail.languages, id: \.self) { code in
                        let isSelected = code == selectedLanguage
                        let isPlayable = playableCodes.isEmpty || playableCodes.contains(code)

                        Button {
                            onSelectLanguage(code)
                        } label: {
                            LanguageChip(languageCode: code, isSelected: isSelected)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isPlayable)
                        .opacity(isPlayable ? 1 : 0.35)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 6) // avoid clipping the leading/trailing capsules when scroll view clips
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, -6) // compensate so visual alignment matches surrounding elements
            .scrollIndicators(.hidden)
            .applyScrollClipDisabled()
        } else {
            LanguageBadgeList(codes: detail.languages)
        }
    }
}

private func metadataSection(for detail: AppViewModel.ProjectDetail) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Text(LocalizedStringKey("project_detail_metadata_title"))
            .font(.subheadline.weight(.semibold))

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey("project_detail_metadata_id"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail.id)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Button {
                UIPasteboard.general.string = detail.id
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                didCopyProjectID = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await MainActor.run { didCopyProjectID = false }
                }
            } label: {
                Image(systemName: didCopyProjectID ? "checkmark.seal.fill" : "doc.on.doc")
                    .symbolRenderingMode(.hierarchical)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(didCopyProjectID ? "project_detail_copied" : "project_detail_copy"))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey("project_detail_metadata_created"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatted(date: detail.createdAt))
                    .font(.callout.weight(.medium))
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

    private func videoSection(for detail: AppViewModel.ProjectDetail) -> some View {
        Group {
            if detail.finalVideoURL(for: selectedLanguage) != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text(LocalizedStringKey("project_detail_video_label"))
                        .font(.subheadline.weight(.semibold))

                    Group {
                        if playerStatus == .ready, let player {
                            VideoPlayer(player: player)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                                VStack(spacing: 10) {
                                    ProgressView()
                                    Text(LocalizedStringKey("project_detail_video_loading"))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .aspectRatio(9/16, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .onAppear {
                        if playerStatus == .ready {
                            player?.play()
                        }
                    }
                    .onChange(of: playerStatus) { status in
                        if status == .ready {
                            player?.play()
                        }
                    }
                    .onDisappear {
                        player?.pause()
                    }

                    languagesSection(for: detail)

                    DownloadSectionView(
                        downloadPhase: downloadPhase,
                        downloadProgress: downloadProgress,
                        onDownload: onDownload,
                        onDownloadAll: detail.languages.count > 1 ? onDownloadAll : nil
                    )
                }
            }
        }
        .padding(.trailing, 12)
    }

    private func resolvedVoiceLabel(for detail: AppViewModel.ProjectDetail) -> String? {
        if let title = detail.voiceTitle, !title.isEmpty {
            return title
        }
        if detail.voiceExternalId == nil {
            return defaultVoiceName
        }
        return NSLocalizedString("project_detail_voice_unknown", comment: "Fallback voice label")
    }

    private func formattedDuration(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, remainder)
        }
        return "\(seconds)s"
    }

    private func metadataBadges(for detail: AppViewModel.ProjectDetail) -> [MetadataBadge] {
        var items: [MetadataBadge] = []
        if let voice = resolvedVoiceLabel(for: detail) {
            items.append(MetadataBadge(iconName: "waveform", value: voice))
        }
        if let duration = formattedDuration(detail.targetDurationSeconds) {
            items.append(MetadataBadge(iconName: "clock", value: duration))
        }
        return items
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = locale
        return formatter.string(from: date)
    }

    private func close() {
        onClose()
        dismiss()
    }
}

private struct MetadataBadge: Identifiable {
    let id = UUID()
    let iconName: String
    let value: String
}

private struct MetadataBadgeView: View {
    let badge: MetadataBadge

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: badge.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(badge.value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(
            Capsule(style: .continuous)
                .fill(Color(.systemGray6))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

// Prevents the leading chip from being visually clipped by the scroll view without altering alignment.
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
