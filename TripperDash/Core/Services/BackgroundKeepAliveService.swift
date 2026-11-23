import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// Manages background execution preservation to guarantee that the Wi-Fi UDP socket
/// to the motorcycle's TFT Dash and the CoreBluetooth link to the Tripper Pod remain
/// 100% connected even when the rider locks or turns off the iPhone display.
public final class BackgroundKeepAliveService: @unchecked Sendable {
    public static let shared = BackgroundKeepAliveService()
    
    private var audioPlayer: AVAudioPlayer?
    #if canImport(UIKit)
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    #endif
    private var isKeepAliveActive: Bool = false
    
    private init() {
        setupAudioSession()
        setupLifecycleObservers()
    }
    
    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers, .duckOthers])
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
        #endif
    }
    
    // MARK: - Keep-Alive Activation
    
    /// Starts background keep-alive loop so iOS won't suspend sockets when the screen is locked
    public func startKeepAlive() {
        guard !isKeepAliveActive else { return }
        isKeepAliveActive = true
        
        // Prepare silent audio player to maintain active audio/network run loop
        if audioPlayer == nil {
            // Generate a 1-second silent WAV in memory
            let silentAudioData = createSilentAudioWAVData()
            do {
                audioPlayer = try AVAudioPlayer(data: silentAudioData)
                audioPlayer?.numberOfLoops = -1 // Infinite loop
                audioPlayer?.volume = 0.01 // Inaudible
                audioPlayer?.prepareToPlay()
            } catch {
                print("Failed to initialize silent audio player: \(error)")
            }
        }
        
        audioPlayer?.play()
    }
    
    public func stopKeepAlive() {
        isKeepAliveActive = false
        audioPlayer?.stop()
        endBackgroundTask()
    }
    
    // MARK: - Background Task Assertion
    
    private func handleDidEnterBackground() {
        guard isKeepAliveActive else { return }
        
        #if canImport(UIKit)
        // Request background execution assertion from iOS
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "TripperDashSocketKeepAlive") { [weak self] in
            self?.endBackgroundTask()
        }
        #endif
    }
    
    private func handleWillEnterForeground() {
        endBackgroundTask()
    }
    
    private func endBackgroundTask() {
        #if canImport(UIKit)
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
        #endif
    }
    
    // MARK: - In-Memory Silent WAV Generator (Zero external assets needed)
    
    private func createSilentAudioWAVData() -> Data {
        let sampleRate: Int32 = 44100
        let channels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let durationSeconds: Int = 1
        let numSamples = Int(sampleRate) * durationSeconds
        let dataSize = Int32(numSamples * Int(channels) * Int(bitsPerSample / 8))
        let totalSize = 36 + dataSize
        
        var header = Data()
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        header.append(contentsOf: withUnsafeBytes(of: totalSize.littleEndian) { Array($0) })
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        
        let formatChunkSize: Int32 = 16
        header.append(contentsOf: withUnsafeBytes(of: formatChunkSize.littleEndian) { Array($0) })
        
        let formatType: Int16 = 1 // PCM
        header.append(contentsOf: withUnsafeBytes(of: formatType.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: channels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        
        let byteRate: Int32 = sampleRate * Int32(channels) * Int32(bitsPerSample / 8)
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        
        let blockAlign: Int16 = channels * (bitsPerSample / 8)
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        
        // Silent PCM samples (all zeros)
        let silence = Data(repeating: 0, count: Int(dataSize))
        return header + silence
    }
}
