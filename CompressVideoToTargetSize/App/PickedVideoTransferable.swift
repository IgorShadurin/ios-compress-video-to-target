import Foundation
import CoreTransferable
import PhotosUI
import UniformTypeIdentifiers

struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { incoming in
            let destinationURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(incoming.file.pathExtension)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.copyItem(at: incoming.file, to: destinationURL)
            return PickedVideo(url: destinationURL)
        }
    }
}
