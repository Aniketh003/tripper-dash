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
        case .requestingAuth: return "Sending K1G Auth (q3c.e)..."
        case .exchangingKeys: return "Exchanging RSA Keys..."
        case .connected: return "Connected (Nav Active)"
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
    public var controlPort: UInt16 = 2002
    
    // Live Diagnostic Logs for UI display
    public var diagnosticLogs: [String] = []
    
    private var socketFD: Int32 = -1
    private var rxThread: Thread?
    private var isRunning: Bool = false
    private var rollingSeq: UInt8 = 0
    private var heartbeatTimer: DispatchSourceTimer?
    
    // RSA Handshake State
    private var dashModulusHex: String? = nil
    private var dashExponentHex: String? = nil
    private var sessionKeySent: Bool = false
    private var authTimeoutTimer: DispatchSourceTimer?
    
    private let queue = DispatchQueue(label: "com.tripperdash.client", qos: .userInteractive)
    private let heartbeatQueue = DispatchQueue(label: "com.tripperdash.heartbeat", qos: .userInteractive)
    
    private init() {
        // Load saved SSID if available
        if let savedSSID = UserDefaults.standard.string(forKey: "pref_dash_ssid"), !savedSSID.isEmpty {
            self.dashSSID = savedSSID
        }
    }
    
    public func setDashSSID(_ newSSID: String) {
        let trimmed = newSSID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.dashSSID = trimmed
        UserDefaults.standard.set(trimmed, forKey: "pref_dash_ssid")
        log("Updated Dash SSID to: '\(trimmed)'")
    }
    
    public func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        print(entry)
        DispatchQueue.main.async {
            self.diagnosticLogs.append(entry)
            if self.diagnosticLogs.count > 100 {
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
    public func connect(to ip: String = "192.168.1.1", port: UInt16 = 2002) {
        disconnect()
        
        self.dashIP = ip
        self.controlPort = port
        self.connectionState = .verifyingNetwork
        self.dashModulusHex = nil
        self.dashExponentHex = nil
        self.sessionKeySent = false
        
        log("Connecting to Royal Enfield Dash at \(ip):\(port)...")
        
        // 1. Verify Local Wi-Fi Subnet
        if let localIP = getLocalWiFiIP() {
            log("Local Wi-Fi IP: \(localIP)")
            if !localIP.hasPrefix("192.168.1.") && !localIP.hasPrefix("192.168.") {
                log("⚠️ iPhone IP is not on 192.168.1.x subnet!")
                log("👉 Make sure you joined the bike's Wi-Fi ('\(dashSSID)') in iOS Settings > Wi-Fi (Password: 12345678).")
            }
        } else {
            log("⚠️ Could not detect Wi-Fi IP! Please check if Wi-Fi is enabled and connected to the bike.")
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            self.setupSocketAndStart()
        }
    }
    
    public func disconnect() {
        stopHeartbeat()
        stopAuthTimer()
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
        
        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))
        
        // Bind to port 2002 on all interfaces (0.0.0.0:2002)
        var bindAddr = sockaddr_in()
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = controlPort.bigEndian
        bindAddr.sin_addr.s_addr = INADDR_ANY.bigEndian
        
        let bindResult = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        if bindResult < 0 {
            let err = String(cString: strerror(errno))
            log("⚠️ Warning: bind to port \(controlPort) returned: \(err)")
        } else {
            log("✅ Bound UDP listening socket to port \(controlPort).")
        }
        
        isRunning = true
        
        // Start Background Receiver Thread
        startRXThread()
        
        // Send Initial K1G Burst
        DispatchQueue.main.async { self.connectionState = .requestingAuth }
        sendInitialK1GBurst()
        
        // Start 6-second timeout for Dash response
        startAuthTimeout()
    }
    
    private func sendInitialK1GBurst() {
        log("Sending K1G Auth Request (q3c.e) to \(dashIP):\(controlPort)...")
        
        for h in DashK1GProtocol.initialBurstHex {
            if let hex = h {
                if let raw = DashAuthCrypto.hexToData(hex) {
                    let seqPkt = DashK1GProtocol.patchSequence(data: raw, seq: nextSeq())
                    sendRawPacket(seqPkt)
                }
            } else {
                let hostPkt = DashK1GProtocol.buildHostnameAnnounce(hostname: "iPhone", seq: nextSeq())
                sendRawPacket(hostPkt)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
    
    private func startAuthTimeout() {
        stopAuthTimer()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 6.0)
        timer.setEventHandler { [weak self] in
            guard let self = self, self.connectionState != .connected else { return }
            self.log("⚠️ No response received from Dash at \(self.dashIP)!")
            self.log("👉 Check: 1) Is bike ignition ON? 2) Is Dash in Digital Mode (Menu > Appearance > Screen Type > Digital)? 3) Is phone Wi-Fi connected to '\(self.dashSSID)'?")
            DispatchQueue.main.async {
                self.connectionState = .failed("No response from dash (Timeout)")
            }
        }
        timer.resume()
        self.authTimeoutTimer = timer
    }
    
    private func stopAuthTimer() {
        authTimeoutTimer?.cancel()
        authTimeoutTimer = nil
    }
    
    // MARK: - RX Loop on Port 2002
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
            // Check for Auth Segments (0x07)
            if s.type == 0x07 {
                handleAuthSegment(s)
            } else if s.type == 0x09 {
                handleButtonOrAckSegment(s)
            }
        }
    }
    
    private func handleAuthSegment(_ seg: DashK1GProtocol.K1GSegment) {
        if seg.sub == 0x00 {
            // Modulus received
            let modHex = seg.payload.map { String(format: "%02X", $0) }.joined()
            self.dashModulusHex = modHex
            log("Dash → Sent RSA Public Key Modulus (\(seg.payload.count) bytes)")
            checkAndSendSessionKey()
        } else if seg.sub == 0x03 {
            // Exponent received
            let expHex = seg.payload.map { String(format: "%02X", $0) }.joined()
            self.dashExponentHex = expHex
            log("Dash → Sent RSA Public Key Exponent: 0x\(expHex)")
            checkAndSendSessionKey()
        } else if seg.sub == 0x01 {
            // Auth Status Response
            if let status = seg.payload.first, status == 0x01 {
                log("🎉 *** DASH AUTHENTICATION SUCCESS (07 01 01) ***")
                stopAuthTimer()
                
                DispatchQueue.main.async {
                    self.connectionState = .connected
                    BackgroundKeepAliveService.shared.startKeepAlive()
                }
                
                // Activate Navigation Mode on Dash
                sendNavModeKick()
                startHeartbeat()
            } else {
                log("❌ Dash rejected session key (07 01). Did the SSID '\(dashSSID)' match the bike's screen?")
            }
        }
    }
    
    private func checkAndSendSessionKey() {
        guard !sessionKeySent,
              let mod = dashModulusHex,
              let exp = dashExponentHex else { return }
        
        sessionKeySent = true
        DispatchQueue.main.async { self.connectionState = .exchangingKeys }
        log("Encrypting session key with Dash RSA public key (SSID: '\(dashSSID)')...")
        
        do {
            // Generate 32-byte cryptographically secure random AES key
            var aesKey = Data(count: 32)
            _ = aesKey.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
            
            let ciphertext = try DashAuthCrypto.encryptSessionKey(
                ssid: dashSSID,
                modulusHex: mod,
                exponentHex: exp,
                aesKey: aesKey
            )
            
            log("Sending encrypted session key (q3c.d, 128 bytes)...")
            let pkt = DashK1GProtocol.buildQ3CDPacket(ciphertext: ciphertext, seq: nextSeq())
            sendRawPacket(pkt)
        } catch {
            log("❌ RSA Encryption failed: \(error.localizedDescription)")
            DispatchQueue.main.async { self.connectionState = .failed("RSA encryption error") }
        }
    }
    
    private func handleButtonOrAckSegment(_ seg: DashK1GProtocol.K1GSegment) {
        // Frame Decoded ACK (09 06 55) -> Must respond with q3c.l2
        if seg.sub == 0x06 && seg.payload.first == 0x55 {
            if let l2Data = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_l2) {
                sendRawPacket(DashK1GProtocol.patchSequence(data: l2Data, seq: nextSeq()))
            }
            return
        }
        
        // Handlebar Joystick Button Events (09 00 ... XX)
        if seg.sub == 0x00, let lastByte = seg.payload.last {
            switch lastByte {
            case 0x13:
                log("🎮 Handlebar Joystick: RIGHT")
                dispatchJoystick(.right)
            case 0x14:
                log("🎮 Handlebar Joystick: LEFT")
                dispatchJoystick(.left)
            case 0x15:
                log("🎮 Handlebar Joystick: DOWN")
                dispatchJoystick(.down)
            case 0x18:
                log("🎮 Handlebar Joystick: CENTER CLICK")
                dispatchJoystick(.centerClick)
            default:
                break
            }
        }
    }
    
    private func sendNavModeKick() {
        log("Switching Dash to Navigation Mode (q3c.z2 + q3c.w)...")
        for hex in [DashK1GProtocol.q3c_z2_start_nav, DashK1GProtocol.q3c_w_proj_on, DashK1GProtocol.q3c_q_nav_ctx, DashK1GProtocol.q3c_r_empty_lists] {
            if let data = DashAuthCrypto.hexToData(hex) {
                sendRawPacket(DashK1GProtocol.patchSequence(data: data, seq: nextSeq()))
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }
    
    // MARK: - Heartbeat
    private func startHeartbeat() {
        stopHeartbeat()
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: heartbeatQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(1000), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self = self, self.connectionState == .connected else { return }
            let hb = K1GPacket.makeHeartbeatPacket()
            self.sendRawPacket(hb)
        }
        timer.resume()
        self.heartbeatTimer = timer
    }
    
    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }
    
    // MARK: - Packet Transmission
    public func sendRawPacket(_ data: Data) {
        guard socketFD >= 0 else { return }
        
        var destAddr = sockaddr_in()
        destAddr.sin_family = sa_family_t(AF_INET)
        destAddr.sin_port = controlPort.bigEndian
        inet_pton(AF_INET, dashIP, &destAddr.sin_addr)
        
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
    
    // MARK: - Public Actions for Nav, Music, Call
    public func sendManeuver(iconCode: UInt8, distanceMeters: UInt32, streetName: String) {
        let packet = K1GPacket.makeManeuverPacket(iconCode: iconCode, distanceMeters: distanceMeters, streetName: streetName)
        sendRawPacket(packet)
    }
    
    public func sendMusicUpdate(title: String, artist: String, isPlaying: Bool) {
        let packet = K1GPacket.makeMusicInfoPacket(title: title, artist: artist, isPlaying: isPlaying)
        sendRawPacket(packet)
    }
    
    public func sendCallAlert(callerName: String, isRinging: Bool, isOngoing: Bool, durationSeconds: UInt32) {
        let packet = K1GPacket.makeCallAlertPacket(callerName: callerName, isRinging: isRinging, isOngoing: isOngoing, durationSeconds: durationSeconds)
        sendRawPacket(packet)
    }
    
    private func dispatchJoystick(_ event: DashJoystickEvent) {
        DispatchQueue.main.async {
            self.lastJoystickEvent = event
        }
        
        let callService = CallHandlingService.shared
        let mediaService = MediaPlaybackService.shared
        
        if callService.isRinging {
            if event == .centerClick || event == .up { callService.answerCall() }
            else if event == .down { callService.endOrRejectCall() }
            return
        } else if callService.isOngoing {
            if event == .down || event == .centerClick { callService.endOrRejectCall() }
            return
        }
        
        switch event {
        case .centerClick: mediaService.togglePlayPause()
        case .right: mediaService.nextTrack()
        case .left: mediaService.previousTrack()
        default: break
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
                if name == "en0" { // en0 is standard iOS Wi-Fi interface
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
