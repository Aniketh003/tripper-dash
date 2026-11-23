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
        case .verifyingNetwork: return "Checking Wi-Fi Subnet..."
        case .requestingAuth: return "Sending K1G Auth (q3c.e)..."
        case .exchangingKeys: return "Exchanging RSA-1024 Keys..."
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
    public var broadcastIP: String = "192.168.1.255"
    public var bikePort: UInt16 = DashK1GProtocol.bikeListenPort   // 2000
    public var listenPort: UInt16 = DashK1GProtocol.phoneListenPort // 2002
    
    // Live Diagnostic Logs for UI display
    public var diagnosticLogs: [String] = []
    
    private var socketFD: Int32 = -1
    private var rxThread: Thread?
    private var isRunning: Bool = false
    private var rollingSeq: UInt8 = 0
    
    // Background Timers
    private var heartbeatTimer: DispatchSourceTimer?
    private var routeCardKeepaliveTimer: DispatchSourceTimer?
    private var projHeartbeatTimer: DispatchSourceTimer?
    private var authTimeoutTimer: DispatchSourceTimer?
    
    // RSA Handshake State
    private var dashModulusHex: String? = nil
    private var dashExponentHex: String? = nil
    private var sessionKeySent: Bool = false
    private var authRetries: Int = 0
    
    private let queue = DispatchQueue(label: "com.tripperdash.client", qos: .userInteractive)
    private let heartbeatQueue = DispatchQueue(label: "com.tripperdash.heartbeat", qos: .userInteractive)
    
    private init() {
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
    public func connect(to ip: String = "192.168.1.1", port: UInt16 = DashK1GProtocol.bikeListenPort) {
        disconnect()
        
        self.dashIP = ip
        self.bikePort = port
        self.connectionState = .verifyingNetwork
        self.dashModulusHex = nil
        self.dashExponentHex = nil
        self.sessionKeySent = false
        self.authRetries = 0
        
        log("Initiating connection to Dash at \(ip):\(port) (RX listening on port \(listenPort))...")
        
        // 1. Verify Local Wi-Fi Subnet
        if let localIP = getLocalWiFiIP() {
            log("Local iPhone Wi-Fi IP: \(localIP)")
            if !localIP.hasPrefix("192.168.1.") && !localIP.hasPrefix("192.168.") {
                log("⚠️ Warning: iPhone IP is not on 192.168.1.x subnet!")
                log("👉 Ensure phone is connected to the bike's Wi-Fi hotspot ('\(dashSSID)').")
            } else {
                log("✅ Wi-Fi subnet verified (192.168.1.x).")
            }
        } else {
            log("⚠️ Could not detect Wi-Fi IP. Please check iOS Settings > Wi-Fi.")
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            self.setupSocketAndStart()
        }
    }
    
    public func disconnect() {
        stopAllTimers()
        
        // Send projection teardown TLVs if was running
        if isRunning {
            if let stopPkt = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_h_proj_stop) {
                sendRawPacket(DashK1GProtocol.patchSequence(data: stopPkt, seq: nextSeq()))
            }
            if let offPkt = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_x_proj_off) {
                sendRawPacket(DashK1GProtocol.patchSequence(data: offPkt, seq: nextSeq()))
            }
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
        
        // Bind to port 2002 on all interfaces (0.0.0.0:2002) to absorb dash->phone packets
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
        
        // Start Background Receiver Thread on Port 2002 BEFORE sending burst
        startRXThread()
        
        // Send Initial K1G Burst to port 2000
        DispatchQueue.main.async { self.connectionState = .requestingAuth }
        sendInitialK1GBurst()
        
        // Start 8-second timeout for Dash response
        startAuthTimeout()
    }
    
    private func sendInitialK1GBurst() {
        log("Sending K1G Announcement Burst + Auth Request (q3c.e) to \(dashIP):\(bikePort)...")
        
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
            // Modulus received (07 00)
            let modHex = seg.payload.map { String(format: "%02X", $0) }.joined()
            self.dashModulusHex = modHex
            log("Dash → Sent RSA Public Key Modulus (\(seg.payload.count) B)")
            checkAndSendSessionKey()
        } else if seg.sub == 0x03 {
            // Exponent received (07 03)
            let expHex = seg.payload.map { String(format: "%02X", $0) }.joined()
            self.dashExponentHex = expHex
            log("Dash → Sent RSA Public Key Exponent: 0x\(expHex)")
            checkAndSendSessionKey()
        } else if seg.sub == 0x01 {
            // Auth Status (07 01)
            let status = seg.payload.first ?? 0x00
            if status == 0x01 {
                log("🎉 *** DASH AUTHENTICATION OK (07 01 01) ***")
                stopAuthTimer()
                
                DispatchQueue.main.async {
                    self.connectionState = .connected
                    BackgroundKeepAliveService.shared.startKeepAlive()
                }
                
                // Drive Dash into Navigation Mode
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
        
        // 1. Mandatory IDR Frame Decoded ACK (09 06 0001 55 -> reply with q3c.L2)
        if segHex.hasPrefix("09060001") && segHex.hasSuffix("55") {
            if let l2Data = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_l2) {
                sendRawPacket(DashK1GProtocol.patchSequence(data: l2Data, seq: nextSeq()))
            }
            return
        }
        
        // 2. Handlebar Button Events (09 00 0001 XX)
        if segHex.hasPrefix("09000001") && seg.payload.count >= 1 {
            let buttonByte = seg.payload.last ?? 0
            
            // Crucial: Send echo-ack (06 80 0001 XX) so the dash registers button receipt
            let ackPkt = DashK1GProtocol.buildButtonAck(buttonByte: buttonByte, seq: nextSeq())
            sendRawPacket(ackPkt)
            
            switch buttonByte {
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
                log("🎮 Unknown button byte: 0x\(String(format: "%02X", buttonByte))")
            }
            return
        }
        
        // 3. Other firmware command ACKs
        if segHex.hasPrefix("09040001") && segHex.hasSuffix("55") {
            if let k2 = DashAuthCrypto.hexToData("0016000200000000020100054B314720000612000155") {
                sendRawPacket(DashK1GProtocol.patchSequence(data: k2, seq: nextSeq()))
            }
        } else if segHex.hasPrefix("090A0001") && segHex.hasSuffix("55") {
            if let t2 = DashAuthCrypto.hexToData("0016000200000000020100054B31472000068000010A") {
                sendRawPacket(DashK1GProtocol.patchSequence(data: t2, seq: nextSeq()))
            }
        }
    }
    
    // MARK: - Post-Auth Navigation Transition Sequence
    private func enterNavigationMode() {
        log("Driving Dash to Navigation Mode...")
        
        // 1. Navigation Context + Empty Lists
        for hex in [DashK1GProtocol.q3c_q_nav_ctx, DashK1GProtocol.q3c_r_empty_lists] {
            if let data = DashAuthCrypto.hexToData(hex) {
                sendRawPacket(DashK1GProtocol.patchSequence(data: data, seq: nextSeq()))
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        
        // 2. Pre-z2 Route Card Burst (4 times with 0.25s gap) - establishes route surface
        let routePkt = DashK1GProtocol.buildRouteCardPacket(title: "OpenDash Navigation", seq: nextSeq(), projectionOn: false)
        for _ in 0..<4 {
            sendRawPacket(routePkt)
            Thread.sleep(forTimeInterval: 0.25)
        }
        
        // 3. Projection Frame Heartbeat (q3c.g)
        if let gPkt = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_g_proj_frame) {
            sendRawPacket(DashK1GProtocol.patchSequence(data: gPkt, seq: nextSeq()))
        }
        
        // 4. Start Navigation Command (q3c.z2)
        if let z2Pkt = DashAuthCrypto.hexToData(DashK1GProtocol.q3c_z2_start_nav) {
            sendRawPacket(DashK1GProtocol.patchSequence(data: z2Pkt, seq: nextSeq()))
        }
        
        // 5. Post-z2 confirmation route card with projection ON
        let routePktOn = DashK1GProtocol.buildRouteCardPacket(title: "OpenDash Navigation", seq: nextSeq(), projectionOn: true)
        sendRawPacket(routePktOn)
        
        // 6. Start Keepalive Loops (Heartbeat + Route-Card + Projection Frame)
        startAllKeepalives()
        log("✅ Navigation mode active & keepalives running.")
    }
    
    // MARK: - Timers & Keepalives
    private func startAllKeepalives() {
        stopAllTimers()
        
        // Timer 1: 1 Hz Status Heartbeat (0044 + 0030)
        let hbTimer = DispatchSource.makeTimerSource(flags: .strict, queue: heartbeatQueue)
        hbTimer.schedule(deadline: .now(), repeating: .milliseconds(1000), leeway: .milliseconds(50))
        hbTimer.setEventHandler { [weak self] in
            guard let self = self, self.connectionState == .connected else { return }
            let hb0044 = K1GPacket.makeHeartbeatPacket()
            self.sendRawPacket(DashK1GProtocol.patchSequence(data: hb0044, seq: self.nextSeq()))
            let hb0030 = K1GPacket.makeMetadata0030Packet()
            self.sendRawPacket(DashK1GProtocol.patchSequence(data: hb0030, seq: self.nextSeq()))
        }
        hbTimer.resume()
        self.heartbeatTimer = hbTimer
        
        // Timer 2: 1 Hz Route Card Keep-alive (Prevents 15-second dash watchdog timeout)
        let rcTimer = DispatchSource.makeTimerSource(flags: .strict, queue: heartbeatQueue)
        rcTimer.schedule(deadline: .now() + 1.0, repeating: .milliseconds(1000), leeway: .milliseconds(50))
        rcTimer.setEventHandler { [weak self] in
            guard let self = self, self.connectionState == .connected else { return }
            let rcPkt = DashK1GProtocol.buildRouteCardPacket(title: "OpenDash Navigation", seq: self.nextSeq(), projectionOn: true)
            self.sendRawPacket(rcPkt)
            
            // Also send active instruction packet
            let navInfo = DashK1GProtocol.buildActiveNavPacket(maneuver: 0x0B, nextMeters: 500, totalMeters: 1200, seq: self.nextSeq())
            self.sendRawPacket(navInfo)
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
        
        // 1. Send Unicast to Bike (192.168.1.1:2000)
        sendToHost(data, host: dashIP, port: bikePort)
        
        // 2. Send Broadcast to Subnet (192.168.1.255:2000)
        sendToHost(data, host: broadcastIP, port: bikePort)
        
        // 3. Fallback to 2002 for firmware variants
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
