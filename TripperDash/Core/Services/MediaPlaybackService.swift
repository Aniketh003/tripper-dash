import Foundation
import SwiftUI
#if os(iOS)
import MediaPlayer
import AVFoundation
import UIKit
#endif

@Observable
public final class MediaPlaybackService: @unchecked Sendable {
    public static let shared = MediaPlaybackService()
    
    public var currentTitle: String = "Not Playing"
    public var currentArtist: String = ""
    public var isPlaying: Bool = false
    public var currentVolume: Float = 0.5
    public var volumePercent: Int = 50
    
    // Floating Apple-style Volume HUD state
    public var showVolumeHUD: Bool = false
    
    #if os(iOS)
    private let player = MPMusicPlayerController.systemMusicPlayer
    fileprivate weak var mountedSlider: UISlider?
    private var volumeObservation: NSKeyValueObservation?
    #endif
    private var hudDismissWorkItem: DispatchWorkItem?
    
    private init() {
        #if os(iOS)
        setupAudioSessionAndVolumeObserver()
        setupMediaObservers()
        updateCurrentTrack()
        #endif
    }
    
    #if os(iOS)
    private func setupAudioSessionAndVolumeObserver() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("MediaPlaybackService AVAudioSession setup error: \(error)")
        }
        
        let initialVol = session.outputVolume
        self.currentVolume = initialVol
        self.volumePercent = Int(round(initialVol * 100))
        
        // Observe live hardware & programmatic volume changes
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self = self, let newVol = change.newValue else { return }
            DispatchQueue.main.async {
                self.currentVolume = newVol
                self.volumePercent = Int(round(newVol * 100))
                TripperDashClient.shared.sendMusicUpdate(
                    title: self.currentTitle,
                    artist: self.currentArtist,
                    isPlaying: self.isPlaying
                )
            }
        }
    }
    
    private func setupMediaObservers() {
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
    
    fileprivate func attachSlider(_ slider: UISlider) {
        self.mountedSlider = slider
    }
    #endif
    
    public func updateCurrentTrack() {
        #if os(iOS)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let item = self.player.nowPlayingItem {
                self.currentTitle = item.title ?? "Unknown Track"
                self.currentArtist = item.artist ?? ""
            } else {
                self.currentTitle = "Not Playing"
                self.currentArtist = ""
            }
            self.updatePlaybackState()
            
            TripperDashClient.shared.sendMusicUpdate(
                title: self.currentTitle,
                artist: self.currentArtist,
                isPlaying: self.isPlaying
            )
        }
        #endif
    }
    
    #if os(iOS)
    private func updatePlaybackState() {
        isPlaying = (player.playbackState == .playing)
    }
    #endif
    
    // MARK: - Playback Controls (Driven by UI or Bike Handlebar Joystick)
    
    public func togglePlayPause() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if self.player.playbackState == .playing {
                self.player.pause()
                self.isPlaying = false
            } else {
                self.player.play()
                self.isPlaying = true
            }
            #else
            self.isPlaying.toggle()
            #endif
            
            TripperDashClient.shared.log(self.isPlaying ? "▶️ Music: Playing (\(self.currentTitle))" : "⏸️ Music: Paused")
            TripperDashClient.shared.sendMusicUpdate(
                title: self.currentTitle,
                artist: self.currentArtist,
                isPlaying: self.isPlaying
            )
        }
    }
    
    public func nextTrack() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.player.skipToNextItem()
            #endif
            TripperDashClient.shared.log("⏭️ Music: Next Track")
            self.updateCurrentTrack()
        }
    }
    
    public func previousTrack() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.player.skipToPreviousItem()
            #endif
            TripperDashClient.shared.log("⏮️ Music: Previous Track")
            self.updateCurrentTrack()
        }
    }
    
    // MARK: - System Media Volume Control (Handlebar Joystick Up / Down)
    
    public func volumeUp() {
        adjustVolume(by: 0.0625) // Exact 1/16th step matching iPhone hardware buttons
    }
    
    public func volumeDown() {
        adjustVolume(by: -0.0625)
    }
    
    public func setVolume(_ target: Float) {
        let clamped = min(1.0, max(0.0, target))
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.applySystemVolume(clamped)
        }
    }
    
    private func adjustVolume(by delta: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            #if os(iOS)
            // Always read true hardware volume from AVAudioSession (never stale slider.value!)
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(true)
            let base = session.outputVolume
            #else
            let base = self.currentVolume
            #endif
            
            let target = min(1.0, max(0.0, base + delta))
            self.applySystemVolume(target)
        }
    }
    
    private func applySystemVolume(_ target: Float) {
        self.currentVolume = target
        self.volumePercent = Int(round(target * 100))
        
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let slider = self.mountedSlider {
            // Setting value + sending touchUpInside reliably triggers MPVolumeSlider's internal system audio commit
            slider.setValue(target, animated: false)
            slider.sendActions(for: .touchUpInside)
            slider.sendActions(for: .valueChanged)
        }
        #endif
        
        triggerVolumeHUD()
        TripperDashClient.shared.log("🔊 System Volume → \(self.volumePercent)%")
        TripperDashClient.shared.sendMusicUpdate(
            title: self.currentTitle,
            artist: self.currentArtist,
            isPlaying: self.isPlaying
        )
    }
    
    private func triggerVolumeHUD() {
        hudDismissWorkItem?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showVolumeHUD = true
        }
        let item = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.25)) {
                self?.showVolumeHUD = false
            }
        }
        hudDismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: item)
    }
}

// MARK: - Persistent Invisible MPVolumeView Host (Mounted in Root View)
#if os(iOS)
public struct SystemVolumeBridge: UIViewRepresentable {
    public init() {}
    
    public func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 120, height: 32))
        volumeView.alpha = 0.01
        volumeView.isUserInteractionEnabled = false
        volumeView.clipsToBounds = true
        
        // Locate internal UISlider once laid out and register with MediaPlaybackService
        DispatchQueue.main.async {
            if let slider = findSlider(in: volumeView) {
                MediaPlaybackService.shared.attachSlider(slider)
            }
        }
        return volumeView
    }
    
    public func updateUIView(_ uiView: MPVolumeView, context: Context) {
        if MediaPlaybackService.shared.mountedSlider == nil,
           let slider = findSlider(in: uiView) {
            MediaPlaybackService.shared.attachSlider(slider)
        }
    }
    
    private func findSlider(in view: UIView) -> UISlider? {
        if let s = view as? UISlider { return s }
        for sub in view.subviews {
            if let s = findSlider(in: sub) { return s }
        }
        return nil
    }
}
#else
public struct SystemVolumeBridge: View {
    public init() {}
    public var body: some View { EmptyView() }
}
#endif
