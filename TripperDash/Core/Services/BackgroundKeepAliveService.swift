import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// Guarantees that the Wi-Fi UDP K1G socket + H.264 RTP video stream to the Royal Enfield TFT Dash
/// and CoreBluetooth link to the Tripper Pod remain 100% active when the rider exits the app,
/// switches to Spotify, receives an incoming phone call, or locks the iPhone screen.
public final class BackgroundKeepAliveService: @unchecked Sendable {
    public static let shared = BackgroundKeepAliveService()
    
    private var audioPlayer: AVAudioPlayer?
    #if canImport(UIKit)
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    #endif
    private var isKeepAliveActive: Bool = false
    private var watchdogTimer: DispatchSourceTimer?
    private let watchdogQueue = DispatchQueue(label: "com.tripperdash.keepalive.watchdog", qos: .userInitiated)
    
    private init() {
        setupAudioSession()
        setupLifecycleObservers()
    }
    
    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            // .mixWithOthers ONLY (no .duckOthers) so background keep-alive never lowers Spotify/Apple Music volume
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("BackgroundKeepAliveService audio session error: \(error)")
        }
        #endif
    }
    
    private func setupLifecycleObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidEnterBackground()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWillEnterForeground()
        }
        
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self = self, self.isKeepAliveActive else { return }
            let typeVal = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if typeVal == AVAudioSession.InterruptionType.ended.rawValue {
                self.ensureAudioAndLocationAlive()
            }
            // Even during an incoming call interruption, immediately force a fresh TFT video frame
            // so the Incoming Call card renders on the bike screen!
            TFTProjectionService.shared.triggerImmediateFrame()
        }
        
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isKeepAliveActive else { return }
            self.ensureAudioAndLocationAlive()
        }
        
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isKeepAliveActive else { return }
            self.audioPlayer = nil
            self.ensureAudioAndLocationAlive()
        }
        #endif
    }
    
    // MARK: - Keep-Alive Activation
    
    public func startKeepAlive() {
        isKeepAliveActive = true
        
        // 1. Activate Background Location keep-alive (survives phone call audio interruptions & app switching!)
        LocationTracker.shared?.setBackgroundKeepAlive(true)
        
        // 2. Activate silent mixed audio player
        ensureAudioAndLocationAlive()
        
        // 3. Start 3-second background watchdog to auto-recover audio player & rotate background task assertions
        startWatchdogTimer()
    }
    
    public func stopKeepAlive() {
        isKeepAliveActive = false
        stopWatchdogTimer()
        audioPlayer?.stop()
        LocationTracker.shared?.setBackgroundKeepAlive(false)
        endBackgroundTask()
    }
    
    private func ensureAudioAndLocationAlive() {
        guard isKeepAliveActive else { return }
        setupAudioSession()
        
        if audioPlayer == nil {
            let silentAudioData = createSilentAudioWAVData()
            do {
                let player = try AVAudioPlayer(data: silentAudioData)
                player.numberOfLoops = -1
                player.volume = 0.01
                player.prepareToPlay()
                self.audioPlayer = player
            } catch {
                print("Failed to initialize silent audio player: \(error)")
            }
        }
        
        if !(audioPlayer?.isPlaying ?? false) {
            audioPlayer?.play()
        }
        
        LocationTracker.shared?.setBackgroundKeepAlive(true)
    }
    
    private func startWatchdogTimer() {
        stopWatchdogTimer()
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + 3.0, repeating: .seconds(3))
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isKeepAliveActive else { return }
            DispatchQueue.main.async {
                self.ensureAudioAndLocationAlive()
                #if canImport(UIKit)
                if UIApplication.shared.applicationState != .active {
                    self.rotateBackgroundTaskAssertion()
                }
                #endif
            }
        }
        timer.resume()
        self.watchdogTimer = timer
    }
    
    private func stopWatchdogTimer() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }
    
    // MARK: - Background Task Assertion Rotation
    
    private func handleDidEnterBackground() {
        guard isKeepAliveActive else { return }
        ensureAudioAndLocationAlive()
        rotateBackgroundTaskAssertion()
        TFTProjectionService.shared.handleAppDidEnterBackground()
    }
    
    private func handleWillEnterForeground() {
        guard isKeepAliveActive else { return }
        ensureAudioAndLocationAlive()
        endBackgroundTask()
        TFTProjectionService.shared.handleAppWillEnterForeground()
    }
    
    private func rotateBackgroundTaskAssertion() {
        #if canImport(UIKit)
        let oldTask = backgroundTaskIdentifier
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "TripperDashSocketKeepAlive") { [weak self] in
            self?.endBackgroundTask()
        }
        if oldTask != .invalid {
            UIApplication.shared.endBackgroundTask(oldTask)
        }
        #endif
    }
    
    private func endBackgroundTask() {
        #if canImport(UIKit)
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
        #endif
    }
    
    // MARK: - In-Memory Silent WAV Generator
    
    private func createSilentAudioWAVData() -> Data {
        let sampleRate: Int32 = 44100
        let channels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let durationSeconds: Int = 1
        let numSamples = Int(sampleRate) * durationSeconds
        let dataSize = Int32(numSamples * Int(channels) * Int(bitsPerSample / 8))
        let fileSize = 36 + dataSize
        
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        let fmtChunkSize: Int32 = 16
        let audioFormat: Int16 = 1
        let byteRate: Int32 = sampleRate * Int32(channels) * Int32(bitsPerSample / 8)
        let blockAlign: Int16 = channels * (bitsPerSample / 8)
        data.append(withUnsafeBytes(of: fmtChunkSize.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: audioFormat.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        data.append(contentsOf: "data".utf8)
        data.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        data.append(Data(count: Int(dataSize)))
        return data
    }
}
