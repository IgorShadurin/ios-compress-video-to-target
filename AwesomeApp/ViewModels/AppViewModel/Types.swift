import SwiftUI
import Foundation

extension AppViewModel {
    enum ViewPhase {
        case idle
        case processing
        case result
    }

    enum GenerationMode: String {
        case demo
        case production
    }

    enum DownloadPhase {
        case idle
        case ready
        case downloading
        case success
        case failed(message: String)

        var isError: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    enum PaywallPlan: String, CaseIterable, Identifiable {
        case weekly
        case monthly

        var id: String { rawValue }

        var productIdentifier: String {
            switch self {
            case .weekly:
                return "awesomeapp_weekly_basic"
            case .monthly:
                return "awesomeapp_monthly_basic"
            }
        }

        init?(productIdentifier: String) {
            switch productIdentifier {
            case "awesomeapp_weekly_basic":
                self = .weekly
            case "awesomeapp_monthly_basic":
                self = .monthly
            default:
                return nil
            }
        }
    }

    enum RestoreOutcome {
        case restored
        case notFound
        case failed(String)
        case cancelled
        case guestLinkRequired

        var localizedDescription: String {
            switch self {
            case .restored:
                return NSLocalizedString("restore_success_message", comment: "")
            case .notFound:
                return NSLocalizedString("restore_not_found_message", comment: "")
            case .failed(let message):
                return message
            case .cancelled:
                return ""
            case .guestLinkRequired:
                return NSLocalizedString("restore_guest_link_message", comment: "")
            }
        }
    }

    enum PaywallContext {
        case manual
        case creationRequest
    }

    struct ProjectSummary: Identifiable, Hashable {
        let id: String
        let title: String
        let createdAt: Date
        let status: ProjectSummaryStatus
    }

    struct ProjectDetail: Identifiable, Hashable {
        let id: String
        var title: String
        var createdAt: Date
        var status: ProjectSummaryStatus
        var prompt: String?
        var finalVideoURL: URL?
        var languages: [String]
        var languageVariants: [ProjectLanguageVariant]
        var targetDurationSeconds: Int?
        var voiceExternalId: String?
        var voiceTitle: String?

        init(summary: ProjectSummary) {
            self.id = summary.id
        self.title = summary.title
        self.createdAt = summary.createdAt
        self.status = summary.status
        self.prompt = nil
        self.finalVideoURL = nil
        self.languages = []
        self.languageVariants = []
        self.targetDurationSeconds = nil
        self.voiceExternalId = nil
        self.voiceTitle = nil
    }
}

    struct ProcessingStage: Identifiable {
        let id = UUID()
        let iconName: String
        let titleKey: String
        let iconTint: Color
        let backgroundTint: Color
    }

    enum ProjectSummaryStatus: String, Decodable {
        case new = "new"
        case processScript = "process_script"
        case processScriptValidate = "process_script_validate"
        case processAudio = "process_audio"
        case processAudioValidate = "process_audio_validate"
        case processTranscription = "process_transcription"
        case processMetadata = "process_metadata"
        case processCaptionsVideo = "process_captions_video"
        case processImagesGeneration = "process_images_generation"
        case processVideoPartsGeneration = "process_video_parts_generation"
        case processVideoMain = "process_video_main"
        case error = "error"
        case done = "done"
        case cancelled = "cancelled"
        case unknown

        var isComplete: Bool { self == .done }

        var isTerminal: Bool {
            switch self {
            case .done, .error, .cancelled:
                return true
            default:
                return false
            }
        }

        var localizedKey: LocalizedStringKey {
            switch self {
            case .done:
                return LocalizedStringKey("project_status_done")
            case .error:
                return LocalizedStringKey("project_status_error")
            case .cancelled:
                return LocalizedStringKey("project_status_cancelled")
            case .unknown:
                return LocalizedStringKey("project_status_unknown")
            default:
                return LocalizedStringKey("project_status_processing")
            }
        }

        var tintColor: Color {
            switch self {
            case .done:
                return .green
            case .error:
                return .red
            case .cancelled:
                return .gray
            case .unknown:
                return .secondary
            default:
                return .orange
            }
        }

        func progressIndex(in stages: [AppViewModel.ProcessingStage]) -> Int {
            let last = max(0, stages.count - 1)
            switch self {
            case .done:
                return last
            case .processVideoMain:
                return min(last, 5)
            case .processVideoPartsGeneration:
                return min(last, 4)
            case .processImagesGeneration, .processCaptionsVideo:
                return min(last, 3)
            case .processMetadata, .processTranscription:
                return min(last, 2)
            case .processAudio, .processAudioValidate:
                return min(last, 1)
            case .processScript, .processScriptValidate, .new:
                return 0
            case .error, .cancelled:
                return last
            case .unknown:
                return 0
            }
        }
    }

    enum PhotoPermissionError: LocalizedError {
        case denied
        case unknown

        var errorDescription: String? {
            switch self {
            case .denied:
                return NSLocalizedString("error_photos_denied", comment: "")
            case .unknown:
                return NSLocalizedString("error_generic", comment: "")
            }
        }
    }
}
extension AppViewModel.ProjectSummary {
    init(response: ProjectListItemResponse) {
        self.id = response.id
        self.title = response.title
        self.createdAt = response.createdAt
        self.status = AppViewModel.ProjectSummaryStatus(rawValue: response.status) ?? AppViewModel.ProjectSummaryStatus.unknown
    }
}

extension AppViewModel.ProjectDetail {
    init(response: ProjectDetailResponse) {
        self.id = response.id
        self.title = response.title
        self.createdAt = response.createdAt
            self.status = AppViewModel.ProjectSummaryStatus(rawValue: response.status) ?? AppViewModel.ProjectSummaryStatus.unknown
            let preferredPrompt = response.prompt?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let preferredPrompt, !preferredPrompt.isEmpty {
                self.prompt = preferredPrompt
            } else if let rawScript = response.rawScript?.trimmingCharacters(in: .whitespacesAndNewlines), !rawScript.isEmpty {
                self.prompt = rawScript
            } else {
                self.prompt = nil
            }
            self.finalVideoURL = AppViewModel.ProjectDetail.makeAbsoluteURL(primary: response.finalVideoUrl, fallbackPath: response.finalVideoPath)
            self.languages = response.languages ?? []
            self.languageVariants = (response.languageVariants ?? [])
                .map { variant in
                    ProjectLanguageVariant(
                        languageCode: variant.languageCode,
                        isPrimary: variant.isPrimary ?? false,
                        finalVideoURL: AppViewModel.ProjectDetail.makeAbsoluteURL(
                            primary: variant.finalVideoUrl.flatMap { URL(string: $0) },
                            fallbackPath: variant.finalVideoPath
                        )
                    )
                }
            self.targetDurationSeconds = response.creation?.durationSeconds
            self.voiceExternalId = response.creation?.voiceId
            self.voiceTitle = nil
        }

    mutating func merge(summary: AppViewModel.ProjectSummary) {
        guard summary.id == id else { return }
        title = summary.title
        createdAt = summary.createdAt
        status = summary.status
    }
}

private extension AppViewModel.ProjectDetail {
    static func makeAbsoluteURL(primary: URL?, fallbackPath: String?) -> URL? {
        if let primary {
            return primary
        }
        guard let fallbackPath, !fallbackPath.isEmpty else { return nil }
        if let absolute = URL(string: fallbackPath), absolute.scheme != nil {
            return absolute
        }
        if let relative = URL(string: fallbackPath, relativeTo: AppConfiguration.apiBaseURL) {
            return relative.absoluteURL
        }
        return nil
    }
}

struct ProjectLanguageVariant: Identifiable, Hashable {
    var id: String { languageCode }
    let languageCode: String
    let isPrimary: Bool
    let finalVideoURL: URL?
}

struct DownloadProgress: Equatable {
    enum Mode: Equatable { case single, all }
    var current: Int
    var total: Int
    var mode: Mode
}

enum PlayerStatus: Equatable {
    case idle
    case loading
    case ready
    case failed(String?)
}

extension AppViewModel.ProjectDetail {
    func finalVideoURL(for languageCode: String?) -> URL? {
        if let languageCode,
           let match = languageVariants.first(where: { $0.languageCode == languageCode }),
           let url = match.finalVideoURL {
            return url
        }
        if let primary = languageVariants.first(where: { $0.isPrimary && $0.finalVideoURL != nil }) {
            return primary.finalVideoURL
        }
        return finalVideoURL
    }
}
