import AVFoundation
import Combine
import Foundation

final class VoicePreviewController: ObservableObject {
    @Published private(set) var currentlyPlayingVoiceId: String?

    private var player: AVPlayer?
    private var playbackObserver: Any?

    func togglePreview(for voice: VoiceOption) {
        guard let url = voice.previewURL else { return }
        if currentlyPlayingVoiceId == voice.id {
            stop()
        } else {
            startPlayback(url: url, voiceId: voice.id)
        }
    }

    func stop() {
        player?.pause()
        player = nil
        if let observer = playbackObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackObserver = nil
        }
        currentlyPlayingVoiceId = nil
    }

    private func startPlayback(url: URL, voiceId: String) {
        stop()
        configureAudioSessionIfNeeded()
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        currentlyPlayingVoiceId = voiceId
        playbackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
        player?.play()
    }

    private func configureAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
            try session.setActive(true, options: [.notifyOthersOnDeactivation])
        } catch {
            // Silent failure; audio can still play with default session configuration.
        }
    }

    deinit {
        stop()
    }
}
