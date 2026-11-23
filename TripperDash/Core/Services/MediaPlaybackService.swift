import Foundation
#if os(iOS)
import MediaPlayer
#endif

@Observable
public final class MediaPlaybackService: @unchecked Sendable {
    public static let shared = MediaPlaybackService()
    
    public var currentTitle: String = "No Media Playing"
    public var currentArtist: String = "Idle"
    public var isPlaying: Bool = false
    
    #if os(iOS)
    private let player = MPMusicPlayerController.systemMusicPlayer
    #endif
    
    private init() {
        #if os(iOS)
        setupObservers()
        updateCurrentTrack()
        #endif
    }
    
    #if os(iOS)
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
    #endif
    
    public func updateCurrentTrack() {
        #if os(iOS)
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
        #endif
    }
    
    #if os(iOS)
    private func updatePlaybackState() {
        isPlaying = (player.playbackState == .playing)
    }
    #endif
    
    // MARK: - Playback Controls (Can be driven by phone UI or bike handlebar joystick)
    
    public func togglePlayPause() {
        #if os(iOS)
        if player.playbackState == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
        #else
        isPlaying.toggle()
        #endif
        
        TripperDashClient.shared.sendMusicUpdate(
            title: currentTitle,
            artist: currentArtist,
            isPlaying: isPlaying
        )
    }
    
    public func nextTrack() {
        #if os(iOS)
        player.skipToNextItem()
        updateCurrentTrack()
        #endif
    }
    
    public func previousTrack() {
        #if os(iOS)
        player.skipToPreviousItem()
        updateCurrentTrack()
        #endif
    }
}
