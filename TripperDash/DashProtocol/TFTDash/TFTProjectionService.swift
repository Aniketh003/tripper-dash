import Foundation
import SwiftUI
import CoreGraphics
import CoreVideo
import CoreMedia
import VideoToolbox
import Darwin

// MARK: - Circular Himalayan 450 TFT Digital Homescreen Canvas
/// Renders the exact Digital Mode Homescreen projected to the bike's round TFT cluster
/// (and used directly as the live interactive TFT Preview inside Cockpit & Settings).
public struct TFTHomescreenCanvas: View {
    public let speedKmh: Double
    public let heading: Double
    public let weatherTempC: Int
    public let weatherCondition: String
    public let weatherSymbol: String
    public let weatherLocation: String
    public let windKmh: Int
    public let songTitle: String
    public let songArtist: String
    public let isMusicPlaying: Bool
    public let volumePercent: Int
    public let batteryPercent: Int
    public let isCallRinging: Bool
    public let isCallOngoing: Bool
    public let callerName: String
    public let callDuration: String
    public let showWeather: Bool
    public let showMusic: Bool
    public let showSpeed: Bool
    public let activeNavInstruction: String?
    public let activeNavDistanceMeters: Int?
    
    public init(
        speedKmh: Double,
        heading: Double,
        weatherTempC: Int,
        weatherCondition: String,
        weatherSymbol: String,
        weatherLocation: String,
        windKmh: Int,
        songTitle: String,
        songArtist: String,
        isMusicPlaying: Bool,
        volumePercent: Int,
        batteryPercent: Int,
        isCallRinging: Bool,
        isCallOngoing: Bool,
        callerName: String,
        callDuration: String,
        showWeather: Bool = true,
        showMusic: Bool = true,
        showSpeed: Bool = true,
        activeNavInstruction: String? = nil,
        activeNavDistanceMeters: Int? = nil
    ) {
        self.speedKmh = speedKmh
        self.heading = heading
        self.weatherTempC = weatherTempC
        self.weatherCondition = weatherCondition
        self.weatherSymbol = weatherSymbol
        self.weatherLocation = weatherLocation
        self.windKmh = windKmh
        self.songTitle = songTitle
        self.songArtist = songArtist
        self.isMusicPlaying = isMusicPlaying
        self.volumePercent = volumePercent
        self.batteryPercent = batteryPercent
        self.isCallRinging = isCallRinging
        self.isCallOngoing = isCallOngoing
        self.callerName = callerName
        self.callDuration = callDuration
        self.showWeather = showWeather
        self.showMusic = showMusic
        self.showSpeed = showSpeed
        self.activeNavInstruction = activeNavInstruction
        self.activeNavDistanceMeters = activeNavDistanceMeters
    }
    
    private var currentTimeString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: Date())
    }
    
    private var compassText: String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return dirs[Int((heading + 22.5) / 45.0) & 7]
    }
    
    public var body: some View {
        ZStack {
            // Pure OLED Black Background with subtle ambient radial glow
            RadialGradient(
                colors: [
                    (isCallRinging ? Color.green : (isCallOngoing ? Color.orange : Color(red: 0.14, green: 0.14, blue: 0.18))).opacity(0.28),
                    Color.black
                ],
                center: .center,
                startRadius: 10,
                endRadius: 165
            )
            
            VStack(spacing: 10) {
                // Top Arc Status: Time + Weather + Battery
                HStack(spacing: 12) {
                    Text(currentTimeString)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white.opacity(0.85))
                    
                    if showWeather {
                        HStack(spacing: 4) {
                            Image(systemName: weatherSymbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(red: 1.0, green: 0.62, blue: 0.04))
                            Text("\(weatherTempC)°")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    
                    HStack(spacing: 3) {
                        Image(systemName: "battery.75percent")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 0.19, green: 0.82, blue: 0.35))
                        Text("\(batteryPercent)%")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
                .padding(.top, 18)
                
                Spacer(minLength: 2)
                
                // Center Stage: Call Alert OR Active Nav OR Digital Homescreen (Speed + Weather Details)
                if isCallRinging || isCallOngoing {
                    VStack(spacing: 6) {
                        Image(systemName: isCallRinging ? "phone.down.waves.left.and.right" : "phone.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(isCallRinging ? Color(red: 0.19, green: 0.82, blue: 0.35) : Color(red: 1.0, green: 0.62, blue: 0.04))
                        
                        Text(callerName)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(isCallRinging ? "↑ / ● Answer   ·   ↓ Decline" : callDuration)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(isCallRinging ? Color.white.opacity(0.7) : Color(red: 0.19, green: 0.82, blue: 0.35))
                    }
                    .padding(.horizontal, 16)
                } else if let navText = activeNavInstruction, let dist = activeNavDistanceMeters {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.turn.up.right")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(Color(red: 1.0, green: 0.62, blue: 0.04))
                        
                        Text(dist >= 1000 ? String(format: "%.1f km", Double(dist) / 1000.0) : "\(dist) m")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                        
                        Text(navText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 20)
                } else {
                    VStack(spacing: 4) {
                        if showSpeed {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.0f", speedKmh))
                                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(.white)
                                Text("km/h")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                        
                        if showWeather {
                            HStack(spacing: 6) {
                                Text(weatherCondition)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                                Text("·")
                                    .foregroundColor(.white.opacity(0.4))
                                Text(weatherLocation)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(.white.opacity(0.65))
                                Text("·")
                                    .foregroundColor(.white.opacity(0.4))
                                Text(compassText)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(Color(red: 1.0, green: 0.62, blue: 0.04))
                            }
                            .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer(minLength: 2)
                
                // Bottom Band: Now Playing Song + Live Volume Indicator
                if showMusic {
                    VStack(spacing: 5) {
                        HStack(spacing: 6) {
                            Image(systemName: isMusicPlaying ? "waveform" : "music.note")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(isMusicPlaying ? Color(red: 1.0, green: 0.62, blue: 0.04) : .white.opacity(0.45))
                            
                            Text(songTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            if !songArtist.isEmpty {
                                Text("— \(songArtist)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.55))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        // Compact Volume Bar
                        HStack(spacing: 6) {
                            Image(systemName: volumePercent == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.5))
                            
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 84, height: 3.5)
                                Capsule()
                                    .fill(Color(red: 1.0, green: 0.62, blue: 0.04))
                                    .frame(width: max(4, 84.0 * CGFloat(volumePercent) / 100.0), height: 3.5)
                            }
                            
                            Text("\(volumePercent)%")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                    .padding(.bottom, 20)
                } else {
                    Spacer().frame(height: 16)
                }
            }
        }
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
        )
    }
}

// MARK: - H.264 RTP Video Projection Streamer (UDP Port 5000 → Himalayan 450 TFT)
@Observable
public final class TFTProjectionService: @unchecked Sendable {
    public static let shared = TFTProjectionService()
    
    public var isStreaming: Bool = false
    public var framesSent: Int = 0
    public var currentFPS: Double = 0.0
    
    private let width: Int32 = 526
    private let height: Int32 = 300
    private var compressionSession: VTCompressionSession?
    private var videoSocketFD: Int32 = -1
    private var renderTimer: Timer?
    private var rtpSequenceNumber: UInt16 = 0
    private var rtpTimestamp: UInt32 = 0
    private let rtpSSRC: UInt32 = 0x52453435 // "RE45"
    private var targetIP: String = "192.168.1.1"
    private var targetPort: UInt16 = DashK1GProtocol.bikeVideoPort // 5000
    private var lastFrameCountReset: Date = Date()
    private var framesInWindow: Int = 0
    
    private weak var trackerRef: LocationTracker?
    
    private init() {}
    
    public func attachTracker(_ tracker: LocationTracker) {
        self.trackerRef = tracker
    }
    
    public func startStreaming(to ip: String, port: UInt16 = DashK1GProtocol.bikeVideoPort) {
        stopStreaming()
        
        self.targetIP = ip
        self.targetPort = port
        
        // Open UDP Socket for RTP Video Stream (Port 5000)
        videoSocketFD = socket(AF_INET, SOCK_DGRAM, 0)
        guard videoSocketFD >= 0 else {
            TripperDashClient.shared.log("⚠️ Video projection socket failed to open.")
            return
        }
        
        setupH264Encoder()
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isStreaming = true
            self.framesSent = 0
            self.framesInWindow = 0
            self.lastFrameCountReset = Date()
            
            // Stream at 4 FPS for Digital Homescreen (crisp, ultra low battery & Wi-Fi overhead)
            self.renderTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.captureAndEncodeFrame()
                }
            }
        }
        
        TripperDashClient.shared.log("📺 TFT Digital Homescreen H.264 stream started → \(ip):\(port) (526×300 @ 4 fps)")
    }
    
    public func stopStreaming() {
        DispatchQueue.main.async {
            self.renderTimer?.invalidate()
            self.renderTimer = nil
            self.isStreaming = false
            self.currentFPS = 0.0
        }
        
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        
        if videoSocketFD >= 0 {
            close(videoSocketFD)
            videoSocketFD = -1
        }
    }
    
    // MARK: - VideoToolbox H.264 Baseline Profile 3.0 Setup
    private func setupH264Encoder() {
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        
        guard status == noErr, let session = session else {
            print("VTCompressionSessionCreate failed: \(status)")
            return
        }
        
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_3_0)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: 300_000 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 4 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 8 as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(session)
        
        self.compressionSession = session
    }
    
    // MARK: - Render SwiftUI TFT Homescreen → CVPixelBuffer → H.264 RTP
    @MainActor
    private func captureAndEncodeFrame() {
        guard isStreaming, let session = compressionSession else { return }
        
        let client = TripperDashClient.shared
        let weather = WeatherService.shared
        let media = MediaPlaybackService.shared
        let call = CallHandlingService.shared
        let battery = BatteryOptimizationService.shared
        let speed = trackerRef?.currentSpeedKmh ?? 0
        let heading = trackerRef?.currentHeading ?? 0
        
        let canvas = ZStack {
            Color.black
            TFTHomescreenCanvas(
                speedKmh: speed,
                heading: heading,
                weatherTempC: weather.temperatureC,
                weatherCondition: weather.conditionText,
                weatherSymbol: weather.symbolName,
                weatherLocation: weather.locationName,
                windKmh: weather.windSpeedKmh,
                songTitle: media.currentTitle,
                songArtist: media.currentArtist,
                isMusicPlaying: media.isPlaying,
                volumePercent: media.volumePercent,
                batteryPercent: battery.batteryLevelPercent,
                isCallRinging: call.isRinging,
                isCallOngoing: call.isOngoing,
                callerName: call.callerName,
                callDuration: call.formattedDuration,
                showWeather: client.showWeatherOnTFT,
                showMusic: client.showMusicOnTFT,
                showSpeed: client.showSpeedOnTFT,
                activeNavInstruction: client.isNavigationActive ? client.activeNavStreet : nil,
                activeNavDistanceMeters: client.isNavigationActive ? client.activeNavDistanceMeters : nil
            )
            .frame(width: 296, height: 296)
        }
        .frame(width: CGFloat(width), height: CGFloat(height))
        
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1.0
        
        guard let cgImage = renderer.cgImage,
              let pixelBuffer = makePixelBuffer(from: cgImage, width: Int(width), height: Int(height)) else {
            return
        }
        
        let pts = CMTime(value: CMTimeValue(framesSent), timescale: 4)
        let duration = CMTime(value: 1, timescale: 4)
        
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: duration,
            frameProperties: nil,
            infoFlagsOut: nil
        ) { [weak self] status, _, sampleBuffer in
            guard let self = self, status == noErr, let sampleBuffer = sampleBuffer else { return }
            self.packetizeAndSendRTP(sampleBuffer: sampleBuffer)
        }
    }
    
    private func makePixelBuffer(from cgImage: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
    
    // MARK: - RFC 6184 H.264 over RTP Packetizer (Max 1380B payload → UDP/5000)
    private func packetizeAndSendRTP(sampleBuffer: CMSampleBuffer) {
        guard videoSocketFD >= 0 else { return }
        
        // 1. Check if keyframe and emit SPS & PPS NALUs first
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
           let first = attachments.first,
           (first[kCMSampleAttachmentKey_NotSync] as? Bool) != true,
           let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            
            var spsPtr: UnsafePointer<UInt8>?
            var spsSize: Int = 0
            if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 0, parameterSetPointerOut: &spsPtr, parameterSetSizeOut: &spsSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
               let spsPtr = spsPtr {
                sendNALU(Data(bytes: spsPtr, count: spsSize), isLastOfFrame: false)
            }
            
            var ppsPtr: UnsafePointer<UInt8>?
            var ppsSize: Int = 0
            if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 1, parameterSetPointerOut: &ppsPtr, parameterSetSizeOut: &ppsSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
               let ppsPtr = ppsPtr {
                sendNALU(Data(bytes: ppsPtr, count: ppsSize), isLastOfFrame: false)
            }
        }
        
        // 2. Extract AVCC length-prefixed NALUs from CMBlockBuffer
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
              let basePtr = dataPointer else { return }
        
        var offset = 0
        while offset + 4 <= totalLength {
            var naluLen: UInt32 = 0
            memcpy(&naluLen, basePtr.advanced(by: offset), 4)
            naluLen = CFSwapInt32BigToHost(naluLen)
            offset += 4
            
            let len = Int(naluLen)
            guard len > 0, offset + len <= totalLength else { break }
            let isLast = (offset + len >= totalLength)
            let nalu = Data(bytes: basePtr.advanced(by: offset), count: len)
            sendNALU(nalu, isLastOfFrame: isLast)
            offset += len
        }
        
        rtpTimestamp = rtpTimestamp &+ (90_000 / 4) // 90 kHz RTP clock @ 4 fps
        
        DispatchQueue.main.async {
            self.framesSent += 1
            self.framesInWindow += 1
            let elapsed = Date().timeIntervalSince(self.lastFrameCountReset)
            if elapsed >= 2.0 {
                self.currentFPS = Double(self.framesInWindow) / elapsed
                self.framesInWindow = 0
                self.lastFrameCountReset = Date()
            }
        }
    }
    
    private func sendNALU(_ nalu: Data, isLastOfFrame: Bool) {
        let maxPayload = 1360 // Safe under 1380B MTU cap
        if nalu.count <= maxPayload {
            sendRTPPacket(payload: nalu, marker: isLastOfFrame)
        } else {
            // FU-A Fragmentation per RFC 6184
            let naluHeader = nalu[0]
            let fuIndicator = (naluHeader & 0xE0) | 28 // Type 28 = FU-A
            let naluType = naluHeader & 0x1F
            
            var offset = 1
            let maxFrag = maxPayload - 2
            while offset < nalu.count {
                let end = min(offset + maxFrag, nalu.count)
                let isStart = (offset == 1)
                let isEnd = (end == nalu.count)
                
                var fuHeader = naluType
                if isStart { fuHeader |= 0x80 }
                if isEnd { fuHeader |= 0x40 }
                
                var frag = Data(capacity: 2 + (end - offset))
                frag.append(fuIndicator)
                frag.append(fuHeader)
                frag.append(nalu.subdata(in: offset..<end))
                
                sendRTPPacket(payload: frag, marker: isEnd && isLastOfFrame)
                offset = end
            }
        }
    }
    
    private func sendRTPPacket(payload: Data, marker: Bool) {
        var packet = Data(capacity: 12 + payload.count)
        let seq = rtpSequenceNumber
        rtpSequenceNumber = rtpSequenceNumber &+ 1
        
        packet.append(0x80) // V=2, P=0, X=0, CC=0
        packet.append(marker ? (0x80 | 96) : 96) // M + Dynamic Payload Type 96 (H264)
        packet.append(UInt8(seq >> 8))
        packet.append(UInt8(seq & 0xFF))
        packet.append(UInt8((rtpTimestamp >> 24) & 0xFF))
        packet.append(UInt8((rtpTimestamp >> 16) & 0xFF))
        packet.append(UInt8((rtpTimestamp >> 8) & 0xFF))
        packet.append(UInt8(rtpTimestamp & 0xFF))
        packet.append(UInt8((rtpSSRC >> 24) & 0xFF))
        packet.append(UInt8((rtpSSRC >> 16) & 0xFF))
        packet.append(UInt8((rtpSSRC >> 8) & 0xFF))
        packet.append(UInt8(rtpSSRC & 0xFF))
        packet.append(payload)
        
        var destAddr = sockaddr_in()
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = targetPort.bigEndian
        inet_pton(AF_INET, targetIP, &destAddr.sin_addr)
        
        packet.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            withUnsafePointer(to: &destAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = sendto(videoSocketFD, base, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}
