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

@Observable
public final class TripperDashClient: @unchecked Sendable {
    public static let shared = TripperDashClient()
    
    public var connectionState: DashConnectionState = .disconnected
    public var lastJoystickEvent: DashJoystickEvent? = nil
    public var dashSSID: String = "RE_450_HIMALAYAN"
    public var dashIP: String = "192.168.1.1"
    public var broadcastIP: String = "192.168.1.255"
    public var bikePort: UInt16 = DashK1GProtocol.bikeListenPort   // 2000
    public var listenPort: UInt16 = DashK1GProtocol.phoneListenPort // 2002
    public var isMockMode: Bool = false
    
    // TFT Digital Homescreen Preferences (No Speedometer!)
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
    
    // Active Navigation State (Turn-by-turn bubble is HIDDEN by default when isNavigationActive == false!)
    public var isNavigationActive: Bool = false
    public var activeNavStreet: String = ""
    public var activeNavDistanceMeters: Int = 0
    public var activeNavIconCode: UInt8 = DashK1GProtocol.navManeuverContinue
    
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
        if let savedSSID = UserDefaults.standard.string(forKey: "pref_dash_ssid"), !savedSSID.isEmpty {
            self.dashSSID = savedSSID
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
        UserDefaults.standard.set(trimmed, forKey: "pref_dash_ip")
        log("Updated Dash IP to: '\(trimmed)'")
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
            if s.type == 0x07 {
                handleAuthSegment(s)
            } else if s.type == 0x09 {
                handleDashCommandOrButton(s)
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
        
        // 3. Handlebar Joystick Button Events (09 00 0001 XX)
        // Supports BOTH Dash Map Mode (0x13, 0x14, 0x15, 0x12, 0x18) AND Dash Media Mode (0x05, 0x06, 0x07, 0x09, 0x0A)!
        if segHex.hasPrefix("09000001") && seg.payload.count >= 1 {
            let buttonByte = seg.payload.last ?? 0
            
            // Immediate Echo ACK (06 80 0001 XX) + Zoom Icons if map-mode button
            let ackPkt = DashK1GProtocol.buildButtonAck(buttonByte: buttonByte, seq: nextSeq())
            sendRawPacket(ackPkt)
            if buttonByte == 0x13 || buttonByte == 0x14 || buttonByte == 0x15 {
                if let zoomData = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_zoom_icons) {
                    sendRawPacket(DashK1GProtocol.patchSequence(data: zoomData, seq: nextSeq()))
                }
            }
            
            switch buttonByte {
            case 0x09, 0x13, 0x02:
                // 0x09 = Media Mode Next Track, 0x13 = Map Mode Right
                log("🎮 Handlebar Joystick: RIGHT → Next Track (0x\(String(format: "%02X", buttonByte)))")
                dispatchJoystick(.right)
            case 0x0A, 0x14, 0x01:
                // 0x0A = Media Mode Previous Track, 0x14 = Map Mode Left
                log("🎮 Handlebar Joystick: LEFT → Previous Track (0x\(String(format: "%02X", buttonByte)))")
                dispatchJoystick(.left)
            case 0x06:
                // 0x06 = Media Mode Volume Up
                log("🎮 Handlebar Joystick: UP → Volume Up (0x06)")
                dispatchJoystick(.up)
            case 0x07, 0x15, 0x03:
                // 0x07 = Media Mode Volume Down, 0x15 = Map Mode Down
                log("🎮 Handlebar Joystick: DOWN → Volume Down (0x\(String(format: "%02X", buttonByte)))")
                dispatchJoystick(.down)
            case 0x05, 0x04:
                // 0x05 = Media Mode Center Click (Play / Pause)
                log("🎮 Handlebar Joystick: CENTER → Play / Pause (0x05)")
                dispatchJoystick(.centerClick)
            case 0x18:
                // 0x18 = Map Mode Center Click (Enters Dash Media Mode)
                log("🎛️ Handlebar Joystick: CENTER → Media Control Mode Active (0x18)")
                dispatchJoystick(.mediaModeEnter)
            case 0x12:
                // 0x12 = Joystick Back / Up (Exits Media Mode)
                log("🎛️ Handlebar Joystick: BACK / UP (0x12)")
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
                maneuver: activeNavIconCode,
                totalDistanceMeters: activeNavDistanceMeters
            )
            sendRawPacket(routePkt)
            Thread.sleep(forTimeInterval: i == 0 ? 0.10 : 0.25)
        }
        
        // 3. Projection Frame Heartbeat (q3c.g) + Nav Placeholder (06 0A 0002 0000)
        if let gPkt = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_g_proj_frame) {
            sendRawPacket(DashK1GProtocol.patchSequence(data: gPkt, seq: nextSeq()))
            Thread.sleep(forTimeInterval: 0.05)
        }
        if let phPkt = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_nav_placeholder) {
            sendRawPacket(DashK1GProtocol.patchSequence(data: phPkt, seq: nextSeq()))
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
            maneuver: activeNavIconCode,
            totalDistanceMeters: activeNavDistanceMeters
        )
        sendRawPacket(routePktOn)
        
        // 6. Push initial Real Time Sync + Music Now-Playing Cards immediately
        sendRawPacket(DashK1GProtocol.buildTimeSyncPacket(seq: nextSeq()))
        let media = MediaPlaybackService.shared
        sendMusicUpdate(title: media.currentTitle, album: media.currentAlbum, artist: media.currentArtist, isPlaying: media.isPlaying)
        
        // 7. Start H.264 Digital Homescreen Video Stream (UDP 5000) if enabled & real socket connected
        if enableVideoProjection && !isMockMode {
            TFTProjectionService.shared.startStreaming(to: dashIP)
        }
        
        // 8. Start Keepalive Loops (Live 0049 Heartbeat + Clean Route Card + Music/Call Cards + 4Hz Projection Frame)
        startAllKeepalives()
        log("✅ TFT Digital Homescreen active & synced in real time.")
    }
    
    /// Builds the clean Latin-1 TFT banner string (Weather + Now Playing when idle, Street when navigating)
    private func buildHomescreenBannerTitle() -> String {
        if isNavigationActive && !activeNavStreet.isEmpty {
            return activeNavStreet
        }
        let call = CallHandlingService.shared
        if call.isRinging {
            return "Call: \(call.callerName)"
        }
        if call.isOngoing {
            return "In Call \(call.formattedDuration) - \(call.callerName)"
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
            let call = CallHandlingService.shared
            
            // Authentic CallState codes: 0x0A = Ringing, 0x14 = In-Call, 0x32 = None
            let callCode: UInt8 = call.isRinging ? 0x0A : (call.isOngoing ? 0x14 : 0x32)
            
            let hb0049 = K1GPacket.makeHeartbeatPacket(
                batteryPct: battery.batteryLevelPercent,
                charging: battery.isCharging,
                gpsOn: true,
                weatherIcon: (self.showWeatherOnTFT && weather.isLoaded) ? weather.dashWeatherIcon : 0xFF,
                tempC: (self.showWeatherOnTFT && weather.isLoaded) ? weather.temperatureC : nil,
                volumePercent: media.volumePercent,
                callStatusCode: callCode
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
        
        // Timer 2: 1 Hz TFT Homescreen Route Card (Turn-by-Turn Hidden when idle) + Authentic Music/Call Cards
        let rcTimer = DispatchSource.makeTimerSource(flags: .strict, queue: heartbeatQueue)
        rcTimer.schedule(deadline: .now() + 0.5, repeating: .milliseconds(1000), leeway: .milliseconds(50))
        rcTimer.setEventHandler { [weak self] in
            guard let self = self, self.connectionState == .connected else { return }
            
            let banner = self.buildHomescreenBannerTitle()
            let rcPkt = DashK1GProtocol.buildRouteCardPacket(
                title: banner,
                seq: self.nextSeq(),
                projectionOn: true,
                isNavigating: self.isNavigationActive,
                maneuver: self.activeNavIconCode,
                totalDistanceMeters: self.activeNavDistanceMeters
            )
            self.sendRawPacket(rcPkt)
            
            // ONLY stream turn-by-turn maneuver cards when a route is actively being navigated!
            if self.isNavigationActive {
                let navInfo = DashK1GProtocol.buildActiveNavPacket(
                    maneuver: self.activeNavIconCode,
                    nextMeters: self.activeNavDistanceMeters,
                    totalMeters: self.activeNavDistanceMeters,
                    roadName: self.activeNavStreet,
                    seq: self.nextSeq()
                )
                self.sendRawPacket(navInfo)
            }
            
            // Repeat Authentic Music Now-Playing Cards (05 17, 05 0D, 05 58, 05 19) at 1 Hz
            if self.showMusicOnTFT {
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
            
            // Repeat Authentic Call Cards (05 21, 05 4D, AES-encrypted 05 22) when a call is active
            let call = CallHandlingService.shared
            if call.isRinging || call.isOngoing {
                self.callWasActiveLastTick = true
                let callPkts = K1GPacket.makeCallCardPackets(
                    callerName: call.callerName,
                    isRinging: call.isRinging,
                    isOngoing: call.isOngoing,
                    aesKey: self.sessionAESKey,
                    nextSeq: { self.nextSeq() }
                )
                for p in callPkts {
                    self.sendRawPacket(p)
                }
            } else if self.callWasActiveLastTick {
                self.callWasActiveLastTick = false
                let clearPkts = K1GPacket.makeCallCardPackets(
                    callerName: "",
                    isRinging: false,
                    isOngoing: false,
                    aesKey: self.sessionAESKey,
                    nextSeq: { self.nextSeq() }
                )
                for p in clearPkts {
                    self.sendRawPacket(p)
                }
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
    public func sendManeuver(iconCode: UInt8, distanceMeters: UInt32, streetName: String) {
        DispatchQueue.main.async {
            self.isNavigationActive = true
            self.activeNavIconCode = iconCode
            self.activeNavDistanceMeters = Int(distanceMeters)
            self.activeNavStreet = streetName
            TFTProjectionService.shared.triggerImmediateFrame()
        }
        let packet = DashK1GProtocol.buildActiveNavPacket(
            maneuver: iconCode,
            nextMeters: Int(distanceMeters),
            totalMeters: Int(distanceMeters),
            roadName: streetName,
            seq: nextSeq()
        )
        sendRawPacket(packet)
    }
    
    public func stopNavigation() {
        DispatchQueue.main.async {
            self.isNavigationActive = false
            self.activeNavStreet = ""
            self.activeNavDistanceMeters = 0
            TFTProjectionService.shared.triggerImmediateFrame()
        }
        // Immediately send clean route card with maneuver = 0xFF to hide turn-by-turn bubble
        let rcPkt = DashK1GProtocol.buildRouteCardPacket(
            title: buildHomescreenBannerTitle(),
            seq: nextSeq(),
            projectionOn: true,
            isNavigating: false
        )
        sendRawPacket(rcPkt)
        log("🧭 Returned TFT to Clean Digital Homescreen (Turn-by-Turn Hidden)")
    }
    
    public func sendMusicUpdate(title: String, album: String = "", artist: String, isPlaying: Bool) {
        guard connectionState == .connected else { return }
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
            maneuver: activeNavIconCode,
            totalDistanceMeters: activeNavDistanceMeters
        )
        sendRawPacket(rcPkt)
        TFTProjectionService.shared.triggerImmediateFrame()
    }
    
    public func sendWeatherUpdate() {
        guard connectionState == .connected else { return }
        let battery = BatteryOptimizationService.shared
        let weather = WeatherService.shared
        let media = MediaPlaybackService.shared
        let call = CallHandlingService.shared
        let callCode: UInt8 = call.isRinging ? 0x0A : (call.isOngoing ? 0x14 : 0x32)
        
        let hb0049 = K1GPacket.makeHeartbeatPacket(
            batteryPct: battery.batteryLevelPercent,
            charging: battery.isCharging,
            gpsOn: true,
            weatherIcon: (showWeatherOnTFT && weather.isLoaded) ? weather.dashWeatherIcon : 0xFF,
            tempC: (showWeatherOnTFT && weather.isLoaded) ? weather.temperatureC : nil,
            volumePercent: media.volumePercent,
            callStatusCode: callCode
        )
        sendRawPacket(DashK1GProtocol.patchSequence(data: hb0049, seq: nextSeq()))
        TFTProjectionService.shared.triggerImmediateFrame()
    }
    
    public func sendCallAlert(callerName: String, isRinging: Bool, isOngoing: Bool, durationSeconds: UInt32) {
        guard connectionState == .connected else {
            TFTProjectionService.shared.triggerImmediateFrame()
            return
        }
        let packets = K1GPacket.makeCallCardPackets(
            callerName: callerName,
            isRinging: isRinging,
            isOngoing: isOngoing,
            aesKey: sessionAESKey,
            nextSeq: { self.nextSeq() }
        )
        for p in packets {
            sendRawPacket(p)
        }
        TFTProjectionService.shared.triggerImmediateFrame()
    }
    
    private func dispatchJoystick(_ event: DashJoystickEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastJoystickEvent = event
            
            let callService = CallHandlingService.shared
            let mediaService = MediaPlaybackService.shared
            
            // Priority 1: Incoming / Ongoing Phone Calls
            if callService.isRinging {
                if event == .centerClick || event == .mediaModeEnter || event == .up || event == .mediaModeBack {
                    self.log("📞 Answering incoming call via handlebar...")
                    callService.answerCall()
                    return
                } else if event == .down {
                    self.log("📞 Rejecting incoming call via handlebar...")
                    callService.endOrRejectCall()
                    return
                }
            } else if callService.isOngoing {
                if event == .down || event == .centerClick || event == .mediaModeEnter {
                    self.log("📞 Ending ongoing call via handlebar...")
                    callService.endOrRejectCall()
                    return
                }
            }
            
            // Priority 2: Riding Controls (Music playback & System Volume)
            switch event {
            case .centerClick:
                // 0x05 = Media Mode Play / Pause
                mediaService.togglePlayPause()
            case .right:
                // 0x09 (Media Mode Next) or 0x13 (Map Mode Right)
                mediaService.nextTrack()
            case .left:
                // 0x0A (Media Mode Prev) or 0x14 (Map Mode Left)
                mediaService.previousTrack()
            case .up:
                // 0x06 (Media Mode Volume Up)
                mediaService.volumeUp()
            case .down:
                // 0x07 (Media Mode Volume Down) or 0x15 (Map Mode Down)
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
            case .mediaModeBack:
                // 0x12 = Exited Media Mode on Dash
                TFTProjectionService.shared.triggerImmediateFrame()
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
