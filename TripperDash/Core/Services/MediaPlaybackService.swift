import Foundation
import SwiftUI
import Darwin
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
    public var currentAlbum: String = ""
    public var isPlaying: Bool = false
    public var currentVolume: Float = 0.5
    public var volumePercent: Int = 50
    
    // Floating Apple-style Volume HUD state
    public var showVolumeHUD: Bool = false
    
    #if os(iOS)
    private let player = MPMusicPlayerController.systemMusicPlayer
    fileprivate weak var mountedSlider: UISlider?
    private var volumeObservation: NSKeyValueObservation?
    
    // Dynamic MediaRemote bridge for system-wide playback (Spotify, YouTube Music, Apple Music) on sideloaded builds
    private typealias MRMediaRemoteSendCommandFn = @convention(c) (UInt32, AnyObject?) -> Bool
    private typealias MRMediaRemoteGetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private var mrSendCommand: MRMediaRemoteSendCommandFn?
    private var mrGetNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFn?
    #endif
    private var hudDismissWorkItem: DispatchWorkItem?
    private var pollTimer: Timer?
    
    private init() {
        #if os(iOS)
        setupMediaRemoteBridge()
        setupAudioSessionAndVolumeObserver()
        setupMediaObservers()
        updateCurrentTrack()
        #endif
    }
    
    #if os(iOS)
    private func setupMediaRemoteBridge() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
            return
        }
        if let symSend = dlsym(handle, "MRMediaRemoteSendCommand") {
            mrSendCommand = unsafeBitCast(symSend, to: MRMediaRemoteSendCommandFn.self)
        }
        if let symInfo = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            mrGetNowPlayingInfo = unsafeBitCast(symInfo, to: MRMediaRemoteGetNowPlayingInfoFn.self)
        }
    }
    
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
                self.notifyDashMusicAndFrame()
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
            self?.updateCurrentTrack()
        }
        
        // Periodic lightweight sync so external player track changes (Spotify / YouTube Music / Lock Screen) stay realtime
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.updateCurrentTrack(silentIfUnchanged: true)
        }
    }
    
    fileprivate func attachSlider(_ slider: UISlider) {
        self.mountedSlider = slider
    }
    #endif
    
    public func updateCurrentTrack(silentIfUnchanged: Bool = false) {
        #if os(iOS)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let prevTitle = self.currentTitle
            let prevArtist = self.currentArtist
            let prevPlaying = self.isPlaying
            
            if let item = self.player.nowPlayingItem {
                self.currentTitle = item.title ?? "Unknown Track"
                self.currentArtist = item.artist ?? ""
                self.currentAlbum = item.albumTitle ?? ""
                self.isPlaying = (self.player.playbackState == .playing)
                self.commitTrackIfNeeded(prevTitle: prevTitle, prevArtist: prevArtist, prevPlaying: prevPlaying, silentIfUnchanged: silentIfUnchanged)
            } else if let getInfo = self.mrGetNowPlayingInfo {
                // Query system MediaRemote daemon (captures Spotify, YouTube Music, Apple Music, etc.)
                getInfo(DispatchQueue.main) { [weak self] info in
                    guard let self = self else { return }
                    if let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !title.isEmpty {
                        self.currentTitle = title
                        self.currentArtist = (info["kMRMediaRemoteNowPlayingInfoArtist"] as? String) ?? ""
                        self.currentAlbum = (info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String) ?? ""
                        if let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double {
                            self.isPlaying = rate > 0.01
                        }
                    } else if self.player.playbackState == .playing {
                        self.isPlaying = true
                    } else if self.currentTitle == "Not Playing" {
                        self.isPlaying = false
                    }
                    self.commitTrackIfNeeded(prevTitle: prevTitle, prevArtist: prevArtist, prevPlaying: prevPlaying, silentIfUnchanged: silentIfUnchanged)
                }
            } else {
                self.isPlaying = (self.player.playbackState == .playing)
                self.commitTrackIfNeeded(prevTitle: prevTitle, prevArtist: prevArtist, prevPlaying: prevPlaying, silentIfUnchanged: silentIfUnchanged)
            }
        }
        #endif
    }
    
    private func commitTrackIfNeeded(prevTitle: String, prevArtist: String, prevPlaying: Bool, silentIfUnchanged: Bool) {
        let changed = (prevTitle != currentTitle) || (prevArtist != currentArtist) || (prevPlaying != isPlaying)
        if changed || !silentIfUnchanged {
            notifyDashMusicAndFrame()
        }
    }
    
    private func notifyDashMusicAndFrame() {
        TripperDashClient.shared.sendMusicUpdate(
            title: currentTitle,
            album: currentAlbum,
            artist: currentArtist,
            isPlaying: isPlaying
        )
        TFTProjectionService.shared.triggerImmediateFrame()
    }
    
    /// Schedules follow-up metadata checks after an async skip/play command so the new song title is always captured
    private func scheduleFollowUpTrackUpdates() {
        for delay in [0.15, 0.35, 0.70] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.updateCurrentTrack()
            }
        }
    }
    
    // MARK: - Playback Controls (Driven by UI or Bike Handlebar Joystick)
    
    public func togglePlayPause() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if self.player.nowPlayingItem != nil || self.mrSendCommand == nil {
                if self.player.playbackState == .playing {
                    self.player.pause()
                    self.isPlaying = false
                } else {
                    self.player.play()
                    self.isPlaying = true
                }
            } else if let sendCmd = self.mrSendCommand {
                // Command 2 = kMRTogglePlayPause (works across Spotify, YouTube Music, Apple Music)
                _ = sendCmd(2, nil)
                self.isPlaying.toggle()
            }
            #else
            self.isPlaying.toggle()
            #endif
            
            TripperDashClient.shared.log(self.isPlaying ? "▶️ Music: Playing (\(self.currentTitle))" : "⏸️ Music: Paused")
            self.notifyDashMusicAndFrame()
            self.scheduleFollowUpTrackUpdates()
        }
    }
    
    public func nextTrack() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if self.player.nowPlayingItem != nil || self.mrSendCommand == nil {
                self.player.skipToNextItem()
            } else if let sendCmd = self.mrSendCommand {
                // Command 4 = kMRNextTrack
                _ = sendCmd(4, nil)
            }
            #endif
            TripperDashClient.shared.log("⏭️ Music: Next Track")
            self.scheduleFollowUpTrackUpdates()
        }
    }
    
    public func previousTrack() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if self.player.nowPlayingItem != nil || self.mrSendCommand == nil {
                if self.player.currentPlaybackTime > 3.5 {
                    self.player.skipToBeginning()
                } else {
                    self.player.skipToPreviousItem()
                }
            } else if let sendCmd = self.mrSendCommand {
                // Command 5 = kMRPreviousTrack
                _ = sendCmd(5, nil)
            }
            #endif
            TripperDashClient.shared.log("⏮️ Music: Previous Track")
            self.scheduleFollowUpTrackUpdates()
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
            slider.setValue(target, animated: false)
            slider.sendActions(for: .touchUpInside)
            slider.sendActions(for: .valueChanged)
        }
        #endif
        
        triggerVolumeHUD()
        TripperDashClient.shared.log("🔊 System Volume → \(self.volumePercent)%")
        notifyDashMusicAndFrame()
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
