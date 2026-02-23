import SwiftUI
import PhotosUI
import UIKit

struct CharacterUploadSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var previewImage: Image?
    @State private var imageData: Data?
    @State private var mimeType: String = "image/jpeg"
    @State private var generatedFileName: String = CharacterUploadSheet.makeFilename(for: "jpg")
    @State private var originalFileSize: Int?
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var isUploading: Bool = false
    @State private var errorMessage: String?

    private let titleLimit = 191
    private let descriptionLimit = 400
    private let uploadLimitBytes = 2 * 1_024 * 1_024
    private let maxDimension: CGFloat = 2_000

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    photoPickerSection
                    nameField
                    descriptionField
                    limitsHint
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Button(action: upload) {
                        HStack {
                            if isUploading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else {
                                Image(systemName: "tray.and.arrow.up")
                            }
                            Text(LocalizedStringKey("character_upload_submit"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUploading || imageData == nil)
                }
                .padding(20)
            }
            .navigationTitle(LocalizedStringKey("character_upload_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey("character_upload_cancel")) {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: pickerItem) { newValue in
            guard let newValue else { return }
            Task {
                await loadImage(from: newValue)
            }
        }
    }

    private var photoPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("character_upload_image_label"))
                .font(.headline)
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    RoundedRectangle(cornerRadius: UIRadius.card, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
                        .foregroundStyle(.secondary)
                        .frame(height: 180)
                    if let previewImage {
                        previewImage
                            .resizable()
                            .scaledToFit()
                            .frame(height: 168)
                            .clipShape(RoundedRectangle(cornerRadius: UIRadius.input, style: .continuous))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 28, weight: .semibold))
                            Text(LocalizedStringKey("character_upload_image_placeholder"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .disabled(isUploading)
            if let sizeDescription {
                Text(sizeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey("character_upload_name"))
                .font(.headline)
            TextField(LocalizedStringKey("character_upload_name_placeholder"), text: $title)
                .modifier(UploadTextFieldStyle())
                .disabled(isUploading)
            Text("\(title.count)/\(titleLimit)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey("character_upload_description"))
                .font(.headline)
            TextField(LocalizedStringKey("character_upload_description_placeholder"), text: $description, axis: .vertical)
                .modifier(UploadTextFieldStyle(minHeight: 120))
                .lineLimit(3...5)
                .disabled(isUploading)
            Text("\(description.count)/\(descriptionLimit)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var limitsHint: some View {
        Text(LocalizedStringKey("character_upload_limits_hint"))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var sizeDescription: String? {
        guard let processedBytes = imageData?.count else { return nil }
        let processedText = formatByteCount(processedBytes)
        if let original = originalFileSize, original != processedBytes {
            let originalText = formatByteCount(original)
            return String(format: NSLocalizedString("character_upload_size_converted", comment: "Processed + original"), processedText, originalText)
        }
        return String(format: NSLocalizedString("character_upload_size_basic", comment: "Processed size"), processedText)
    }

    private func upload() {
        guard !isUploading else { return }
        guard let data = imageData else {
            errorMessage = NSLocalizedString("character_upload_error_missing_image", comment: "Missing image")
            return
        }
        let sanitizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = sanitizedTitle.isEmpty ? CharacterNameGenerator.generate() : sanitizedTitle
        let sanitizedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalDescription = sanitizedDescription.isEmpty ? nil : sanitizedDescription
        let filename = generatedFileName
        isUploading = true
        errorMessage = nil
        Task {
            do {
                try await viewModel.uploadCustomCharacter(
                    imageData: data,
                    fileName: filename,
                    mimeType: mimeType,
                    title: String(finalTitle.prefix(titleLimit)),
                    description: finalDescription.map { String($0.prefix(descriptionLimit)) }
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isUploading = false
        }
    }

    @MainActor
    private func loadImage(from item: PhotosPickerItem) async {
        errorMessage = nil
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                if let processed = processImage(image, originalBytes: data.count) {
                    previewImage = Image(uiImage: processed.image)
                    imageData = processed.data
                    mimeType = processed.mimeType
                    generatedFileName = CharacterUploadSheet.makeFilename(for: processed.fileExtension)
                    originalFileSize = data.count
                } else {
                    imageData = nil
                    previewImage = nil
                    originalFileSize = nil
                    errorMessage = NSLocalizedString("character_upload_error_processing", comment: "Processing failed")
                }
            } else {
                errorMessage = NSLocalizedString("character_upload_error_type", comment: "Invalid image type")
            }
        } catch {
            errorMessage = error.localizedDescription
            imageData = nil
            previewImage = nil
            originalFileSize = nil
        }
    }

    private static func makeFilename(for ext: String) -> String {
        return "character-\(UUID().uuidString).\(ext)"
    }

    private func processImage(_ image: UIImage, originalBytes: Int) -> ProcessedImage? {
        let targetBytes = min(uploadLimitBytes, originalBytes)
        var workingImage = image.normalizedForUpload()
        workingImage = workingImage.scaledIfNeeded(maxDimension: maxDimension)
        var currentMaxDimension = max(workingImage.size.width, workingImage.size.height)
        let compressionSteps: [CGFloat] = stride(from: 0.95, through: 0.30, by: -0.05).map { CGFloat($0) }

        for _ in 0..<8 {
            if let data = compress(image: workingImage, qualities: compressionSteps, targetBytes: targetBytes) {
                return ProcessedImage(image: workingImage, data: data, mimeType: "image/jpeg", fileExtension: "jpg")
            }
            currentMaxDimension *= 0.85
            if currentMaxDimension < 320 {
                break
            }
            workingImage = workingImage.scaled(toMaxDimension: currentMaxDimension)
        }
        return nil
    }

    private func compress(image: UIImage, qualities: [CGFloat], targetBytes: Int) -> Data? {
        for quality in qualities {
            if let data = image.jpegData(compressionQuality: quality), data.count <= targetBytes {
                return data
            }
        }
        return nil
    }

    private func formatByteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

private struct UploadTextFieldStyle: ViewModifier {
    var minHeight: CGFloat = 48

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: UIRadius.input, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIRadius.input, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct ProcessedImage {
    let image: UIImage
    let data: Data
    let mimeType: String
    let fileExtension: String
}

private extension UIImage {
    func normalizedForUpload() -> UIImage {
        if imageOrientation == .up { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return result ?? self
    }

    func scaledIfNeeded(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        return scaled(toMaxDimension: maxDimension)
    }

    func scaled(toMaxDimension maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scaleFactor = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        return redrawn(to: newSize)
    }

    func redrawn(to newSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
