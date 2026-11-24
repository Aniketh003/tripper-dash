import Foundation
import SwiftUI
import Darwin
#if os(iOS)
import MediaPlayer
import AVFoundation
import UIKit
#endif

public enum MusicProvider: String, CaseIterable, Sendable {
    case spotify = "Spotify"
    case appleMusic = "Apple Music"
}

@Observable
public final class MediaPlaybackService: @unchecked Sendable {
    public static let shared = MediaPlaybackService()
    
    public var preferredProvider: MusicProvider = .spotify {
        didSet {
            UserDefaults.standard.set(preferredProvider.rawValue, forKey: "pref_music_provider")
            updateCurrentTrack(silentIfUnchanged: false)
        }
    }
    
    public var currentTitle: String = "Not Playing"
    public var currentArtist: String = ""
    public var currentAlbum: String = ""
    public var isPlaying: Bool = false
    public var currentVolume: Float = 0.5
    public var volumePercent: Int = 50
    
    // Floating Apple-style Volume HUD state
    public var showVolumeHUD: Bool = false
    
    #if os(iOS)
    private let appleMusicPlayer = MPMusicPlayerController.systemMusicPlayer
    fileprivate weak var mountedVolumeView: MPVolumeView?
    fileprivate weak var mountedSlider: UISlider?
    private var windowFallbackVolumeView: MPVolumeView?
    private var volumeObservation: NSKeyValueObservation?
    private var lastProgrammaticVolumeChangeAt: Date = .distantPast
    
    // Dynamic MediaRemote bridge
    private typealias MRMediaRemoteSendCommandFn = @convention(c) (UInt32, AnyObject?) -> Bool
    private typealias MRMediaRemoteGetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias MRMediaRemoteRegisterNotificationsFn = @convention(c) (DispatchQueue) -> Void
    private var mrSendCommand: MRMediaRemoteSendCommandFn?
    private var mrGetNowPlayingInfo: MRMediaRemoteGetNowPlayingInfoFn?
    private var mrRegisterNotifications: MRMediaRemoteRegisterNotificationsFn?
    #endif
    private var hudDismissWorkItem: DispatchWorkItem?
    private var pollTimer: DispatchSourceTimer?
    private let pollQueue = DispatchQueue(label: "com.tripperdash.mediapoll", qos: .utility)
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: "pref_music_provider"),
           let provider = MusicProvider(rawValue: saved) {
            self.preferredProvider = provider
        }
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
        if let symReg = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            mrRegisterNotifications = unsafeBitCast(symReg, to: MRMediaRemoteRegisterNotificationsFn.self)
            mrRegisterNotifications?(DispatchQueue.main)
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
        
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self = self, let newVol = change.newValue else { return }
            DispatchQueue.main.async {
                // Ignore stale KVO echo while our programmatic volume change is committing
                if Date().timeIntervalSince(self.lastProgrammaticVolumeChangeAt) < 0.45 {
                    return
                }
                self.currentVolume = newVol
                self.volumePercent = Int(round(newVol * 100))
                self.notifyDashMusicAndFrame()
            }
        }
    }
    
    private func setupMediaObservers() {
        appleMusicPlayer.beginGeneratingPlaybackNotifications()
        
        NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: appleMusicPlayer,
            queue: .main
        ) { [weak self] _ in
            guard self?.preferredProvider == .appleMusic else { return }
            self?.updateCurrentTrack()
        }
        
        NotificationCenter.default.addObserver(
            forName: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: appleMusicPlayer,
            queue: .main
        ) { [weak self] _ in
            guard self?.preferredProvider == .appleMusic else { return }
            self?.updateCurrentTrack()
        }
        
        // Observe MediaRemote notifications if delivered by iOS
        for name in [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
        ] {
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateCurrentTrack(silentIfUnchanged: true)
            }
        }
        
        // Background-safe GCD timer (continues polling Spotify / MediaRemote even when app is in background!)
        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now() + 1.5, repeating: .milliseconds(2000))
        timer.setEventHandler { [weak self] in
            self?.updateCurrentTrack(silentIfUnchanged: true)
        }
        timer.resume()
        self.pollTimer = timer
    }
    
    fileprivate func attachVolumeView(_ volumeView: MPVolumeView) {
        self.mountedVolumeView = volumeView
        if let slider = Self.findSlider(in: volumeView) {
            self.mountedSlider = slider
        }
    }
    
    fileprivate static func findSlider(in view: UIView) -> UISlider? {
        if let s = view as? UISlider { return s }
        for sub in view.subviews {
            if let s = findSlider(in: sub) { return s }
        }
        return nil
    }
    
    /// Lazily resolves or constructs an active `MPVolumeSlider` inside an off-screen `MPVolumeView`
    /// with `alpha = 1.0` so iOS 16/17/18 never drops programmatic volume changes.
    private func resolveVolumeSlider() -> UISlider? {
        if let existing = mountedSlider, existing.window != nil {
            return existing
        }
        if let vv = mountedVolumeView {
            vv.setNeedsLayout()
            vv.layoutIfNeeded()
            if let s = Self.findSlider(in: vv) {
                self.mountedSlider = s
                return s
            }
        }
        // Fallback: mount a dedicated off-screen MPVolumeView directly on the active key window
        if windowFallbackVolumeView == nil {
            let vv = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 240, height: 44))
            vv.alpha = 1.0
            vv.isHidden = false
            vv.isUserInteractionEnabled = false
            if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
               let window = windowScene.windows.first {
                window.addSubview(vv)
                vv.setNeedsLayout()
                vv.layoutIfNeeded()
                self.windowFallbackVolumeView = vv
            }
        }
        if let fallbackVV = windowFallbackVolumeView {
            fallbackVV.setNeedsLayout()
            fallbackVV.layoutIfNeeded()
            if let s = Self.findSlider(in: fallbackVV) {
                self.mountedSlider = s
                return s
            }
        }
        return mountedSlider
    }
    
    /// Dynamic private framework fallback (`AVSystemController` in `Celestial.framework` / `MediaExperience.framework`)
    /// so handlebar volume control also works while the iPhone screen is locked or app is backgrounded.
    private func setVolumeViaAVSystemController(_ target: Float) {
        _ = dlopen("/System/Library/PrivateFrameworks/Celestial.framework/Celestial", RTLD_NOW)
        _ = dlopen("/System/Library/PrivateFrameworks/MediaExperience.framework/MediaExperience", RTLD_NOW)
        guard let cls = NSClassFromString("AVSystemController") as? NSObject.Type else { return }
        let sharedSel = NSSelectorFromString("sharedAVSystemController")
        guard cls.responds(to: sharedSel),
              let controller = cls.perform(sharedSel)?.takeUnretainedValue() as? NSObject else {
            return
        }
        let setVolSel = NSSelectorFromString("setVolumeTo:forCategory:")
        guard controller.responds(to: setVolSel) else { return }
        typealias SetVolIMP = @convention(c) (AnyObject, Selector, Float, NSString) -> Bool
        let imp = controller.method(for: setVolSel)
        let fn = unsafeBitCast(imp, to: SetVolIMP.self)
        for category in ["Audio/Video", "MediaPlayback", "AmbientSound", "Ringtone"] {
            if fn(controller, setVolSel, target, category as NSString) {
                break
            }
        }
    }
    #endif
    
    public func updateCurrentTrack(silentIfUnchanged: Bool = false) {
        #if os(iOS)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let prevTitle = self.currentTitle
            let prevArtist = self.currentArtist
            let prevPlaying = self.isPlaying
            
            // 1. If user chose Apple Music explicitly (OR Apple Music is actively playing while Spotify is not connected)
            if self.preferredProvider == .appleMusic {
                if let item = self.appleMusicPlayer.nowPlayingItem {
                    self.currentTitle = item.title ?? "Unknown Track"
                    self.currentArtist = item.artist ?? ""
                    self.currentAlbum = item.albumTitle ?? ""
                    self.isPlaying = (self.appleMusicPlayer.playbackState == .playing)
                } else {
                    self.currentTitle = "Not Playing"
                    self.currentArtist = ""
                    self.currentAlbum = ""
                    self.isPlaying = false
                }
                self.commitTrackIfNeeded(prevTitle: prevTitle, prevArtist: prevArtist, prevPlaying: prevPlaying, silentIfUnchanged: silentIfUnchanged)
                return
            }
            
            // 2. Primary Mode: SPOTIFY
            // First query Spotify Web API if linked (works 100% in background & foreground on all iOS versions)
            let spotify = SpotifyService.shared
            if spotify.isConnected {
                spotify.fetchCurrentlyPlaying { [weak self] ok in
                    guard let self = self else { return }
                    if ok && !spotify.trackTitle.isEmpty {
                        self.currentTitle = spotify.trackTitle
                        self.currentArtist = spotify.trackArtist
                        self.currentAlbum = spotify.trackAlbum
                        self.isPlaying = spotify.isPlaying
                        self.commitTrackIfNeeded(prevTitle: prevTitle, prevArtist: prevArtist, prevPlaying: prevPlaying, silentIfUnchanged: silentIfUnchanged)
                    } else {
                        self.queryMediaRemoteOrAudioSession(prevTitle: prevTitle, prevArtist: prevArtist, prevPlaying: prevPlaying, silentIfUnchanged: silentIfUnchanged)
                    }
                }
            } else {
                self.queryMediaRemoteOrAudioSession(prevTitle: prevTitle, prevArtist: prevArtist, prevPlaying: prevPlaying, silentIfUnchanged: silentIfUnchanged)
            }
        }
        #endif
    }
    
    #if os(iOS)
    private func queryMediaRemoteOrAudioSession(prevTitle: String, prevArtist: String, prevPlaying: Bool, silentIfUnchanged: Bool) {
        let otherAudioPlaying = AVAudioSession.sharedInstance().isOtherAudioPlaying
        
        if let getInfo = self.mrGetNowPlayingInfo {
            getInfo(DispatchQueue.main) { [weak self] info in
                guard let self = self else { return }
                if let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !title.isEmpty {
                    self.currentTitle = title
                    self.currentArtist = (info["kMRMediaRemoteNowPlayingInfoArtist"] as? String) ?? "Spotify"
                    self.currentAlbum = (info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String) ?? ""
                    if let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double {
                        self.isPlaying = rate > 0.01
                    } else {
                        self.isPlaying = otherAudioPlaying
                    }
                } else {
                    self.isPlaying = otherAudioPlaying
                    if otherAudioPlaying && (self.currentTitle == "Not Playing" || self.currentTitle.isEmpty) {
                        self.currentTitle = "Spotify Playing"
                        self.currentArtist = "Link Spotify in App for Track Titles"
                    } else if !otherAudioPlaying && self.currentTitle == "Spotify Playing" {
                        self.currentTitle = "Spotify Paused"
                    }
                }
                self.commitTrackIfNeeded(prevTitle: prevTitle, prevArtist: prevArtist, prevPlaying: prevPlaying, silentIfUnchanged: silentIfUnchanged)
            }
        } else {
            self.isPlaying = otherAudioPlaying
            self.commitTrackIfNeeded(prevTitle: prevTitle, prevArtist: prevArtist, prevPlaying: prevPlaying, silentIfUnchanged: silentIfUnchanged)
        }
    }
    #endif
    
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
    
    private func scheduleFollowUpTrackUpdates() {
        for delay in [0.25, 0.65, 1.25] {
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
            
            if self.preferredProvider == .appleMusic {
                if self.appleMusicPlayer.playbackState == .playing {
                    self.appleMusicPlayer.pause()
                    self.isPlaying = false
                } else {
                    self.appleMusicPlayer.play()
                    self.isPlaying = true
                }
                self.notifyDashMusicAndFrame()
                self.scheduleFollowUpTrackUpdates()
                return
            }
            
            // SPOTIFY MODE (Never triggers Apple Music!)
            let targetPlayState = !self.isPlaying
            self.isPlaying = targetPlayState
            self.notifyDashMusicAndFrame()
            
            let spotify = SpotifyService.shared
            if spotify.isConnected {
                let endpoint = targetPlayState ? "play" : "pause"
                spotify.sendPlayerCommand(endpoint: endpoint, method: "PUT") { [weak self] ok in
                    if !ok {
                        _ = self?.mrSendCommand?(2, nil)
                    }
                    self?.scheduleFollowUpTrackUpdates()
                }
            } else {
                let sent = self.mrSendCommand?(2, nil) ?? false
                if !sent {
                    // Fallback: Use AVAudioSession focus pulse to pause/resume external Spotify session
                    self.toggleExternalAudioViaSessionFocus()
                }
                self.scheduleFollowUpTrackUpdates()
            }
            #else
            self.isPlaying.toggle()
            self.notifyDashMusicAndFrame()
            #endif
            
            TripperDashClient.shared.log(self.isPlaying ? "▶️ Spotify: Play (\(self.currentTitle))" : "⏸️ Spotify: Pause")
        }
    }
    
    public func nextTrack() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            
            if self.preferredProvider == .appleMusic {
                self.appleMusicPlayer.skipToNextItem()
                self.scheduleFollowUpTrackUpdates()
                return
            }
            
            // SPOTIFY MODE
            let spotify = SpotifyService.shared
            if spotify.isConnected {
                spotify.sendPlayerCommand(endpoint: "next", method: "POST") { [weak self] _ in
                    self?.scheduleFollowUpTrackUpdates()
                }
            } else {
                _ = self.mrSendCommand?(4, nil)
                self.scheduleFollowUpTrackUpdates()
            }
            #endif
            TripperDashClient.shared.log("⏭️ Spotify: Next Track")
        }
    }
    
    public func previousTrack() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            
            if self.preferredProvider == .appleMusic {
                if self.appleMusicPlayer.currentPlaybackTime > 3.5 {
                    self.appleMusicPlayer.skipToBeginning()
                } else {
                    self.appleMusicPlayer.skipToPreviousItem()
                }
                self.scheduleFollowUpTrackUpdates()
                return
            }
            
            // SPOTIFY MODE
            let spotify = SpotifyService.shared
            if spotify.isConnected {
                spotify.sendPlayerCommand(endpoint: "previous", method: "POST") { [weak self] _ in
                    self?.scheduleFollowUpTrackUpdates()
                }
            } else {
                _ = self.mrSendCommand?(5, nil)
                self.scheduleFollowUpTrackUpdates()
            }
            #endif
            TripperDashClient.shared.log("⏮️ Spotify: Previous Track")
        }
    }
    
    #if os(iOS)
    /// Toggles external audio app (Spotify) play/pause by pulsing non-mixable audio session focus
    /// and releasing with `.notifyOthersOnDeactivation`.
    private func toggleExternalAudioViaSessionFocus() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                try? session.setActive(false, options: [.notifyOthersOnDeactivation])
                try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try? session.setActive(true)
            }
        } catch {
            print("Audio focus toggle error: \(error)")
        }
    }
    #endif
    
    // MARK: - System Media Volume Control (Handlebar Joystick Up / Down — Works for Spotify & All Apps!)
    
    public func volumeUp() {
        adjustVolume(by: 0.0625)
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
            // Use self.currentVolume when stepping consecutively within 1.5s because
            // AVAudioSession.outputVolume updates asynchronously after MPVolumeSlider commits.
            let recentlyStepped = Date().timeIntervalSince(self.lastProgrammaticVolumeChangeAt) < 1.5
            let base = recentlyStepped ? self.currentVolume : session.outputVolume
            #else
            let base = self.currentVolume
            #endif
            
            let target = min(1.0, max(0.0, base + delta))
            self.applySystemVolume(target)
        }
    }
    
    private func applySystemVolume(_ target: Float) {
        #if os(iOS)
        self.lastProgrammaticVolumeChangeAt = Date()
        #endif
        self.currentVolume = target
        self.volumePercent = Int(round(target * 100))
        
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let slider = self.resolveVolumeSlider() {
            slider.value = target
            slider.setValue(target, animated: false)
            slider.sendActions(for: [.valueChanged, .touchUpInside])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.035) {
                slider.setValue(target, animated: false)
                slider.sendActions(for: .valueChanged)
            }
        }
        self.setVolumeViaAVSystemController(target)
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

// MARK: - Persistent Off-Screen MPVolumeView Host (Mounted in Root View with alpha=1.0)
#if os(iOS)
public struct SystemVolumeBridge: UIViewRepresentable {
    public init() {}
    
    public func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 200, height: 44))
        // Crucial for iOS 16/17/18: alpha MUST be >= 0.05 (1.0 offscreen is best)
        // or MPVolumeSlider silently ignores programmatic setValue calls!
        volumeView.alpha = 1.0
        volumeView.isHidden = false
        volumeView.isUserInteractionEnabled = false
        volumeView.showsRouteButton = false
        volumeView.setNeedsLayout()
        volumeView.layoutIfNeeded()
        
        MediaPlaybackService.shared.attachVolumeView(volumeView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            volumeView.setNeedsLayout()
            volumeView.layoutIfNeeded()
            MediaPlaybackService.shared.attachVolumeView(volumeView)
        }
        return volumeView
    }
    
    public func updateUIView(_ uiView: MPVolumeView, context: Context) {
        MediaPlaybackService.shared.attachVolumeView(uiView)
    }
}
#else
public struct SystemVolumeBridge: View {
    public init() {}
    public var body: some View { EmptyView() }
}
#endif
