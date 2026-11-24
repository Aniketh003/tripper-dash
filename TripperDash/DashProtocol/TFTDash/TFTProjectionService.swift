import Foundation
import SwiftUI
import CoreLocation
import CoreGraphics
import CoreVideo
import CoreMedia
import VideoToolbox
import Darwin
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Exact Royal Enfield Himalayan 450 TFT Dome Geometry (DashGlass 526×300)
/// Measured on physical hardware: the round TFT glass is 526 px across, centered at (263, 263) with radius 263.
/// The 526×300 video surface occupies the upper 300 rows of that 526 px circle (the bike's native
/// hardware speedometer, gear & fuel band sits below y = 300).
public struct DashGlassDomeShape: Shape {
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 526.0
        let scaleY = rect.height / 300.0
        let scale = min(scaleX, scaleY)
        let cx = rect.midX
        let cy = 263.0 * scaleY
        let r = 263.0 * scale
        
        var path = Path()
        path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        return path.intersection(Path(rect))
    }
}

// MARK: - Himalayan 450 TFT Digital Homescreen Canvas (526×300 Dome, No Speedometer)
/// Renders the clean Digital Mode Homescreen projected to the bike's 526×300 TFT dome.
/// When `forDashStream == true`, no artificial border is drawn because the physical TFT bezel IS the circle.
public struct TFTHomescreenCanvas: View {
    public let heading: Double
    public let weatherLoaded: Bool
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
    public let isCharging: Bool
    public let isCallRinging: Bool
    public let isCallOngoing: Bool
    public let callerName: String
    public let callDuration: String
    public let showWeather: Bool
    public let showMusic: Bool
    public let activeNavInstruction: String?
    public let activeNavDistanceMeters: Int?
    public let forDashStream: Bool
    
    public init(
        heading: Double,
        weatherLoaded: Bool,
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
        isCharging: Bool = false,
        isCallRinging: Bool,
        isCallOngoing: Bool,
        callerName: String,
        callDuration: String,
        showWeather: Bool = true,
        showMusic: Bool = true,
        activeNavInstruction: String? = nil,
        activeNavDistanceMeters: Int? = nil,
        forDashStream: Bool = false
    ) {
        self.heading = heading
        self.weatherLoaded = weatherLoaded
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
        self.isCharging = isCharging
        self.isCallRinging = isCallRinging
        self.isCallOngoing = isCallOngoing
        self.callerName = callerName
        self.callDuration = callDuration
        self.showWeather = showWeather
        self.showMusic = showMusic
        self.activeNavInstruction = activeNavInstruction
        self.activeNavDistanceMeters = activeNavDistanceMeters
        self.forDashStream = forDashStream
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
    
    @ViewBuilder
    private func wallpaperBackground(style: TFTWallpaperStyle, dimming: Double) -> some View {
        switch style {
        case .pureBlack:
            RadialGradient(
                colors: [
                    Color(red: 0.12, green: 0.14, blue: 0.20).opacity(0.24),
                    Color.black
                ],
                center: UnitPoint(x: 0.5, y: 0.72),
                startRadius: 12,
                endRadius: 230
            )
        case .apexGold:
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.26, green: 0.18, blue: 0.04), Color(red: 0.06, green: 0.05, blue: 0.03), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                RadialGradient(
                    colors: [amber.opacity(0.32), Color.clear],
                    center: UnitPoint(x: 0.5, y: 0.25),
                    startRadius: 8,
                    endRadius: 240
                )
                Color.black.opacity(dimming * 0.6)
            }
        case .sherpaDusk:
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.34, green: 0.11, blue: 0.14), Color(red: 0.16, green: 0.08, blue: 0.18), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Color.black.opacity(dimming * 0.6)
            }
        case .midnightMesh:
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.16, blue: 0.32), Color(red: 0.03, green: 0.07, blue: 0.16), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Color.black.opacity(dimming * 0.6)
            }
        case .customPhoto:
            ZStack {
                #if canImport(UIKit)
                if let uiImg = TFTProjectionService.shared.cachedCustomWallpaperImage {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 526, height: 300)
                        .clipped()
                } else {
                    Color.black
                }
                #else
                Color.black
                #endif
                Color.black.opacity(dimming)
            }
        }
    }
    
    private let amber = Color(red: 1.0, green: 0.62, blue: 0.04)
    private let emerald = Color(red: 0.19, green: 0.82, blue: 0.35)
    
    public var body: some View {
        let client = TripperDashClient.shared
        ZStack {
            // Pure OLED Black base so outer corners blend invisibly into the bike's round TFT bezel
            Color.black
            
            // Wallpaper Layer (Custom Photo or Curated OLED Theme)
            wallpaperBackground(style: client.wallpaperStyle, dimming: client.wallpaperDimming)
            
            // Content strictly positioned inside the 526×300 upper circular dome (center = 263, 263; radius = 263)
            VStack(spacing: 10) {
                // 1. Top Dome Status Pill (y ≈ 38..66, where dome chord width > 290 px)
                HStack(spacing: 12) {
                    Text(currentTimeString)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.white)
                    
                    Text("·")
                        .foregroundColor(.white.opacity(0.35))
                    
                    HStack(spacing: 4) {
                        Image(systemName: compassText == "N" ? "location.north.fill" : "location.north")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(amber)
                        Text(compassText)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(amber)
                    }
                    
                    Text("·")
                        .foregroundColor(.white.opacity(0.35))
                    
                    HStack(spacing: 4) {
                        Image(systemName: isCharging ? "battery.100percent.bolt" : "battery.75percent")
                            .font(.system(size: 12))
                            .foregroundColor(emerald)
                        Text("\(batteryPercent)%")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .padding(.top, 34)
                
                // 2. Main Dome Area (y ≈ 76..288)
                if isCallRinging || isCallOngoing {
                    callOverlayCard
                } else if let navText = activeNavInstruction, !navText.isEmpty, let dist = activeNavDistanceMeters {
                    activeNavigationCard(instruction: navText, distanceMeters: dist)
                } else {
                    digitalHomescreenContent
                }
                
                Spacer(minLength: 8)
            }
            .frame(width: 526, height: 300)
        }
        .frame(width: 526, height: 300)
        .clipShape(DashGlassDomeShape())
        .overlay {
            if !forDashStream {
                DashGlassDomeShape()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.24), Color.white.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
            }
        }
    }
    
    // MARK: - Clean Digital Homescreen (Weather + Now Playing Music & Volume, Zero Speedometer)
    private var digitalHomescreenContent: some View {
        VStack(spacing: 10) {
            // Live Outdoor Weather Bar
            if showWeather {
                HStack(spacing: 10) {
                    Image(systemName: weatherLoaded ? weatherSymbol : "location.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(amber)
                    
                    if weatherLoaded {
                        Text("\(weatherTempC)°C")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(weatherCondition)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.92))
                                .lineLimit(1)
                            
                            Text(weatherLocation.isEmpty ? "Wind \(windKmh) km/h" : "\(weatherLocation) · Wind \(windKmh) km/h")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.58))
                                .lineLimit(1)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Waiting for GPS Weather")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.85))
                            Text("Live local temperature & wind will appear shortly")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(width: 390)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            
            // Live Now Playing Music & Volume Card
            if showMusic {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(isMusicPlaying ? amber.opacity(0.20) : Color.white.opacity(0.08))
                                .frame(width: 44, height: 44)
                            Image(systemName: isMusicPlaying ? "waveform" : "music.note")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(isMusicPlaying ? amber : .white.opacity(0.55))
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(songTitle)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            
                            Text(songArtist.isEmpty ? (isMusicPlaying ? "Playing on iPhone" : "Paused · Use Joystick to Control") : songArtist)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        // Playback Status Badge
                        Text(isMusicPlaying ? "PLAYING" : "PAUSED")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(isMusicPlaying ? .black : .white.opacity(0.7))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(isMusicPlaying ? amber : Color.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    
                    // Crisp Live System Volume Bar
                    HStack(spacing: 10) {
                        Image(systemName: volumePercent == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.6))
                        
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.14))
                                    .frame(height: 6)
                                Capsule()
                                    .fill(amber)
                                    .frame(width: max(6, geo.size.width * CGFloat(volumePercent) / 100.0), height: 6)
                            }
                        }
                        .frame(height: 6)
                        
                        Text("\(volumePercent)%")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(width: 448)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }
    
    // MARK: - Incoming / Ongoing Call Card (Borderless Minimal OLED Card)
    private var resolvedCallTitle: String {
        let trimmed = callerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCallOngoing {
            if trimmed.isEmpty || trimmed == "Incoming Call" || trimmed == "Outgoing Call" || trimmed == "Active Call" {
                return "Ongoing Call"
            }
            return trimmed
        }
        return trimmed.isEmpty ? "Incoming Call" : trimmed
    }
    
    private var callOverlayCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill((isCallRinging ? emerald : amber).opacity(0.22))
                        .frame(width: 50, height: 50)
                    Image(systemName: isCallRinging ? "phone.down.waves.left.and.right" : "phone.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(isCallRinging ? emerald : amber)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(isCallRinging ? "INCOMING CALL" : "ONGOING CALL · \(callDuration)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(isCallRinging ? emerald : amber)
                    
                    Text(resolvedCallTitle)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            
            Text(isCallRinging ? "Joystick ← / ↑ / ● to Answer   ·   → / ↓ to Reject" : "Joystick ● / ← / → / ↓ to End Call")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: 440)
        .background(Color.white.opacity(0.085))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    
    // MARK: - Live Moving Vector Navigation Map + Turn HUD (Shown when a route is actively being navigated)
    private func activeNavigationCard(instruction: String, distanceMeters: Int) -> some View {
        let nav = NavigationEngine.shared
        let client = TripperDashClient.shared
        let stepIcon = nav.currentStep?.maneuver.iconName ?? "location.north.line.fill"
        let totalRemMeters = max(distanceMeters, client.activeNavTotalDistanceMeters)
        let totalRemStr = totalRemMeters >= 1000 ? String(format: "%.1f km", Double(totalRemMeters) / 1000.0) : "\(totalRemMeters) m"
        let etaStr = client.activeNavEtaText.isEmpty ? nav.etaFormatted : client.activeNavEtaText
        
        return ZStack {
            // 1. Live Heading-Up Vector Route Map Canvas
            Canvas { context, size in
                let puckCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.78)
                
                // Subtle radar range rings around the motorcycle puck
                for radius in [55.0, 105.0, 155.0] {
                    let ringRect = CGRect(x: puckCenter.x - radius, y: puckCenter.y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: ringRect), with: .color(.white.opacity(0.06)), lineWidth: 1)
                }
                
                let coords = nav.decodedCoordinates
                if coords.count >= 2 {
                    let anchor = nav.riderCoordinate ?? coords[min(nav.closestPolylineIndex, coords.count - 1)]
                    let headingRad = nav.riderHeadingDegrees * .pi / 180.0
                    let cosH = cos(headingRad)
                    let sinH = sin(headingRad)
                    let metersPerDegLat = 111_132.0
                    let metersPerDegLng = 111_320.0 * max(0.2, cos(anchor.latitude * .pi / 180.0))
                    let pxPerMeter = distanceMeters < 220 ? 0.48 : 0.24
                    
                    func project(_ c: CLLocationCoordinate2D) -> CGPoint {
                        let eastM = (c.longitude - anchor.longitude) * metersPerDegLng
                        let northM = (c.latitude - anchor.latitude) * metersPerDegLat
                        // Rotate into Rider Heading-Up frame (forward = -Y, right = +X)
                        let rightM = eastM * cosH - northM * sinH
                        let fwdM = eastM * sinH + northM * cosH
                        return CGPoint(
                            x: puckCenter.x + CGFloat(rightM * pxPerMeter),
                            y: puckCenter.y - CGFloat(fwdM * pxPerMeter)
                        )
                    }
                    
                    let splitIdx = min(max(0, nav.closestPolylineIndex), coords.count - 1)
                    var upcomingPath = Path()
                    let startPt = project(anchor)
                    upcomingPath.move(to: startPt)
                    let endIdx = min(coords.count - 1, splitIdx + 90)
                    for i in splitIdx...endIdx {
                        upcomingPath.addLine(to: project(coords[i]))
                    }
                    
                    // Glowing route road casing & active path
                    context.stroke(upcomingPath, with: .color(.black.opacity(0.85)), style: StrokeStyle(lineWidth: 13, lineCap: .round, lineJoin: .round))
                    context.stroke(upcomingPath, with: .color(amber), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    
                    // Turn waypoint marker
                    if let step = nav.currentStep, let tLat = step.endLatitude, let tLng = step.endLongitude {
                        let turnPt = project(CLLocationCoordinate2D(latitude: tLat, longitude: tLng))
                        let markerRect = CGRect(x: turnPt.x - 7, y: turnPt.y - 7, width: 14, height: 14)
                        context.fill(Path(ellipseIn: markerRect), with: .color(.white))
                        context.stroke(Path(ellipseIn: markerRect.insetBy(dx: -3, dy: -3)), with: .color(amber), lineWidth: 2.5)
                    }
                }
                
                // Rider Directional Navigation Arrow Puck at puckCenter
                let haloRect = CGRect(x: puckCenter.x - 16, y: puckCenter.y - 16, width: 32, height: 32)
                context.fill(Path(ellipseIn: haloRect), with: .color(emerald.opacity(0.24)))
                var arrow = Path()
                arrow.move(to: CGPoint(x: puckCenter.x, y: puckCenter.y - 12))
                arrow.addLine(to: CGPoint(x: puckCenter.x + 9, y: puckCenter.y + 9))
                arrow.addLine(to: CGPoint(x: puckCenter.x, y: puckCenter.y + 4))
                arrow.addLine(to: CGPoint(x: puckCenter.x - 9, y: puckCenter.y + 9))
                arrow.closeSubpath()
                context.fill(arrow, with: .color(emerald))
                context.stroke(arrow, with: .color(.white), lineWidth: 1.8)
            }
            .frame(width: 468, height: 210)
            .background(Color(red: 0.04, green: 0.07, blue: 0.12).opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            
            // 2. Top Turn-by-Turn Instruction Banner + Bottom-Right ETA Pill
            VStack {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(amber)
                            .frame(width: 44, height: 44)
                        Image(systemName: stepIcon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.black)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(distanceMeters >= 1000 ? String(format: "%.1f km", Double(distanceMeters) / 1000.0) : "\(distanceMeters) m")
                                .font(.system(size: 22, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white)
                            
                            // 6-Bar Proximity Indicator
                            let prox = Int(DashK1GProtocol.proximityLevel(meters: distanceMeters))
                            if prox > 0 {
                                HStack(spacing: 2) {
                                    ForEach(0..<6, id: \.self) { idx in
                                        Capsule()
                                            .fill(idx < prox ? amber : Color.white.opacity(0.18))
                                            .frame(width: 5, height: 8)
                                    }
                                }
                            }
                        }
                        
                        Text(instruction)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.88))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(amber.opacity(0.45), lineWidth: 1)
                )
                .padding(.horizontal, 14)
                .padding(.top, 8)
                
                Spacer()
                
                HStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(emerald)
                        Text(etaStr.isEmpty ? totalRemStr : "\(totalRemStr) · ETA \(etaStr)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.82))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                    .padding(.trailing, 20)
                    .padding(.bottom, 10)
                }
            }
            .frame(width: 468, height: 210)
        }
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
    private var renderTimer: DispatchSourceTimer?
    private let videoQueue = DispatchQueue(label: "com.tripperdash.videoencoder", qos: .userInteractive)
    private var rtpSequenceNumber: UInt16 = UInt16.random(in: 1...60000)
    private var rtpTimestampBase: UInt32 = UInt32.random(in: 1000...UInt32.max / 2)
    private var streamStartTime: Date = Date()
    private let rtpSSRC: UInt32 = 0x52453435 // "RE45"
    private var targetIP: String = "192.168.1.1"
    private var targetPort: UInt16 = DashK1GProtocol.bikeVideoPort // 5000
    private var lastFrameCountReset: Date = Date()
    private var framesInWindow: Int = 0
    private var forceNextKeyFrame: Bool = true
    private var lastPixelBuffer: CVPixelBuffer?
    
    // Cached normalized SPS & PPS for Dash compound IDR bundling
    private var cachedSPS: Data?
    private var cachedPPS: Data?
    #if canImport(UIKit)
    public var cachedCustomWallpaperImage: UIImage?
    #endif
    
    private weak var trackerRef: LocationTracker?
    
    private init() {
        reloadCustomWallpaperCache()
    }
    
    public func reloadCustomWallpaperCache() {
        #if canImport(UIKit)
        let url = TripperDashClient.customWallpaperFileURL
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let img = UIImage(data: data) {
            self.cachedCustomWallpaperImage = img
        } else {
            self.cachedCustomWallpaperImage = nil
        }
        #endif
    }
    
    public func attachTracker(_ tracker: LocationTracker) {
        self.trackerRef = tracker
    }
    
    /// Called by BackgroundKeepAliveService when the app enters background (e.g. user opens Spotify, locks phone, or call rings)
    public func handleAppDidEnterBackground() {
        guard isStreaming else { return }
        videoQueue.async { [weak self] in
            guard let self = self, self.isStreaming else { return }
            self.setupH264Encoder()
            self.forceNextKeyFrame = true
            self.encodeNextFrameOnQueue(forceKeyframe: true)
        }
    }
    
    /// Called by BackgroundKeepAliveService when returning to foreground
    public func handleAppWillEnterForeground() {
        guard isStreaming else { return }
        videoQueue.async { [weak self] in
            guard let self = self, self.isStreaming else { return }
            self.setupH264Encoder()
            self.forceNextKeyFrame = true
            self.encodeNextFrameOnQueue(forceKeyframe: true)
        }
    }
    
    /// Triggers an immediate keyframe encode & RTP transmission whenever song, volume, weather, or call state changes!
    public func triggerImmediateFrame() {
        guard isStreaming else { return }
        forceNextKeyFrame = true
        videoQueue.async { [weak self] in
            self?.encodeNextFrameOnQueue(forceKeyframe: true)
        }
    }
    
    public func startStreaming(to ip: String, port: UInt16 = DashK1GProtocol.bikeVideoPort) {
        stopStreaming()
        
        self.targetIP = ip
        self.targetPort = port
        self.cachedSPS = nil
        self.cachedPPS = nil
        self.forceNextKeyFrame = true
        self.streamStartTime = Date()
        
        videoSocketFD = socket(AF_INET, SOCK_DGRAM, 0)
        guard videoSocketFD >= 0 else {
            TripperDashClient.shared.log("⚠️ Video projection socket failed to open.")
            return
        }
        
        var sndBuf: Int32 = 524_288
        setsockopt(videoSocketFD, SOL_SOCKET, SO_SNDBUF, &sndBuf, socklen_t(MemoryLayout<Int32>.size))
        
        DispatchQueue.main.async {
            self.isStreaming = true
            self.framesSent = 0
            self.framesInWindow = 0
            self.lastFrameCountReset = Date()
        }
        
        videoQueue.async { [weak self] in
            guard let self = self else { return }
            self.setupH264Encoder()
            self.encodeNextFrameOnQueue(forceKeyframe: true)
            
            // Background-safe GCD DispatchSourceTimer at 4 FPS (never pauses when app is backgrounded or phone is ringing!)
            let timer = DispatchSource.makeTimerSource(flags: .strict, queue: self.videoQueue)
            timer.schedule(deadline: .now() + 0.25, repeating: .milliseconds(250), leeway: .milliseconds(20))
            timer.setEventHandler { [weak self] in
                self?.encodeNextFrameOnQueue(forceKeyframe: false)
            }
            timer.resume()
            self.renderTimer = timer
        }
        
        TripperDashClient.shared.log("📺 TFT Digital Homescreen H.264 stream started → \(ip):\(port) (526×300 @ 4 fps, background-persistent)")
    }
    
    public func stopStreaming() {
        renderTimer?.cancel()
        renderTimer = nil
        
        DispatchQueue.main.async {
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
    
    // MARK: - VideoToolbox H.264 Baseline Profile Setup (1s GOP, Zero B-Frames, Low Latency)
    private func setupH264Encoder() {
        if let old = compressionSession {
            VTCompressionSessionInvalidate(old)
            compressionSession = nil
        }
        
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
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_4_1)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: 250_000 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 4 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 4 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 1.0 as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(session)
        
        self.compressionSession = session
    }
    
    // MARK: - Background-Safe Frame Snapshot & H.264 Encode
    private func encodeNextFrameOnQueue(forceKeyframe: Bool) {
        guard videoSocketFD >= 0 else { return }
        if compressionSession == nil {
            setupH264Encoder()
        }
        guard let session = compressionSession else { return }
        
        let client = TripperDashClient.shared
        let weather = WeatherService.shared
        let media = MediaPlaybackService.shared
        let call = CallHandlingService.shared
        let battery = BatteryOptimizationService.shared
        let heading = trackerRef?.currentHeading ?? 0
        
        // Build 526×300 pixel buffer using thread-safe CoreGraphics/UIKit renderer (works in foreground AND background!)
        let pixelBuffer = renderDomePixelBufferBackgroundSafe(
            heading: heading,
            weatherLoaded: weather.isLoaded,
            weatherTempC: weather.temperatureC,
            weatherCondition: weather.conditionText,
            weatherLocation: weather.locationName,
            windKmh: weather.windSpeedKmh,
            songTitle: media.currentTitle,
            songArtist: media.currentArtist,
            isMusicPlaying: media.isPlaying,
            volumePercent: media.volumePercent,
            batteryPercent: battery.batteryLevelPercent,
            isCharging: battery.isCharging,
            isCallRinging: call.isRinging,
            isCallOngoing: call.isOngoing,
            callerName: call.displayTitle,
            callDuration: call.formattedDuration,
            showWeather: client.showWeatherOnTFT,
            showMusic: client.showMusicOnTFT,
            activeNavInstruction: client.isNavigationActive ? client.activeNavStreet : nil,
            activeNavDistanceMeters: client.isNavigationActive ? client.activeNavDistanceMeters : nil
        ) ?? lastPixelBuffer
        
        guard let bufferToEncode = pixelBuffer else { return }
        self.lastPixelBuffer = bufferToEncode
        
        let elapsedMs = Int64(Date().timeIntervalSince(streamStartTime) * 1000.0)
        let pts = CMTime(value: max(Int64(framesSent + 1), elapsedMs), timescale: 1000)
        let duration = CMTime(value: 250, timescale: 1000)
        
        var frameProps: CFDictionary? = nil
        if forceKeyframe || forceNextKeyFrame || (framesSent % 4 == 0) {
            forceNextKeyFrame = false
            let dict: [CFString: Any] = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue as Any]
            frameProps = dict as CFDictionary
        }
        
        let encodeStatus = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: bufferToEncode,
            presentationTimeStamp: pts,
            duration: duration,
            frameProperties: frameProps,
            infoFlagsOut: nil
        ) { [weak self] status, _, sampleBuffer in
            guard let self = self else { return }
            if status != noErr {
                // Encoder was invalidated by iOS background transition — recreate on videoQueue immediately!
                self.videoQueue.async {
                    self.setupH264Encoder()
                    self.forceNextKeyFrame = true
                }
                return
            }
            guard let sampleBuffer = sampleBuffer else { return }
            self.packetizeAndSendRTP(sampleBuffer: sampleBuffer)
        }
        
        if encodeStatus != noErr {
            // Recreate encoder immediately and retry once
            setupH264Encoder()
            forceNextKeyFrame = true
        }
    }
    
    private static func maneuverGlyphText(for iconCode: UInt8) -> String {
        switch iconCode {
        case DashK1GProtocol.navManeuverTurnLeft:   return "↰"
        case DashK1GProtocol.navManeuverTurnRight:  return "↱"
        case DashK1GProtocol.navManeuverSharpLeft:  return "↙"
        case DashK1GProtocol.navManeuverSharpRight: return "↘"
        case DashK1GProtocol.navManeuverSlightLeft: return "↖"
        case DashK1GProtocol.navManeuverSlightRight:return "↗"
        case DashK1GProtocol.navManeuverUTurnLeft,
             DashK1GProtocol.navManeuverUTurnRight: return "⮌"
        case DashK1GProtocol.navManeuverRoundabout: return "⟳"
        case DashK1GProtocol.navManeuverArrive,
             DashK1GProtocol.navManeuverArrivalPin: return "⚑"
        default:                                    return "↑"
        }
    }
    
    /// Thread-safe 526×300 Dome Renderer using UIGraphicsImageRenderer / CoreGraphics.
    /// Runs reliably on `videoQueue` even when the app is in the background, when Spotify is open,
    /// when the phone screen is locked, or when the iOS Incoming Call screen covers the display!
    private func renderDomePixelBufferBackgroundSafe(
        heading: Double,
        weatherLoaded: Bool,
        weatherTempC: Int,
        weatherCondition: String,
        weatherLocation: String,
        windKmh: Int,
        songTitle: String,
        songArtist: String,
        isMusicPlaying: Bool,
        volumePercent: Int,
        batteryPercent: Int,
        isCharging: Bool,
        isCallRinging: Bool,
        isCallOngoing: Bool,
        callerName: String,
        callDuration: String,
        showWeather: Bool,
        showMusic: Bool,
        activeNavInstruction: String?,
        activeNavDistanceMeters: Int?
    ) -> CVPixelBuffer? {
        #if canImport(UIKit)
        let size = CGSize(width: Int(width), height: Int(height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size)
            
            // 1. Pure OLED black background
            UIColor.black.setFill()
            cg.fill(rect)
            
            // Clip to 526×300 DashGlass dome (circle centered at (263, 263), radius 263)
            let domePath = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 526, height: 526))
            domePath.addClip()
            
            let amber = UIColor(red: 1.0, green: 0.62, blue: 0.04, alpha: 1.0)
            let emerald = UIColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1.0)
            let coral = UIColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1.0)
            
            // 1b. Render Custom Photo or Theme Wallpaper inside the 526×300 dome
            let client = TripperDashClient.shared
            let style = client.wallpaperStyle
            let dim = CGFloat(min(0.88, max(0.10, client.wallpaperDimming)))
            
            switch style {
            case .pureBlack:
                break
            case .apexGold:
                let colors = [
                    UIColor(red: 0.28, green: 0.19, blue: 0.04, alpha: 1.0).cgColor,
                    UIColor(red: 0.07, green: 0.05, blue: 0.02, alpha: 1.0).cgColor,
                    UIColor.black.cgColor
                ] as CFArray
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.55, 1.0]) {
                    cg.drawLinearGradient(grad, start: CGPoint(x: 263, y: 0), end: CGPoint(x: 263, y: 300), options: [])
                }
                UIColor.black.withAlphaComponent(dim * 0.5).setFill()
                cg.fill(rect)
            case .sherpaDusk:
                let colors = [
                    UIColor(red: 0.34, green: 0.11, blue: 0.14, alpha: 1.0).cgColor,
                    UIColor(red: 0.14, green: 0.07, blue: 0.18, alpha: 1.0).cgColor,
                    UIColor.black.cgColor
                ] as CFArray
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.6, 1.0]) {
                    cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 526, y: 300), options: [])
                }
                UIColor.black.withAlphaComponent(dim * 0.5).setFill()
                cg.fill(rect)
            case .midnightMesh:
                let colors = [
                    UIColor(red: 0.05, green: 0.16, blue: 0.32, alpha: 1.0).cgColor,
                    UIColor(red: 0.02, green: 0.07, blue: 0.15, alpha: 1.0).cgColor,
                    UIColor.black.cgColor
                ] as CFArray
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 0.6, 1.0]) {
                    cg.drawLinearGradient(grad, start: CGPoint(x: 263, y: 0), end: CGPoint(x: 263, y: 300), options: [])
                }
                UIColor.black.withAlphaComponent(dim * 0.5).setFill()
                cg.fill(rect)
            case .customPhoto:
                if let wpImg = self.cachedCustomWallpaperImage {
                    let imgSize = wpImg.size
                    let scale = max(rect.width / max(1, imgSize.width), rect.height / max(1, imgSize.height))
                    let drawW = imgSize.width * scale
                    let drawH = imgSize.height * scale
                    let drawRect = CGRect(
                        x: (rect.width - drawW) / 2.0,
                        y: (rect.height - drawH) / 2.0,
                        width: drawW,
                        height: drawH
                    )
                    wpImg.draw(in: drawRect)
                    UIColor.black.withAlphaComponent(dim).setFill()
                    cg.fill(rect)
                }
            }
            
            // 2. Top Status Capsule (Clock · Compass · Battery) at y = 30..60
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            let timeStr = fmt.string(from: Date())
            let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
            let compassStr = dirs[Int((heading + 22.5) / 45.0) & 7]
            let topText = "\(timeStr)   ·   \(compassStr)   ·   \(isCharging ? "⚡" : "")\(batteryPercent)%"
            
            let pillRect = CGRect(x: 158, y: 28, width: 210, height: 28)
            UIColor(white: 1.0, alpha: 0.09).setFill()
            UIBezierPath(roundedRect: pillRect, cornerRadius: 14).fill()
            
            let topPara = NSMutableParagraphStyle()
            topPara.alignment = .center
            let topAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13.0, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: topPara
            ]
            (topText as NSString).draw(in: CGRect(x: pillRect.minX, y: pillRect.minY + 5, width: pillRect.width, height: 18), withAttributes: topAttrs)
            
            // 3. Priority 1: Incoming or Ongoing Phone Call Card (Borderless Minimal OLED Card!)
            if isCallRinging || isCallOngoing {
                let cardRect = CGRect(x: 43, y: 72, width: 440, height: 206)
                let accent = isCallRinging ? emerald : amber
                
                // Clean borderless surface (no green/amber outline border)
                UIColor(white: 1.0, alpha: 0.085).setFill()
                let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 24)
                cardPath.fill()
                
                // Status Badge
                let badgeText = isCallRinging ? "INCOMING CALL" : "ONGOING CALL  ·  \(callDuration)"
                let badgeAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13.5, weight: .heavy),
                    .foregroundColor: accent,
                    .paragraphStyle: topPara
                ]
                (badgeText as NSString).draw(in: CGRect(x: cardRect.minX + 16, y: cardRect.minY + 22, width: cardRect.width - 32, height: 22), withAttributes: badgeAttrs)
                
                // Caller Title (Never displays "Incoming Call" during an ongoing call!)
                let trimmedCaller = callerName.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayCaller: String
                if isCallOngoing {
                    if trimmedCaller.isEmpty || trimmedCaller == "Incoming Call" || trimmedCaller == "Outgoing Call" || trimmedCaller == "Active Call" {
                        displayCaller = "Ongoing Call"
                    } else {
                        displayCaller = trimmedCaller
                    }
                } else {
                    displayCaller = trimmedCaller.isEmpty ? "Incoming Call" : trimmedCaller
                }
                
                let callerAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 27, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: topPara
                ]
                (displayCaller as NSString).draw(in: CGRect(x: cardRect.minX + 18, y: cardRect.minY + 54, width: cardRect.width - 36, height: 36), withAttributes: callerAttrs)
                
                // Handlebar Action Pills (Left/Up/Center=Answer, Right/Down=Reject, Any direction=End Ongoing Call)
                if isCallRinging {
                    let ansRect = CGRect(x: cardRect.minX + 26, y: cardRect.minY + 122, width: 186, height: 48)
                    emerald.setFill()
                    UIBezierPath(roundedRect: ansRect, cornerRadius: 24).fill()
                    let btnAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 13.5, weight: .bold),
                        .foregroundColor: UIColor.black,
                        .paragraphStyle: topPara
                    ]
                    ("← / ↑ / ●  Answer" as NSString).draw(in: CGRect(x: ansRect.minX, y: ansRect.minY + 15, width: ansRect.width, height: 20), withAttributes: btnAttrs)
                    
                    let rejRect = CGRect(x: cardRect.maxX - 212, y: cardRect.minY + 122, width: 186, height: 48)
                    coral.setFill()
                    UIBezierPath(roundedRect: rejRect, cornerRadius: 24).fill()
                    let rejAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 13.5, weight: .bold),
                        .foregroundColor: UIColor.white,
                        .paragraphStyle: topPara
                    ]
                    ("→ / ↓  Decline" as NSString).draw(in: CGRect(x: rejRect.minX, y: rejRect.minY + 15, width: rejRect.width, height: 20), withAttributes: rejAttrs)
                } else {
                    let endRect = CGRect(x: cardRect.midX - 130, y: cardRect.minY + 122, width: 260, height: 48)
                    coral.setFill()
                    UIBezierPath(roundedRect: endRect, cornerRadius: 24).fill()
                    let endAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 14, weight: .bold),
                        .foregroundColor: UIColor.white,
                        .paragraphStyle: topPara
                    ]
                    ("● / ← / → / ↓  End Call" as NSString).draw(in: CGRect(x: endRect.minX, y: endRect.minY + 15, width: endRect.width, height: 20), withAttributes: endAttrs)
                }
                return
            }
            
            // 4. Priority 2: Live Moving Heading-Up Vector Navigation Map (Official-App Style!)
            if let navText = activeNavInstruction, !navText.isEmpty, let dist = activeNavDistanceMeters {
                let nav = NavigationEngine.shared
                let mapRect = CGRect(x: 24, y: 64, width: 478, height: 224)
                
                cg.saveGState()
                let mapClip = UIBezierPath(roundedRect: mapRect, cornerRadius: 22)
                mapClip.addClip()
                
                // Dark tactical navigation map background
                UIColor(red: 0.04, green: 0.07, blue: 0.12, alpha: 0.94).setFill()
                cg.fill(mapRect)
                
                let puckCenter = CGPoint(x: 263, y: 236)
                
                // Subtle radar range rings around the motorcycle puck
                UIColor(white: 1.0, alpha: 0.06).setStroke()
                for r: CGFloat in [55, 105, 155] {
                    let ring = UIBezierPath(ovalIn: CGRect(x: puckCenter.x - r, y: puckCenter.y - r, width: r * 2, height: r * 2))
                    ring.lineWidth = 1.0
                    ring.stroke()
                }
                
                // Project route polyline in Heading-Up coordinates around the rider
                let coords = nav.decodedCoordinates
                if coords.count >= 2 {
                    let splitIdx = min(max(0, nav.closestPolylineIndex), coords.count - 1)
                    let anchor = nav.riderCoordinate ?? coords[splitIdx]
                    let headingDeg = nav.riderHeadingDegrees > 0 ? nav.riderHeadingDegrees : heading
                    let headingRad = headingDeg * .pi / 180.0
                    let cosH = cos(headingRad)
                    let sinH = sin(headingRad)
                    let metersPerDegLat = 111_132.0
                    let metersPerDegLng = 111_320.0 * max(0.2, cos(anchor.latitude * .pi / 180.0))
                    let pxPerMeter = dist < 220 ? 0.50 : 0.25
                    
                    func project(_ c: CLLocationCoordinate2D) -> CGPoint {
                        let eastM = (c.longitude - anchor.longitude) * metersPerDegLng
                        let northM = (c.latitude - anchor.latitude) * metersPerDegLat
                        let rightM = eastM * cosH - northM * sinH
                        let fwdM = eastM * sinH + northM * cosH
                        return CGPoint(
                            x: puckCenter.x + CGFloat(rightM * pxPerMeter),
                            y: puckCenter.y - CGFloat(fwdM * pxPerMeter)
                        )
                    }
                    
                    // Traveled tail behind rider
                    if splitIdx > 0 {
                        let tailStart = max(0, splitIdx - 25)
                        let tailPath = UIBezierPath()
                        tailPath.move(to: project(coords[tailStart]))
                        for i in (tailStart + 1)...splitIdx {
                            tailPath.addLine(to: project(coords[i]))
                        }
                        tailPath.addLine(to: puckCenter)
                        tailPath.lineWidth = 6
                        tailPath.lineCapStyle = .round
                        tailPath.lineJoinStyle = .round
                        UIColor(white: 1.0, alpha: 0.22).setStroke()
                        tailPath.stroke()
                    }
                    
                    // Upcoming road path ahead of rider
                    let routePath = UIBezierPath()
                    routePath.move(to: puckCenter)
                    let endIdx = min(coords.count - 1, splitIdx + 95)
                    for i in splitIdx...endIdx {
                        routePath.addLine(to: project(coords[i]))
                    }
                    routePath.lineCapStyle = .round
                    routePath.lineJoinStyle = .round
                    
                    // Outer dark road casing
                    routePath.lineWidth = 14
                    UIColor(red: 0.01, green: 0.02, blue: 0.05, alpha: 0.95).setStroke()
                    routePath.stroke()
                    
                    // Inner glowing amber route line
                    routePath.lineWidth = 8.5
                    amber.setStroke()
                    routePath.stroke()
                    
                    // Highlight upcoming turn junction waypoint
                    if let step = nav.currentStep, let tLat = step.endLatitude, let tLng = step.endLongitude {
                        let turnPt = project(CLLocationCoordinate2D(latitude: tLat, longitude: tLng))
                        let outerDot = UIBezierPath(ovalIn: CGRect(x: turnPt.x - 10, y: turnPt.y - 10, width: 20, height: 20))
                        amber.withAlphaComponent(0.35).setFill()
                        outerDot.fill()
                        let innerDot = UIBezierPath(ovalIn: CGRect(x: turnPt.x - 5.5, y: turnPt.y - 5.5, width: 11, height: 11))
                        UIColor.white.setFill()
                        innerDot.fill()
                    }
                }
                
                // Draw Rider Directional Navigation Arrow Puck at puckCenter
                let halo = UIBezierPath(ovalIn: CGRect(x: puckCenter.x - 18, y: puckCenter.y - 18, width: 36, height: 36))
                emerald.withAlphaComponent(0.24).setFill()
                halo.fill()
                
                let arrow = UIBezierPath()
                arrow.move(to: CGPoint(x: puckCenter.x, y: puckCenter.y - 13))
                arrow.addLine(to: CGPoint(x: puckCenter.x + 10, y: puckCenter.y + 10))
                arrow.addLine(to: CGPoint(x: puckCenter.x, y: puckCenter.y + 5))
                arrow.addLine(to: CGPoint(x: puckCenter.x - 10, y: puckCenter.y + 10))
                arrow.close()
                emerald.setFill()
                arrow.fill()
                UIColor.white.setStroke()
                arrow.lineWidth = 2.0
                arrow.stroke()
                
                cg.restoreGState()
                
                // Top Turn Instruction Banner overlaid at top of map (y = 68..126)
                let bannerRect = CGRect(x: 42, y: 68, width: 442, height: 58)
                UIColor(white: 0.05, alpha: 0.90).setFill()
                let bannerPath = UIBezierPath(roundedRect: bannerRect, cornerRadius: 16)
                bannerPath.fill()
                amber.withAlphaComponent(0.55).setStroke()
                bannerPath.lineWidth = 1.2
                bannerPath.stroke()
                
                // Maneuver Icon Circle
                let iconCircleRect = CGRect(x: bannerRect.minX + 10, y: bannerRect.minY + 8, width: 42, height: 42)
                amber.setFill()
                UIBezierPath(ovalIn: iconCircleRect).fill()
                
                let glyphStr = Self.maneuverGlyphText(for: client.activeNavIconCode)
                let glyphAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 22, weight: .heavy),
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: topPara
                ]
                (glyphStr as NSString).draw(in: CGRect(x: iconCircleRect.minX, y: iconCircleRect.minY + 7, width: iconCircleRect.width, height: 28), withAttributes: glyphAttrs)
                
                // Distance to Next Turn + Street Name
                let leftNavPara = NSMutableParagraphStyle()
                leftNavPara.alignment = .left
                leftNavPara.lineBreakMode = .byTruncatingTail
                
                let distStr = dist >= 1000 ? String(format: "%.1f km", Double(dist) / 1000.0) : "\(dist) m"
                let distAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 21, weight: .heavy),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: leftNavPara
                ]
                (distStr as NSString).draw(in: CGRect(x: bannerRect.minX + 62, y: bannerRect.minY + 6, width: 130, height: 24), withAttributes: distAttrs)
                
                // 6-Bar Turn Proximity Meter
                let proxLevel = Int(DashK1GProtocol.proximityLevel(meters: dist))
                if proxLevel > 0 {
                    for b in 0..<6 {
                        let barRect = CGRect(x: bannerRect.minX + 185 + CGFloat(b * 9), y: bannerRect.minY + 14, width: 6, height: 10)
                        (b < proxLevel ? amber : UIColor(white: 1.0, alpha: 0.18)).setFill()
                        UIBezierPath(roundedRect: barRect, cornerRadius: 2).fill()
                    }
                }
                
                let streetAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13.5, weight: .semibold),
                    .foregroundColor: UIColor(white: 1.0, alpha: 0.88),
                    .paragraphStyle: leftNavPara
                ]
                (navText as NSString).draw(in: CGRect(x: bannerRect.minX + 62, y: bannerRect.minY + 32, width: bannerRect.width - 74, height: 18), withAttributes: streetAttrs)
                
                // Bottom-Right Remaining Distance & Arrival ETA Pill
                let totalRem = max(dist, client.activeNavTotalDistanceMeters)
                let totalRemStr = totalRem >= 1000 ? String(format: "%.1f km", Double(totalRem) / 1000.0) : "\(totalRem) m"
                let etaText = client.activeNavEtaText.isEmpty ? nav.etaFormatted : client.activeNavEtaText
                let summaryStr = etaText.isEmpty ? "🏁 \(totalRemStr)" : "🏁 \(totalRemStr) · \(etaText)"
                
                let etaRect = CGRect(x: 312, y: 248, width: 162, height: 30)
                UIColor(white: 0.05, alpha: 0.88).setFill()
                let etaPath = UIBezierPath(roundedRect: etaRect, cornerRadius: 15)
                etaPath.fill()
                UIColor(white: 1.0, alpha: 0.22).setStroke()
                etaPath.lineWidth = 1.0
                etaPath.stroke()
                
                let etaAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12.0, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: topPara
                ]
                (summaryStr as NSString).draw(in: CGRect(x: etaRect.minX + 6, y: etaRect.minY + 7, width: etaRect.width - 12, height: 16), withAttributes: etaAttrs)
                return
            }
            
            // 5. Priority 3: Clean Digital Homescreen (Weather Card + Now Playing Music & Volume Card)
            var currentY: CGFloat = 70
            let leftPara = NSMutableParagraphStyle()
            leftPara.alignment = .left
            leftPara.lineBreakMode = .byTruncatingTail
            
            if showWeather {
                let wRect = CGRect(x: 68, y: currentY, width: 390, height: 64)
                UIColor(white: 1.0, alpha: 0.07).setFill()
                UIBezierPath(roundedRect: wRect, cornerRadius: 16).fill()
                
                if weatherLoaded {
                    let tempStr = "\(weatherTempC)°C"
                    let tempAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 23, weight: .bold),
                        .foregroundColor: amber
                    ]
                    (tempStr as NSString).draw(in: CGRect(x: wRect.minX + 18, y: wRect.minY + 18, width: 78, height: 28), withAttributes: tempAttrs)
                    
                    let condAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                        .foregroundColor: UIColor.white,
                        .paragraphStyle: leftPara
                    ]
                    (weatherCondition as NSString).draw(in: CGRect(x: wRect.minX + 98, y: wRect.minY + 12, width: 274, height: 20), withAttributes: condAttrs)
                    
                    let locLine = weatherLocation.isEmpty ? "Wind \(windKmh) km/h" : "\(weatherLocation) · Wind \(windKmh) km/h"
                    let locAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 12.5, weight: .medium),
                        .foregroundColor: UIColor(white: 1.0, alpha: 0.62),
                        .paragraphStyle: leftPara
                    ]
                    (locLine as NSString).draw(in: CGRect(x: wRect.minX + 98, y: wRect.minY + 34, width: 274, height: 18), withAttributes: locAttrs)
                } else {
                    let waitAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                        .foregroundColor: UIColor(white: 1.0, alpha: 0.8),
                        .paragraphStyle: topPara
                    ]
                    ("Syncing Local GPS Weather..." as NSString).draw(in: CGRect(x: wRect.minX + 16, y: wRect.minY + 22, width: wRect.width - 32, height: 20), withAttributes: waitAttrs)
                }
                currentY += 74
            }
            
            if showMusic {
                let mRect = CGRect(x: 39, y: currentY, width: 448, height: 136)
                UIColor(white: 1.0, alpha: 0.085).setFill()
                UIBezierPath(roundedRect: mRect, cornerRadius: 20).fill()
                
                // Status Pill (PLAYING / PAUSED)
                let badgeW: CGFloat = 78
                let badgeRect = CGRect(x: mRect.maxX - badgeW - 18, y: mRect.minY + 18, width: badgeW, height: 24)
                (isMusicPlaying ? amber : UIColor(white: 1.0, alpha: 0.14)).setFill()
                UIBezierPath(roundedRect: badgeRect, cornerRadius: 12).fill()
                
                let bText = isMusicPlaying ? "PLAYING" : "PAUSED"
                let bAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10.5, weight: .bold),
                    .foregroundColor: isMusicPlaying ? UIColor.black : UIColor(white: 1.0, alpha: 0.75),
                    .paragraphStyle: topPara
                ]
                (bText as NSString).draw(in: CGRect(x: badgeRect.minX, y: badgeRect.minY + 5, width: badgeRect.width, height: 14), withAttributes: bAttrs)
                
                // Song Title & Artist
                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 19, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: leftPara
                ]
                (songTitle as NSString).draw(in: CGRect(x: mRect.minX + 20, y: mRect.minY + 16, width: mRect.width - badgeW - 48, height: 24), withAttributes: titleAttrs)
                
                let subText = songArtist.isEmpty ? (isMusicPlaying ? "Spotify / iPhone Audio" : "Paused · Use Handlebar Joystick") : songArtist
                let subAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14, weight: .medium),
                    .foregroundColor: UIColor(white: 1.0, alpha: 0.65),
                    .paragraphStyle: leftPara
                ]
                (subText as NSString).draw(in: CGRect(x: mRect.minX + 20, y: mRect.minY + 44, width: mRect.width - 40, height: 20), withAttributes: subAttrs)
                
                // Volume Bar Track
                let barTrackRect = CGRect(x: mRect.minX + 20, y: mRect.minY + 94, width: mRect.width - 88, height: 8)
                UIColor(white: 1.0, alpha: 0.15).setFill()
                UIBezierPath(roundedRect: barTrackRect, cornerRadius: 4).fill()
                
                let fillW = max(8, barTrackRect.width * CGFloat(min(100, max(0, volumePercent))) / 100.0)
                let barFillRect = CGRect(x: barTrackRect.minX, y: barTrackRect.minY, width: fillW, height: 8)
                amber.setFill()
                UIBezierPath(roundedRect: barFillRect, cornerRadius: 4).fill()
                
                let rightPara = NSMutableParagraphStyle()
                rightPara.alignment = .right
                let volAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: UIColor(white: 1.0, alpha: 0.85),
                    .paragraphStyle: rightPara
                ]
                ("\(volumePercent)%" as NSString).draw(in: CGRect(x: barTrackRect.maxX + 8, y: mRect.minY + 89, width: 52, height: 18), withAttributes: volAttrs)
            }
        }
        
        guard let cgImage = image.cgImage else { return nil }
        return makePixelBuffer(from: cgImage, width: Int(width), height: Int(height))
        #else
        return nil
        #endif
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
    
    /// Normalizes the H.264 Baseline SPS header to `67 42 00 29...` (constraint byte 0x00, level 4.1 = 0x29).
    /// Required by the Tripper Dash firmware whitelist before it will display the video surface.
    private static func normalizeSPSForDash(_ sps: Data) -> Data {
        var bytes = [UInt8](sps)
        if bytes.count >= 4 && (bytes[0] & 0x1F) == 7 && bytes[1] == 0x42 && bytes[3] <= 0x29 {
            bytes[2] = 0x00
            bytes[3] = 0x29
        }
        return Data(bytes)
    }
    
    // MARK: - Dash-Specific H.264 over RTP Packetizer (Compound SPS+PPS+IDR Bundle → UDP/5000)
    private func packetizeAndSendRTP(sampleBuffer: CMSampleBuffer) {
        guard videoSocketFD >= 0 else { return }
        
        // 1. Update cached SPS & PPS from sampleBuffer format description if keyframe
        if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            var spsPtr: UnsafePointer<UInt8>?
            var spsSize: Int = 0
            if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 0, parameterSetPointerOut: &spsPtr, parameterSetSizeOut: &spsSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
               let spsPtr = spsPtr, spsSize > 0 {
                let rawSPS = Data(bytes: spsPtr, count: spsSize)
                self.cachedSPS = Self.normalizeSPSForDash(rawSPS)
            }
            
            var ppsPtr: UnsafePointer<UInt8>?
            var ppsSize: Int = 0
            if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 1, parameterSetPointerOut: &ppsPtr, parameterSetSizeOut: &ppsSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
               let ppsPtr = ppsPtr, ppsSize > 0 {
                self.cachedPPS = Data(bytes: ppsPtr, count: ppsSize)
            }
        }
        
        // 2. Extract AVCC length-prefixed NALUs from CMBlockBuffer, filter out SEI/AUD, and bundle SPS+PPS+IDR
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
              let basePtr = dataPointer else { return }
        
        var accessUnitNALs: [Data] = []
        let startCode = Data([0x00, 0x00, 0x00, 0x01])
        
        var offset = 0
        while offset + 4 <= totalLength {
            var naluLen: UInt32 = 0
            memcpy(&naluLen, basePtr.advanced(by: offset), 4)
            naluLen = CFSwapInt32BigToHost(naluLen)
            offset += 4
            
            let len = Int(naluLen)
            guard len > 0, offset + len <= totalLength else { break }
            let nalu = Data(bytes: basePtr.advanced(by: offset), count: len)
            offset += len
            
            let nalType = nalu[0] & 0x1F
            switch nalType {
            case 7: // In-band SPS: normalize and cache, do NOT send standalone
                self.cachedSPS = Self.normalizeSPSForDash(nalu)
            case 8: // In-band PPS: cache, do NOT send standalone
                self.cachedPPS = nalu
            case 6, 9: // SEI & AUD: discard (dash decoder rejects them)
                continue
            case 5: // IDR Keyframe: MUST bundle [SPS + 00000001 + PPS + 00000001 + IDR] as ONE compound NAL!
                if let sps = self.cachedSPS, let pps = self.cachedPPS {
                    var bundled = Data(capacity: sps.count + pps.count + nalu.count + 8)
                    bundled.append(sps)
                    bundled.append(startCode)
                    bundled.append(pps)
                    bundled.append(startCode)
                    bundled.append(nalu)
                    accessUnitNALs.append(bundled)
                }
            case 1...4: // Non-IDR P-slice
                accessUnitNALs.append(nalu)
            default:
                break
            }
        }
        
        guard !accessUnitNALs.isEmpty else { return }
        
        // Wall-clock derived 90 kHz RTP timestamp
        let elapsedSec = Date().timeIntervalSince(streamStartTime)
        let currentTS = rtpTimestampBase &+ UInt32(Int64(elapsedSec * 90_000.0) & 0xFFFFFFFF)
        
        for (idx, nalu) in accessUnitNALs.enumerated() {
            let isLast = (idx == accessUnitNALs.count - 1)
            sendNALU(nalu, timestamp: currentTS, isLastOfFrame: isLast)
        }
        
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
    
    private func sendNALU(_ nalu: Data, timestamp: UInt32, isLastOfFrame: Bool) {
        let maxPayload = 1380 // Matches RtpPacketizer.MAX_PAYLOAD
        if nalu.count <= maxPayload {
            sendRTPPacket(payload: nalu, timestamp: timestamp, marker: isLastOfFrame)
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
                
                sendRTPPacket(payload: frag, timestamp: timestamp, marker: isEnd && isLastOfFrame)
                offset = end
            }
        }
    }
    
    private func sendRTPPacket(payload: Data, timestamp: UInt32, marker: Bool) {
        var packet = Data(capacity: 12 + payload.count)
        let seq = rtpSequenceNumber
        rtpSequenceNumber = rtpSequenceNumber &+ 1
        
        packet.append(0x80) // V=2, P=0, X=0, CC=0
        packet.append(marker ? (0x80 | 96) : 96) // M + Dynamic Payload Type 96 (H264)
        packet.append(UInt8(seq >> 8))
        packet.append(UInt8(seq & 0xFF))
        packet.append(UInt8((timestamp >> 24) & 0xFF))
        packet.append(UInt8((timestamp >> 16) & 0xFF))
        packet.append(UInt8((timestamp >> 8) & 0xFF))
        packet.append(UInt8(timestamp & 0xFF))
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
