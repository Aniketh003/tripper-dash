import Foundation
import MediaPlayer

@Observable
public final class MediaPlaybackService: @unchecked Sendable {
    public static let shared = MediaPlaybackService()
    
    public var currentTitle: String = "No Media Playing"
    public var currentArtist: String = "Idle"
    public var isPlaying: Bool = false
    
    private let player = MPMusicPlayerController.systemMusicPlayer
    
    private init() {
        setupObservers()
        updateCurrentTrack()
    }
    
    private func setupObservers() {
        player.beginGeneratingPlaybackNotifications()
        
        NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            self?.updateCurrentTrack()
        }
        
        NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player,
            queue: .main
        ) { [weak self] _ in
            self?.updatePlaybackState()
        }
    }
    
    public func updateCurrentTrack() {
        if let item = player.nowPlayingItem {
            currentTitle = item.title ?? "Unknown Title"
            currentArtist = item.artist ?? "Unknown Artist"
        } else {
            currentTitle = "No Track Playing"
            currentArtist = ""
        }
        updatePlaybackState()
        
        // Push update to motorcycle dash
        TripperDashClient.shared.sendMusicUpdate(
            title: currentTitle,
            artist: currentArtist,
            isPlaying: isPlaying
        )
    }
    
    private func updatePlaybackState() {
        isPlaying = (player.playbackState == .playing)
    }
    
    // MARK: - Playback Controls (Can be driven by phone UI or bike handlebar joystick)
    
    public func togglePlayPause() {
        if player.playbackState == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        TripperDashClient.shared.sendMusicUpdate(
            title: currentTitle,
            artist: currentArtist,
            isPlaying: isPlaying
        )
    }
    
    public func nextTrack() {
        player.skipToNextItem()
        updateCurrentTrack()
    }
    
    public func previousTrack() {
        player.skipToPreviousItem()
        updateCurrentTrack()
    }
}
