import Foundation
import Darwin

public enum DashConnectionState: Equatable, Sendable {
    case disconnected
    case verifyingNetwork
    case requestingAuth
    case exchangingKeys
    case connected
    case failed(String)
    
    public var displayText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .verifyingNetwork: return "Checking Wi-Fi..."
        case .requestingAuth: return "Authenticating..."
        case .exchangingKeys: return "Exchanging Keys..."
        case .connected: return "Connected"
        case .failed(let err): return "Failed: \(err)"
        }
    }
}

public enum TFTWallpaperStyle: String, CaseIterable, Sendable {
    case pureBlack    = "OLED Black"
    case apexGold     = "Apex Gold"
    case sherpaDusk   = "Sherpa Dusk"
    case midnightMesh = "Midnight"
    case customPhoto  = "Custom Photo"
}

@Observable
public final class TripperDashClient: @unchecked Sendable {
    public static let shared = TripperDashClient()
    public static let defaultBikeSSID = "RE_RLK8_260813"
    public static let defaultBikeIP = "192.168.1.1"
    public static let defaultLocalMacIP = "192.168.0.9"
    
    public var connectionState: DashConnectionState = .disconnected
    public var lastJoystickEvent: DashJoystickEvent? = nil
    public var dashSSID: String = "RE_RLK8_260813"
    public var dashIP: String = "192.168.1.1"
    public var broadcastIP: String = "192.168.1.255"
    public var bikePort: UInt16 = DashK1GProtocol.bikeListenPort   // 2000
    public var listenPort: UInt16 = DashK1GProtocol.phoneListenPort // 2002
    public var isMockMode: Bool = false
    
    // TFT Digital Homescreen Preferences & Wallpaper
    public var showWeatherOnTFT: Bool = true {
        didSet {
            UserDefaults.standard.set(showWeatherOnTFT, forKey: "pref_tft_weather")
            TFTProjectionService.shared.triggerImmediateFrame()
        }
    }
    public var showMusicOnTFT: Bool = true {
        didSet {
            UserDefaults.standard.set(showMusicOnTFT, forKey: "pref_tft_music")
            TFTProjectionService.shared.triggerImmediateFrame()
        }
    }
    public var enableVideoProjection: Bool = true {
        didSet {
            UserDefaults.standard.set(enableVideoProjection, forKey: "pref_tft_video")
            if connectionState == .connected && !isMockMode {
                if enableVideoProjection {
                    TFTProjectionService.shared.startStreaming(to: dashIP)
                } else {
                    TFTProjectionService.shared.stopStreaming()
                }
            }
        }
    }
    public var wallpaperStyle: TFTWallpaperStyle = .pureBlack {
        didSet {
            UserDefaults.standard.set(wallpaperStyle.rawValue, forKey: "pref_tft_wallpaper_style")
            TFTProjectionService.shared.triggerImmediateFrame()
        }
    }
    public var wallpaperDimming: Double = 0.45 {
        didSet {
            UserDefaults.standard.set(wallpaperDimming, forKey: "pref_tft_wallpaper_dim")
            TFTProjectionService.shared.triggerImmediateFrame()
        }
    }
    public var hasCustomWallpaper: Bool = false
    
    // Active Navigation State (Turn-by-turn bubble is HIDDEN by default when isNavigationActive == false!)
    public var isNavigationActive: Bool = false
    public var activeNavStreet: String = ""
    public var activeNavDistanceMeters: Int = 0
    public var activeNavTotalDistanceMeters: Int = 0
    public var activeNavRemainingSeconds: Int = 0
    public var activeNavIconCode: UInt8 = DashK1GProtocol.navManeuverContinue
    public var activeNavNextIconCode: UInt8 = DashK1GProtocol.navManeuverHidden
    public var activeNavEtaText: String = ""
    
    // Live Diagnostic Logs for UI display
    public var diagnosticLogs: [String] = []
    
    private var socketFD: Int32 = -1
    private var rxThread: Thread?
    private var isRunning: Bool = false
    private var rollingSeq: UInt8 = 0
    private var heartbeatTickCount: Int = 0
    
    // Background Timers
    private var heartbeatTimer: DispatchSourceTimer?
    private var routeCardKeepaliveTimer: DispatchSourceTimer?
    private var projHeartbeatTimer: DispatchSourceTimer?
    private var authTimeoutTimer: DispatchSourceTimer?
    
    // RSA & AES Session Handshake State
    private var dashModulusHex: String? = nil
    private var dashExponentHex: String? = nil
    private var sessionAESKey: Data? = nil
    private var sessionKeySent: Bool = false
    private var authRetries: Int = 0
    private var callWasActiveLastTick: Bool = false
    
    private let queue = DispatchQueue(label: "com.tripperdash.client", qos: .userInteractive)
    private let heartbeatQueue = DispatchQueue(label: "com.tripperdash.heartbeat", qos: .userInteractive)
    
    private init() {
        if let savedSSID = UserDefaults.standard.string(forKey: "pref_dash_ssid"),
           !savedSSID.isEmpty,
           savedSSID != "RE_450_HIMALAYAN" {
            self.dashSSID = savedSSID
        } else {
            self.dashSSID = Self.defaultBikeSSID
            UserDefaults.standard.set(Self.defaultBikeSSID, forKey: "pref_dash_ssid")
        }
        if let savedIP = UserDefaults.standard.string(forKey: "pref_dash_ip"), !savedIP.isEmpty {
            self.dashIP = savedIP
        }
        if UserDefaults.standard.object(forKey: "pref_tft_weather") != nil {
            self.showWeatherOnTFT = UserDefaults.standard.bool(forKey: "pref_tft_weather")
        }
        if UserDefaults.standard.object(forKey: "pref_tft_music") != nil {
            self.showMusicOnTFT = UserDefaults.standard.bool(forKey: "pref_tft_music")
        }
        if UserDefaults.standard.object(forKey: "pref_tft_video") != nil {
            self.enableVideoProjection = UserDefaults.standard.bool(forKey: "pref_tft_video")
        }
        if let savedStyle = UserDefaults.standard.string(forKey: "pref_tft_wallpaper_style"),
           let style = TFTWallpaperStyle(rawValue: savedStyle) {
            self.wallpaperStyle = style
        }
        if UserDefaults.standard.object(forKey: "pref_tft_wallpaper_dim") != nil {
            self.wallpaperDimming = UserDefaults.standard.double(forKey: "pref_tft_wallpaper_dim")
        }
        self.hasCustomWallpaper = FileManager.default.fileExists(atPath: Self.customWallpaperFileURL.path)
    }
    
    public static var customWallpaperFileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("tft_custom_wallpaper.jpg")
    }
    
    public func saveCustomWallpaperData(_ data: Data) {
        do {
            try data.write(to: Self.customWallpaperFileURL, options: .atomic)
            DispatchQueue.main.async {
                self.hasCustomWallpaper = true
                self.wallpaperStyle = .customPhoto
                TFTProjectionService.shared.reloadCustomWallpaperCache()
                TFTProjectionService.shared.triggerImmediateFrame()
                self.log("🖼️ Saved custom TFT Homescreen wallpaper.")
            }
        } catch {
            log("⚠️ Failed to save wallpaper: \(error.localizedDescription)")
        }
    }
    
    public func clearCustomWallpaper() {
        try? FileManager.default.removeItem(at: Self.customWallpaperFileURL)
        DispatchQueue.main.async {
            self.hasCustomWallpaper = false
            if self.wallpaperStyle == .customPhoto {
                self.wallpaperStyle = .pureBlack
            }
            TFTProjectionService.shared.reloadCustomWallpaperCache()
            TFTProjectionService.shared.triggerImmediateFrame()
        }
    }
    
    /// Updates broadcast IP automatically whenever dashIP is changed (e.g., 192.168.1.1 -> 192.168.1.255, 192.168.0.9 -> 192.168.0.255)
    private func updateBroadcastForIP(_ ip: String) {
        let parts = ip.split(separator: ".")
        if parts.count == 4 && ip != "127.0.0.1" {
            self.broadcastIP = "\(parts[0]).\(parts[1]).\(parts[2]).255"
        } else {
            self.broadcastIP = "192.168.1.255"
        }
    }
    
    /// Returns the detected local Wi-Fi subnet host IP or fallback for local testing
    public func detectedLocalSubnetPrefix() -> String {
        if let local = getLocalWiFiIP() {
            let parts = local.split(separator: ".")
            if parts.count == 4 {
                return "\(parts[0]).\(parts[1]).\(parts[2])"
            }
        }
        return "192.168.0"
    }
    
    public func setDashSSID(_ newSSID: String) {
        let trimmed = newSSID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.dashSSID = trimmed
        UserDefaults.standard.set(trimmed, forKey: "pref_dash_ssid")
        log("Updated Dash SSID to: '\(trimmed)'")
    }
    
    public func setDashIP(_ newIP: String) {
        let trimmed = newIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.dashIP = trimmed
        self.updateBroadcastForIP(trimmed)
        UserDefaults.standard.set(trimmed, forKey: "pref_dash_ip")
        log("Updated Dash IP to: '\(trimmed)' (Broadcast: \(self.broadcastIP))")
    }
    
    public func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        print(entry)
        DispatchQueue.main.async {
            self.diagnosticLogs.append(entry)
            if self.diagnosticLogs.count > 120 {
                self.diagnosticLogs.removeFirst()
            }
        }
    }
    
    public func clearLogs() {
        DispatchQueue.main.async {
            self.diagnosticLogs.removeAll()
        }
    }
    
    // MARK: - Connection Control
    public func connect(to ip: String? = nil, port: UInt16 = DashK1GProtocol.bikeListenPort) {
        disconnect()
        
        let targetIP = ip ?? self.dashIP
        self.dashIP = targetIP
        self.bikePort = port
        self.connectionState = .verifyingNetwork
        self.dashModulusHex = nil
        self.dashExponentHex = nil
        self.sessionAESKey = nil
        self.sessionKeySent = false
        self.authRetries = 0
        self.isMockMode = false
        
        log("Initiating connection to Dash at \(targetIP):\(port) (RX listening on port \(listenPort))...")
        
        if let localIP = getLocalWiFiIP() {
            log("Local iPhone Wi-Fi IP: \(localIP)")
            if !localIP.hasPrefix("192.168.1.") && !localIP.hasPrefix("192.168.") {
                log("⚠️ Warning: iPhone IP is not on 192.168.1.x subnet!")
                log("👉 Ensure phone is connected to bike Wi-Fi ('\(dashSSID)') or Mac Mock Dash.")
            } else {
                log("✅ Local Wi-Fi verified (\(localIP)).")
            }
        } else {
            log("⚠️ Could not detect Wi-Fi IP. Please check iOS Settings > Wi-Fi.")
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            self.setupSocketAndStart()
        }
    }
    
    // MARK: - Local In-App Mock Simulation
    public func startMockConnection() {
        disconnect()
        isMockMode = true
        connectionState = .requestingAuth
        log("🧪 [MOCK DASH] Simulating Royal Enfield Himalayan 450 TFT...")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, self.isMockMode else { return }
            self.connectionState = .exchangingKeys
            self.log("🧪 [MOCK DASH] Dash exchanged RSA-1024 public key.")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self, self.isMockMode else { return }
                self.connectionState = .connected
                self.log("🎉 *** [MOCK DASH] AUTHENTICATION OK (07 01 01) ***")
                self.log("✅ Simulation Active: Digital Homescreen & Controls ready.")
                BackgroundKeepAliveService.shared.startKeepAlive()
                self.enterNavigationMode()
            }
        }
    }
    
    public func simulateJoystickPress(_ event: DashJoystickEvent) {
        log("🎮 [MOCK] Handlebar Joystick Event Triggered: \(event)")
        dispatchJoystick(event)
    }
    
    public func disconnect() {
        stopAllTimers()
        TFTProjectionService.shared.stopStreaming()
        isMockMode = false
        
        // Clean teardown TLVs so the dash returns cleanly to its menu
        if isRunning {
            if let stopPkt = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_h_proj_stop) {
                sendRawPacket(DashK1GProtocol.patchSequence(data: stopPkt, seq: nextSeq()))
            }
            if let offPkt = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_x_proj_off) {
                sendRawPacket(DashK1GProtocol.patchSequence(data: offPkt, seq: nextSeq()))
            }
            // Send BACK (06 80 0001 12) + 05 17 AA session boundary
            sendRawPacket(DashK1GProtocol.buildButtonAck(buttonByte: 0x12, seq: nextSeq()))
            sendRawPacket(DashK1GProtocol.buildSingleTLVPacket(type: 0x05, sub: 0x17, payload: [0xAA], seq: nextSeq()))
        }
        
        isRunning = false
        
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        rxThread?.cancel()
        rxThread = nil
        
        DispatchQueue.main.async {
            self.connectionState = .disconnected
            BackgroundKeepAliveService.shared.stopKeepAlive()
        }
        log("Dash connection closed.")
    }
    
    // MARK: - BSD UDP Socket Setup
    private func setupSocketAndStart() {
        socketFD = socket(AF_INET, SOCK_DGRAM, 0)
        guard socketFD >= 0 else {
            let err = String(cString: strerror(errno))
            log("❌ Socket creation failed: \(err)")
            DispatchQueue.main.async { self.connectionState = .failed("Socket creation failed") }
            return
        }
        
        var optVal: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &optVal, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEPORT, &optVal, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socketFD, SOL_SOCKET, SO_BROADCAST, &optVal, socklen_t(MemoryLayout<Int32>.size))
        
        var bindAddr = sockaddr_in()
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = listenPort.bigEndian
        bindAddr.sin_addr.s_addr = INADDR_ANY.bigEndian
        
        let bindResult = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if bindResult < 0 {
            let err = String(cString: strerror(errno))
            log("⚠️ Warning: bind to port \(listenPort) returned: \(err)")
        } else {
            log("✅ Bound UDP listening socket to port \(listenPort). Ready to receive Dash segments.")
        }
        
        isRunning = true
        
        startRXThread()
        
        DispatchQueue.main.async { self.connectionState = .requestingAuth }
        sendInitialK1GBurst()
        
        startAuthTimeout()
    }
    
    private func sendInitialK1GBurst() {
        log("Sending K1G Announcement Burst + Real Clock Sync + Auth Request (q3c.e) to \(dashIP):\(bikePort)...")
        
        let battery = BatteryOptimizationService.shared
        let weather = WeatherService.shared
        let media = MediaPlaybackService.shared
        
        let packets = DashK1GProtocol.buildInitialBurstPackets(
            hostname: "iPhone",
            batteryPct: battery.batteryLevelPercent,
            charging: battery.isCharging,
            weatherIcon: weather.isLoaded ? weather.dashWeatherIcon : 0xFF,
            tempC: weather.isLoaded ? weather.temperatureC : nil,
            volumePercent: media.volumePercent,
            nextSeq: { self.nextSeq() }
        )
        
        for pkt in packets {
            sendRawPacket(pkt)
            Thread.sleep(forTimeInterval: 0.02)
        }
    }
    
    private func startAuthTimeout() {
        stopAuthTimer()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 8.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.connectionState != .connected else { return }
            self.log("⚠️ No response received from Dash at \(self.dashIP)!")
            self.log("👉 Checklist:")
            self.log("   1) Bike ignition ON & Dash in Digital Mode (Appearance > Screen Type > Digital)")
            self.log("   2) iPhone Wi-Fi connected to '\(self.dashSSID)' (Password: 12345678)")
            self.log("   3) Stored SSID '\(self.dashSSID)' matches what the bike displays on screen")
            DispatchQueue.main.async {
                self.connectionState = .failed("Dash timeout (no 07 xx packet received)")
            }
        }
        timer.resume()
        self.authTimeoutTimer = timer
    }
    
    private func stopAuthTimer() {
        authTimeoutTimer?.cancel()
        authTimeoutTimer = nil
    }
    
    // MARK: - Inbound Receiver Loop on Port 2002
    private func startRXThread() {
        let thread = Thread { [weak self] in
            guard let self = self else { return }
            var buffer = [UInt8](repeating: 0, count: 65535)
            
            while self.isRunning && self.socketFD >= 0 {
                var srcAddr = sockaddr_in()
                var srcLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                
                let bytesRead = withUnsafeMutablePointer(to: &srcAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(self.socketFD, &buffer, buffer.count, 0, $0, &srcLen)
                    }
                }
                
                if bytesRead > 0 {
                    let data = Data(buffer[0..<bytesRead])
                    self.handleIncomingPacket(data)
                }
            }
        }
        thread.name = "TripperDashRX"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.rxThread = thread
    }
    
    private func handleIncomingPacket(_ data: Data) {
        let segments = DashK1GProtocol.decodeSegments(data: data)
        for s in segments {
            switch s.type {
            case 0x07:
                handleAuthSegment(s)
            case 0x09:
                handleDashCommandOrButton(s)
            case 0x03:
                // 0x03: Cluster Settings Sync Request (Clock format / Temp units) -> Reply with live Clock & Weather
                sendRawPacket(DashK1GProtocol.buildTimeSyncPacket(seq: nextSeq()))
                sendWeatherUpdate()
            case 0x0F, 0x0A:
                // 0x0F (0F01..0F0A) & 0x0A: Cluster Device Info, Firmware & Odometer Telemetry frames
                handleClusterTelemetrySegment(s)
            default:
                break
            }
        }
    }
    
    private func handleClusterTelemetrySegment(_ seg: DashK1GProtocol.K1GSegment) {
        DispatchQueue.main.async {
            VehicleStore.shared.lastDashSyncDate = Date()
        }
        if seg.type == 0x0F {
            let text = String(data: seg.payload, encoding: .ascii)?
                .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines)) ?? ""
            if !text.isEmpty {
                log("🏍️ Cluster Info (0F \(String(format: "%02X", seg.sub))): \(text)")
                DispatchQueue.main.async {
                    VehicleStore.shared.dashFirmwareVersion = text
                }
            }
        } else if seg.type == 0x0A && seg.payload.count >= 4 {
            // Check if 4-byte unsigned integer odometer reading (in km or 0.1 km) is reported by cluster
            let rawVal = (UInt32(seg.payload[0]) << 24) | (UInt32(seg.payload[1]) << 16) | (UInt32(seg.payload[2]) << 8) | UInt32(seg.payload[3])
            if rawVal > 10 && rawVal < 500_000 {
                let km = Double(rawVal)
                if km >= VehicleStore.shared.activeVehicle.currentOdometer {
                    VehicleStore.shared.updateOdometer(km: km)
                    log("🏍️ Cluster Odometer Synced: \(String(format: "%.0f", km)) km")
                }
            }
        }
    }
    
    private func handleAuthSegment(_ seg: DashK1GProtocol.K1GSegment) {
        if seg.sub == 0x00 {
            let modHex = seg.payload.map { String(format: "%02X", $0) }.joined()
            self.dashModulusHex = modHex
            log("Dash → Sent RSA Public Key Modulus (\(seg.payload.count) B)")
            checkAndSendSessionKey()
        } else if seg.sub == 0x03 {
            let expHex = seg.payload.map { String(format: "%02X", $0) }.joined()
            self.dashExponentHex = expHex
            log("Dash → Sent RSA Public Key Exponent: 0x\(expHex)")
            checkAndSendSessionKey()
        } else if seg.sub == 0x01 {
            let status = seg.payload.first ?? 0x00
            if status == 0x01 {
                log("🎉 *** DASH AUTHENTICATION OK (07 01 01) ***")
                stopAuthTimer()
                
                DispatchQueue.main.async {
                    self.connectionState = .connected
                    BackgroundKeepAliveService.shared.startKeepAlive()
                }
                
                enterNavigationMode()
            } else {
                authRetries += 1
                log("❌ Dash returned auth failure (0x\(String(format: "%02X", status))), retry #\(authRetries)")
                if authRetries <= 5 {
                    self.dashModulusHex = nil
                    self.dashExponentHex = nil
                    self.sessionKeySent = false
                    if let reqData = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_e_request_auth) {
                        sendRawPacket(DashK1GProtocol.patchSequence(data: reqData, seq: nextSeq()))
                    }
                }
            }
        }
    }
    
    private func checkAndSendSessionKey() {
        guard !sessionKeySent,
              let mod = dashModulusHex,
              let exp = dashExponentHex else { return }
        
        sessionKeySent = true
        DispatchQueue.main.async { self.connectionState = .exchangingKeys }
        log("Encrypting session key with Dash RSA-1024 pubkey (SSID: '\(dashSSID)')...")
        
        do {
            var aesKey = Data(count: 32)
            _ = aesKey.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
            self.sessionAESKey = aesKey
            
            let ciphertext = try DashAuthCrypto.encryptSessionKey(
                ssid: dashSSID,
                modulusHex: mod,
                exponentHex: exp,
                aesKey: aesKey
            )
            
            log("Sending encrypted session key packet (q3c.d, 128-byte ciphertext)...")
            let pkt = DashK1GProtocol.buildQ3CDPacket(ciphertext: ciphertext, seq: nextSeq())
            sendRawPacket(pkt)
        } catch {
            log("❌ RSA Encryption failed: \(error.localizedDescription)")
            DispatchQueue.main.async { self.connectionState = .failed("RSA encryption error") }
        }
    }
    
    // MARK: - Bike Commands, Frame ACKs & Handlebar Buttons (09 xx)
    private func handleDashCommandOrButton(_ seg: DashK1GProtocol.K1GSegment) {
        let segHex = seg.hexString.uppercased()
        
        // 1. Mandatory IDR Frame Decoded ACK (09 06 0001 55 -> reply with q3c.L2 = 06 11 0001 55)
        if segHex.hasPrefix("09060001") && segHex.hasSuffix("55") {
            if let l2Data = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_l2) {
                sendRawPacket(DashK1GProtocol.patchSequence(data: l2Data, seq: nextSeq()))
            }
            return
        }
        
        // 2. P-Frame Decoded ACK (09 04 0001 55 -> reply with q3c.K2 = 06 12 0001 55)
        if segHex.hasPrefix("09040001") && segHex.hasSuffix("55") {
            if let k2Data = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_k2) {
                sendRawPacket(DashK1GProtocol.patchSequence(data: k2Data, seq: nextSeq()))
            }
            return
        }
        
        // 3. Handlebar Joystick Button Events (09 00 XXXX XX)
        // Supports Dash Map Mode (0x12..0x15, 0x18), Media Mode (0x05..0x07, 0x09, 0x0A), and Call Screen (0x01..0x04, 0x16)!
        if seg.sub == 0x00, let buttonByte = seg.payload.last {
            // Immediate Echo ACK (06 80 0001 XX) + Zoom Icons to keep all directions active
            let ackPkt = DashK1GProtocol.buildButtonAck(buttonByte: buttonByte, seq: nextSeq())
            sendRawPacket(ackPkt)
            if let zoomData = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_zoom_icons) {
                sendRawPacket(DashK1GProtocol.patchSequence(data: zoomData, seq: nextSeq()))
            }
            
            switch buttonByte {
            case 0x01:
                // 0x01 = Call Screen Right (Reject / End Call)
                log("📞 Handlebar Joystick: CALL RIGHT → Reject / End Call (0x01)")
                dispatchJoystick(.callRejectRight)
            case 0x02:
                // 0x02 = Call Screen Left (Answer Incoming Call)
                log("📞 Handlebar Joystick: CALL LEFT → Answer Call (0x02)")
                dispatchJoystick(.callAnswerLeft)
            case 0x03:
                // 0x03 = Call Screen Volume Up
                log("🔊 Handlebar Joystick: CALL UP → Volume Up (0x03)")
                dispatchJoystick(.callVolumeUp)
            case 0x04:
                // 0x04 = Call Screen Volume Down
                log("🔉 Handlebar Joystick: CALL DOWN → Volume Down (0x04)")
                dispatchJoystick(.callVolumeDown)
            case 0x16:
                // 0x16 = Call Screen Middle (End Active Call)
                log("📞 Handlebar Joystick: CALL CENTER → End Call (0x16)")
                dispatchJoystick(.callEndMiddle)
            case 0x09, 0x13:
                // 0x09 = Media Mode Next Track, 0x13 = Map Mode Right
                log("🎮 Handlebar Joystick: RIGHT → Next Track (0x\(String(format: "%02X", buttonByte)))")
                dispatchJoystick(.right)
            case 0x0A, 0x14:
                // 0x0A = Media Mode Previous Track, 0x14 = Map Mode Left
                log("🎮 Handlebar Joystick: LEFT → Previous Track (0x\(String(format: "%02X", buttonByte)))")
                dispatchJoystick(.left)
            case 0x06:
                // 0x06 = Media Mode Volume Up
                log("🔊 Handlebar Joystick: UP → Volume Up (0x06)")
                dispatchJoystick(.up)
            case 0x07, 0x15:
                // 0x07 = Media Mode Volume Down, 0x15 = Map Mode Down
                log("🔉 Handlebar Joystick: DOWN → Volume Down (0x\(String(format: "%02X", buttonByte)))")
                dispatchJoystick(.down)
            case 0x05:
                // 0x05 = Media Mode Center Click (Play / Pause)
                log("🎮 Handlebar Joystick: CENTER → Play / Pause (0x05)")
                dispatchJoystick(.centerClick)
            case 0x18:
                // 0x18 = Map Mode Center Click (Enters Dash Media Mode)
                log("🎛️ Handlebar Joystick: CENTER → Media Control Mode Active (0x18)")
                dispatchJoystick(.mediaModeEnter)
            case 0x12:
                // 0x12 = Joystick Up / Back (Volume Up in Map Mode / Exits Media Mode)
                log("🔊 Handlebar Joystick: UP / BACK → Volume Up (0x12)")
                dispatchJoystick(.mediaModeBack)
            case 0xFE:
                log("📞 Remote Command: Simulate Incoming Call")
                CallHandlingService.shared.simulateIncomingCall(caller: "Royal Enfield Rider")
            default:
                log("🎮 Handlebar Event: 0x\(String(format: "%02X", buttonByte))")
            }
            return
        }
        
        // 4. Other firmware command ACKs
        if segHex.hasPrefix("090A0001") && segHex.hasSuffix("55") {
            if let t2 = DashAuthCrypto.hexToData("0016000200000000020100054B31472000068000010A") {
                sendRawPacket(DashK1GProtocol.patchSequence(data: t2, seq: nextSeq()))
            }
        }
    }
    
    // MARK: - Post-Auth Digital Homescreen & Projection Sequence
    private func enterNavigationMode() {
        log("Activating Clean TFT Digital Homescreen (Turn-by-Turn Hidden, Real Clock & Music Active)...")
        
        // 1. Navigation Context + Empty Lists
        for hex in [DashK1GProtocol.q3c_q_nav_ctx, DashK1GProtocol.q3c_r_empty_lists] {
            if let data = DashAuthCrypto.hexToData(hex) {
                sendRawPacket(DashK1GProtocol.patchSequence(data: data, seq: nextSeq()))
                Thread.sleep(forTimeInterval: 0.04)
            }
        }
        
        // 2. Pre-z2 Homescreen Surface Burst (with turn-by-turn bubble HIDDEN: maneuver = 0xFF)
        let bannerTitle = buildHomescreenBannerTitle()
        for i in 0..<4 {
            let routePkt = DashK1GProtocol.buildRouteCardPacket(
                title: bannerTitle,
                seq: nextSeq(),
                projectionOn: false,
                isNavigating: isNavigationActive,
                isCallActive: false,
                maneuver: activeNavIconCode,
                totalDistanceMeters: max(activeNavTotalDistanceMeters, activeNavDistanceMeters),
                remainingTimeSeconds: activeNavRemainingSeconds,
                arrivalDate: Date().addingTimeInterval(TimeInterval(activeNavRemainingSeconds))
            )
            sendRawPacket(routePkt)
            Thread.sleep(forTimeInterval: i == 0 ? 0.10 : 0.25)
        }
        
        // 3. Projection Frame Heartbeat (q3c.g) + Nav Placeholder (06 0A 0002 0000) + Zoom Icons (06 0C 0001 30)
        if let gPkt = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_g_proj_frame) {
            sendRawPacket(DashK1GProtocol.patchSequence(data: gPkt, seq: nextSeq()))
            Thread.sleep(forTimeInterval: 0.05)
        }
        if let phPkt = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_nav_placeholder) {
            sendRawPacket(DashK1GProtocol.patchSequence(data: phPkt, seq: nextSeq()))
            Thread.sleep(forTimeInterval: 0.02)
        }
        if let zoomData = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_zoom_icons) {
            sendRawPacket(DashK1GProtocol.patchSequence(data: zoomData, seq: nextSeq()))
            Thread.sleep(forTimeInterval: 0.02)
        }
        
        // 4. Start Digital Surface Projection Command (q3c.z2)
        if let z2Pkt = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_z2_start_nav) {
            sendRawPacket(DashK1GProtocol.patchSequence(data: z2Pkt, seq: nextSeq()))
            Thread.sleep(forTimeInterval: 0.04)
        }
        
        // 5. Post-z2 confirmation card with projection ON & turn-by-turn bubble HIDDEN
        let routePktOn = DashK1GProtocol.buildRouteCardPacket(
            title: bannerTitle,
            seq: nextSeq(),
            projectionOn: true,
            isNavigating: isNavigationActive,
            isCallActive: false,
            maneuver: activeNavIconCode,
            totalDistanceMeters: max(activeNavTotalDistanceMeters, activeNavDistanceMeters),
            remainingTimeSeconds: activeNavRemainingSeconds,
            arrivalDate: Date().addingTimeInterval(TimeInterval(activeNavRemainingSeconds))
        )
        sendRawPacket(routePktOn)
        
        // 6. Push initial Real Time Sync + Clear Any Stock Call Banner + Music Now-Playing Cards immediately
        sendRawPacket(DashK1GProtocol.buildTimeSyncPacket(seq: nextSeq()))
        sendRawPacket(DashK1GProtocol.buildSingleTLVPacket(type: 0x05, sub: 0x21, payload: [0x32], seq: nextSeq()))
        sendRawPacket(DashK1GProtocol.buildSingleTLVPacket(type: 0x05, sub: 0x4D, payload: [0x32], seq: nextSeq()))
        let media = MediaPlaybackService.shared
        sendMusicUpdate(title: media.currentTitle, album: media.currentAlbum, artist: media.currentArtist, isPlaying: media.isPlaying)
        
        // 7. Start H.264 Digital Homescreen Video Stream (UDP 5000) if enabled & real socket connected
        if enableVideoProjection && !isMockMode {
            TFTProjectionService.shared.startStreaming(to: dashIP)
        }
        
        // 8. Start Keepalive Loops (Live 0049 Heartbeat + Clean Route Card + Music Cards + 4Hz Projection Frame)
        startAllKeepalives()
        log("✅ TFT Digital Homescreen active & synced in real time.")
    }
    
    /// Builds the clean Latin-1 TFT banner string (Weather + Now Playing when idle, Street when navigating)
    private func buildHomescreenBannerTitle() -> String {
        if isNavigationActive && !activeNavStreet.isEmpty {
            return activeNavStreet
        }
        
        let weather = WeatherService.shared
        let media = MediaPlaybackService.shared
        
        var parts: [String] = []
        if showWeatherOnTFT && weather.isLoaded {
            parts.append(weather.compactTFTString)
        }
        if showMusicOnTFT && media.currentTitle != "Not Playing" && !media.currentTitle.isEmpty {
            parts.append(media.currentTitle)
        }
        
        if parts.isEmpty {
            return "TripperDash"
        }
        return parts.joined(separator: " - ")
    }
    
    // MARK: - Timers & Keepalives
    private func startAllKeepalives() {
        stopAllTimers()
        heartbeatTickCount = 0
        
        // Timer 1: 1 Hz Authentic 0049 Status Heartbeat (Real Battery, Real Weather Icon & Temp, Real Volume, Real Clock Sync)
        let hbTimer = DispatchSource.makeTimerSource(flags: .strict, queue: heartbeatQueue)
        hbTimer.schedule(deadline: .now(), repeating: .milliseconds(1000), leeway: .milliseconds(50))
        hbTimer.setEventHandler { [weak self] in
            guard let self = self, self.connectionState == .connected else { return }
            
            let battery = BatteryOptimizationService.shared
            let weather = WeatherService.shared
            let media = MediaPlaybackService.shared
            
            // Always send callStatusCode = 0x32 (None) so the bike's stock firmware incoming call banner
            // never pops up on top of our custom H.264 TFT call UI!
            let hb0049 = K1GPacket.makeHeartbeatPacket(
                batteryPct: battery.batteryLevelPercent,
                charging: battery.isCharging,
                gpsOn: true,
                weatherIcon: (self.showWeatherOnTFT && weather.isLoaded) ? weather.dashWeatherIcon : 0xFF,
                tempC: (self.showWeatherOnTFT && weather.isLoaded) ? weather.temperatureC : nil,
                volumePercent: media.volumePercent,
                callStatusCode: 0x32
            )
            self.sendRawPacket(DashK1GProtocol.patchSequence(data: hb0049, seq: self.nextSeq()))
            
            // Keep Dash Clock 100% real-time (resync every 15 seconds)
            self.heartbeatTickCount += 1
            if self.heartbeatTickCount % 15 == 0 {
                self.sendRawPacket(DashK1GProtocol.buildTimeSyncPacket(seq: self.nextSeq()))
            }
        }
        hbTimer.resume()
        self.heartbeatTimer = hbTimer
        
        // Timer 2: 1 Hz TFT Homescreen Route Card (Turn-by-Turn Hidden when idle) + Music Cards (keeps joystick active)
        let rcTimer = DispatchSource.makeTimerSource(flags: .strict, queue: heartbeatQueue)
        rcTimer.schedule(deadline: .now() + 0.5, repeating: .milliseconds(1000), leeway: .milliseconds(50))
        rcTimer.setEventHandler { [weak self] in
            guard let self = self, self.connectionState == .connected else { return }
            
            let call = CallHandlingService.shared
            let callActive = call.isRinging || call.isOngoing
            let banner = self.buildHomescreenBannerTitle()
            let totalDist = max(self.activeNavTotalDistanceMeters, self.activeNavDistanceMeters)
            
            let rcPkt = DashK1GProtocol.buildRouteCardPacket(
                title: banner,
                seq: self.nextSeq(),
                projectionOn: true,
                isNavigating: self.isNavigationActive,
                isCallActive: false,
                maneuver: self.activeNavIconCode,
                totalDistanceMeters: totalDist,
                remainingTimeSeconds: self.activeNavRemainingSeconds,
                arrivalDate: Date().addingTimeInterval(TimeInterval(self.activeNavRemainingSeconds))
            )
            self.sendRawPacket(rcPkt)
            
            // ONLY stream turn-by-turn maneuver cards when a route is actively being navigated (and not blocked by a ringing call)
            if self.isNavigationActive && !callActive {
                let navInfo = DashK1GProtocol.buildActiveNavPacket(
                    maneuver: self.activeNavIconCode,
                    nextMeters: self.activeNavDistanceMeters,
                    totalMeters: totalDist,
                    roadName: self.activeNavStreet,
                    nextManeuver: self.activeNavNextIconCode,
                    seq: self.nextSeq()
                )
                self.sendRawPacket(navInfo)
            }
            
            // Keep Music Cards (05 17 = 0x55) + Zoom Icons active at 1 Hz even during calls so the handlebar
            // joystick always forwards Left/Right/Up/Down/Center events without showing the stock call banner!
            let media = MediaPlaybackService.shared
            let musicPkts = K1GPacket.makeMusicCardPackets(
                title: media.currentTitle,
                album: media.currentAlbum,
                artist: media.currentArtist,
                isPlaying: media.isPlaying,
                nextSeq: { self.nextSeq() }
            )
            for p in musicPkts {
                self.sendRawPacket(p)
            }
        }
        rcTimer.resume()
        self.routeCardKeepaliveTimer = rcTimer
        
        // Timer 3: 4 Hz Projection Frame Heartbeat (q3c.g)
        let projTimer = DispatchSource.makeTimerSource(flags: .strict, queue: heartbeatQueue)
        projTimer.schedule(deadline: .now() + 0.25, repeating: .milliseconds(250), leeway: .milliseconds(20))
        projTimer.setEventHandler { [weak self] in
            guard let self = self, self.connectionState == .connected else { return }
            if let gPkt = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_g_proj_frame) {
                self.sendRawPacket(DashK1GProtocol.patchSequence(data: gPkt, seq: self.nextSeq()))
            }
        }
        projTimer.resume()
        self.projHeartbeatTimer = projTimer
    }
    
    private func stopAllTimers() {
        stopAuthTimer()
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        routeCardKeepaliveTimer?.cancel()
        routeCardKeepaliveTimer = nil
        projHeartbeatTimer?.cancel()
        projHeartbeatTimer = nil
    }
    
    // MARK: - Dual-Destination Packet Transmission (Unicast + Subnet Broadcast)
    public func sendRawPacket(_ data: Data) {
        guard socketFD >= 0 else { return }
        
        sendToHost(data, host: dashIP, port: bikePort)
        sendToHost(data, host: broadcastIP, port: bikePort)
        
        if bikePort != listenPort {
            sendToHost(data, host: dashIP, port: listenPort)
        }
    }
    
    private func sendToHost(_ data: Data, host: String, port: UInt16) {
        var destAddr = sockaddr_in()
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = port.bigEndian
        inet_pton(AF_INET, host, &destAddr.sin_addr)
        
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            withUnsafePointer(to: &destAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = sendto(socketFD, base, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
    
    private func nextSeq() -> UInt8 {
        let s = rollingSeq
        rollingSeq = (rollingSeq &+ 1)
        return s
    }
    
    // MARK: - Public Actions for Nav, Music, Weather, Call
    public func sendManeuver(
        iconCode: UInt8,
        distanceMeters: UInt32,
        totalDistanceMeters: UInt32 = 0,
        remainingSeconds: Int = 0,
        streetName: String,
        nextIconCode: UInt8 = DashK1GProtocol.navManeuverHidden,
        etaText: String = ""
    ) {
        let total = totalDistanceMeters > 0 ? Int(totalDistanceMeters) : Int(distanceMeters)
        let remSecs = remainingSeconds > 0 ? remainingSeconds : max(60, total / 11)
        DispatchQueue.main.async {
            self.isNavigationActive = true
            self.activeNavIconCode = iconCode
            self.activeNavDistanceMeters = Int(distanceMeters)
            self.activeNavTotalDistanceMeters = total
            self.activeNavRemainingSeconds = remSecs
            self.activeNavStreet = streetName
            self.activeNavNextIconCode = nextIconCode
            self.activeNavEtaText = etaText
            TFTProjectionService.shared.triggerImmediateFrame()
        }
        guard connectionState == .connected else { return }
        let call = CallHandlingService.shared
        let rcPkt = DashK1GProtocol.buildRouteCardPacket(
            title: streetName.isEmpty ? "Navigation" : streetName,
            seq: nextSeq(),
            projectionOn: true,
            isNavigating: true,
            isCallActive: call.isRinging || call.isOngoing,
            maneuver: iconCode,
            totalDistanceMeters: total,
            remainingTimeSeconds: remSecs,
            arrivalDate: Date().addingTimeInterval(TimeInterval(remSecs))
        )
        sendRawPacket(rcPkt)
        let packet = DashK1GProtocol.buildActiveNavPacket(
            maneuver: iconCode,
            nextMeters: Int(distanceMeters),
            totalMeters: total,
            roadName: streetName,
            nextManeuver: nextIconCode,
            seq: nextSeq()
        )
        sendRawPacket(packet)
    }
    
    public func stopNavigation() {
        DispatchQueue.main.async {
            self.isNavigationActive = false
            self.activeNavStreet = ""
            self.activeNavDistanceMeters = 0
            self.activeNavTotalDistanceMeters = 0
            self.activeNavRemainingSeconds = 0
            self.activeNavNextIconCode = DashK1GProtocol.navManeuverHidden
            self.activeNavEtaText = ""
            TFTProjectionService.shared.triggerImmediateFrame()
        }
        guard connectionState == .connected else { return }
        let call = CallHandlingService.shared
        // Immediately send clean route card with maneuver = 0xFF to hide turn-by-turn bubble
        let rcPkt = DashK1GProtocol.buildRouteCardPacket(
            title: buildHomescreenBannerTitle(),
            seq: nextSeq(),
            projectionOn: true,
            isNavigating: false,
            isCallActive: call.isRinging || call.isOngoing
        )
        sendRawPacket(rcPkt)
        log("🧭 Returned TFT to Clean Digital Homescreen (Turn-by-Turn Hidden)")
    }
    
    public func sendMusicUpdate(title: String, album: String = "", artist: String, isPlaying: Bool) {
        TFTProjectionService.shared.triggerImmediateFrame()
        guard connectionState == .connected else { return }
        let call = CallHandlingService.shared
        // Do not overwrite native Call Popup if a phone call is currently ringing or active
        guard !call.isRinging && !call.isOngoing else { return }
        
        let packets = K1GPacket.makeMusicCardPackets(
            title: title,
            album: album,
            artist: artist,
            isPlaying: isPlaying,
            nextSeq: { self.nextSeq() }
        )
        for p in packets {
            sendRawPacket(p)
        }
        // Also update the route card banner & heartbeat volume immediately
        let rcPkt = DashK1GProtocol.buildRouteCardPacket(
            title: buildHomescreenBannerTitle(),
            seq: nextSeq(),
            projectionOn: true,
            isNavigating: isNavigationActive,
            isCallActive: false,
            maneuver: activeNavIconCode,
            totalDistanceMeters: max(activeNavTotalDistanceMeters, activeNavDistanceMeters),
            remainingTimeSeconds: activeNavRemainingSeconds,
            arrivalDate: Date().addingTimeInterval(TimeInterval(activeNavRemainingSeconds))
        )
        sendRawPacket(rcPkt)
    }
    
    public func sendWeatherUpdate() {
        guard connectionState == .connected else { return }
        let battery = BatteryOptimizationService.shared
        let weather = WeatherService.shared
        let media = MediaPlaybackService.shared
        
        let hb0049 = K1GPacket.makeHeartbeatPacket(
            batteryPct: battery.batteryLevelPercent,
            charging: battery.isCharging,
            gpsOn: true,
            weatherIcon: (showWeatherOnTFT && weather.isLoaded) ? weather.dashWeatherIcon : 0xFF,
            tempC: (showWeatherOnTFT && weather.isLoaded) ? weather.temperatureC : nil,
            volumePercent: media.volumePercent,
            callStatusCode: 0x32
        )
        sendRawPacket(DashK1GProtocol.patchSequence(data: hb0049, seq: nextSeq()))
        TFTProjectionService.shared.triggerImmediateFrame()
    }
    
    public func sendCallAlert(callerName: String, isRinging: Bool, isOngoing: Bool, durationSeconds: UInt32) {
        // Immediately render our custom H.264 Call Card on UDP/5000 while keeping K1G 05 21 = 0x32
        // so the bike firmware's stock incoming call banner NEVER appears on the TFT screen!
        TFTProjectionService.shared.triggerImmediateFrame()
        guard connectionState == .connected else { return }
        
        heartbeatQueue.async { [weak self] in
            guard let self = self else { return }
            self.sendRawPacket(DashK1GProtocol.buildSingleTLVPacket(type: 0x05, sub: 0x21, payload: [0x32], seq: self.nextSeq()))
            self.sendRawPacket(DashK1GProtocol.buildSingleTLVPacket(type: 0x05, sub: 0x4D, payload: [0x32], seq: self.nextSeq()))
            if let zoomData = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_zoom_icons) {
                self.sendRawPacket(DashK1GProtocol.patchSequence(data: zoomData, seq: self.nextSeq()))
            }
        }
    }
    
    private func dispatchJoystick(_ event: DashJoystickEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastJoystickEvent = event
            
            let callService = CallHandlingService.shared
            let mediaService = MediaPlaybackService.shared
            
            // Priority 1: Incoming / Ongoing Phone Calls (Supports Call Screen 0x01..0x04/0x16 + Map/Media buttons!)
            if callService.isRinging {
                switch event {
                case .callAnswerLeft, .left, .up, .mediaModeBack, .centerClick, .mediaModeEnter:
                    self.log("📞 Answering incoming call via handlebar (\(event))...")
                    callService.answerCall()
                    return
                case .callRejectRight, .callEndMiddle, .right, .down:
                    self.log("📞 Rejecting incoming call via handlebar (\(event))...")
                    callService.endOrRejectCall()
                    return
                case .callVolumeUp:
                    mediaService.volumeUp()
                    return
                case .callVolumeDown:
                    mediaService.volumeDown()
                    return
                }
            } else if callService.isOngoing {
                switch event {
                case .callRejectRight, .callEndMiddle, .callAnswerLeft, .down, .centerClick, .mediaModeEnter, .right, .left:
                    self.log("📞 Ending ongoing call via handlebar (\(event))...")
                    callService.endOrRejectCall()
                    return
                case .callVolumeUp, .up, .mediaModeBack:
                    mediaService.volumeUp()
                    return
                case .callVolumeDown:
                    mediaService.volumeDown()
                    return
                }
            }
            
            // Priority 2: Riding Controls (Music playback & System Volume)
            switch event {
            case .centerClick, .callEndMiddle:
                // 0x05 = Media Mode Play / Pause
                mediaService.togglePlayPause()
            case .right, .callAnswerLeft:
                // 0x09 (Media Mode Next) or 0x13 (Map Mode Right)
                mediaService.nextTrack()
            case .left, .callRejectRight:
                // 0x0A (Media Mode Prev) or 0x14 (Map Mode Left)
                mediaService.previousTrack()
            case .up, .callVolumeUp, .mediaModeBack:
                // 0x06 (Media Mode Volume Up), 0x03 (Call Volume Up), or 0x12 (Map Mode Up)
                mediaService.volumeUp()
            case .down, .callVolumeDown:
                // 0x07 (Media Mode Volume Down), 0x15 (Map Mode Down), or 0x04 (Call Volume Down)
                mediaService.volumeDown()
            case .mediaModeEnter:
                // 0x18 = First Center Click on Map Screen that opens Dash Media Mode:
                // Do NOT auto-play or change volume! Just push fresh song metadata to the dash.
                self.sendMusicUpdate(
                    title: mediaService.currentTitle,
                    album: mediaService.currentAlbum,
                    artist: mediaService.currentArtist,
                    isPlaying: mediaService.isPlaying
                )
            }
        }
    }
    
    // MARK: - Wi-Fi IP Utility
    private func getLocalWiFiIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}
