import Foundation
#if os(iOS)
import MediaPlayer
import UIKit
#endif

@Observable
public final class MediaPlaybackService: @unchecked Sendable {
    public static let shared = MediaPlaybackService()
    
    public var currentTitle: String = "No Media Playing"
    public var currentArtist: String = "Idle"
    public var isPlaying: Bool = false
    public var volumePercent: Int = 75
    
    #if os(iOS)
    private let player = MPMusicPlayerController.systemMusicPlayer
    private var volumeSlider: UISlider?
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
    
    // MARK: - Volume Controls (Handlebar Joystick Up / Down)
    
    #if os(iOS)
    private func getVolumeSlider() -> UISlider? {
        if let slider = volumeSlider {
            return slider
        }
        let volumeView = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
        volumeView.alpha = 0.0001
        if let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
           let window = windowScene.windows.first {
            window.addSubview(volumeView)
        }
        volumeView.layoutIfNeeded()
        
        func findSlider(in view: UIView) -> UISlider? {
            if let s = view as? UISlider { return s }
            for sub in view.subviews {
                if let s = findSlider(in: sub) { return s }
            }
            return nil
        }
        
        if let s = findSlider(in: volumeView) {
            self.volumeSlider = s
            return s
        }
        return nil
    }
    #endif
    
    public func volumeUp() {
        #if os(iOS)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let slider = self.getVolumeSlider() {
                let current = slider.value
                let updated = min(1.0, current + 0.0625)
                slider.setValue(updated, animated: false)
                slider.sendActions(for: .valueChanged)
                self.volumePercent = Int(updated * 100)
                TripperDashClient.shared.log("🔊 Volume UP -> \(self.volumePercent)%")
            } else {
                self.volumePercent = min(100, self.volumePercent + 6)
                TripperDashClient.shared.log("🔊 Volume UP -> \(self.volumePercent)%")
            }
        }
        #else
        volumePercent = min(100, volumePercent + 6)
        TripperDashClient.shared.log("🔊 Volume UP -> \(volumePercent)%")
        #endif
    }
    
    public func volumeDown() {
        #if os(iOS)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let slider = self.getVolumeSlider() {
                let current = slider.value
                let updated = max(0.0, current - 0.0625)
                slider.setValue(updated, animated: false)
                slider.sendActions(for: .valueChanged)
                self.volumePercent = Int(updated * 100)
                TripperDashClient.shared.log("🔉 Volume DOWN -> \(self.volumePercent)%")
            } else {
                self.volumePercent = max(0, self.volumePercent - 6)
                TripperDashClient.shared.log("🔉 Volume DOWN -> \(self.volumePercent)%")
            }
        }
        #else
        volumePercent = max(0, volumePercent - 6)
        TripperDashClient.shared.log("🔉 Volume DOWN -> \(volumePercent)%")
        #endif
    }
}
