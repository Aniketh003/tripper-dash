import Foundation
import Network

public enum DashConnectionState: String, Sendable {
    case disconnected = "Disconnected"
    case connecting = "Connecting to Dash Wi-Fi..."
    case connected = "Connected to TFT Dash"
    case streaming = "Projecting Navigation"
    case failed = "Connection Failed"
}

@Observable
public final class TripperDashClient: @unchecked Sendable {
    public static let shared = TripperDashClient()
    
    public var connectionState: DashConnectionState = .disconnected
    public var lastJoystickEvent: DashJoystickEvent? = nil
    public var dashSSID: String = "RE_450_HIMALAYAN"
    public var dashIP: String = "192.168.1.1"
    public var controlPort: UInt16 = 2002
    
    private var connection: NWConnection?
    private var heartbeatSource: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.tripperdash.network", qos: .userInteractive)
    private let heartbeatQueue = DispatchQueue(label: "com.tripperdash.heartbeat", qos: .userInteractive)
    
    private init() {}
    
    // MARK: - Connection Control
    public func connect(to ip: String = "192.168.1.1", port: UInt16 = 2002) {
        disconnect()
        
        self.dashIP = ip
        self.controlPort = port
        self.connectionState = .connecting
        
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: NWEndpoint.Port(rawValue: port)!)
        let params = NWParameters.udp
        
        let conn = NWConnection(to: endpoint, using: params)
        self.connection = conn
        
        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self.connectionState = .connected
                    // Keep background socket and CPU awake even when phone display turns off
                    BackgroundKeepAliveService.shared.startKeepAlive()
                    self.startHeartbeat()
                    self.startReceiving()
                case .failed(let error):
                    print("Dash connection failed: \(error)")
                    self.connectionState = .failed
                    BackgroundKeepAliveService.shared.stopKeepAlive()
                case .cancelled:
                    self.connectionState = .disconnected
                    BackgroundKeepAliveService.shared.stopKeepAlive()
                default:
                    break
                }
            }
        }
        
        conn.start(queue: queue)
    }
    
    public func disconnect() {
        stopHeartbeat()
        connection?.cancel()
        connection = nil
        connectionState = .disconnected
        BackgroundKeepAliveService.shared.stopKeepAlive()
    }
    
    // MARK: - Keep-Alive Heartbeat (DispatchSourceTimer ensures execution with screen locked)
    private func startHeartbeat() {
        stopHeartbeat()
        
        let source = DispatchSource.makeTimerSource(flags: .strict, queue: heartbeatQueue)
        source.schedule(deadline: .now(), repeating: .milliseconds(1000), leeway: .milliseconds(50))
        source.setEventHandler { [weak self] in
            self?.sendHeartbeat()
        }
        source.resume()
        self.heartbeatSource = source
    }
    
    private func stopHeartbeat() {
        heartbeatSource?.cancel()
        heartbeatSource = nil
    }
    
    private func sendHeartbeat() {
        let packet = K1GPacket.makeHeartbeatPacket()
        sendData(packet)
    }
    
    // MARK: - Navigation Maneuver Updates
    public func sendManeuver(iconCode: UInt8, distanceMeters: UInt32, streetName: String) {
        let packet = K1GPacket.makeManeuverPacket(
            iconCode: iconCode,
            distanceMeters: distanceMeters,
            streetName: streetName
        )
        sendData(packet)
    }
    
    // MARK: - Music Display on Dash Gold Band
    public func sendMusicUpdate(title: String, artist: String, isPlaying: Bool) {
        let packet = K1GPacket.makeMusicInfoPacket(
            title: title,
            artist: artist,
            isPlaying: isPlaying
        )
        sendData(packet)
    }
    
    // MARK: - Call Alerts on Dash Screen
    public func sendCallAlert(callerName: String, isRinging: Bool, isOngoing: Bool, durationSeconds: UInt32) {
        let packet = K1GPacket.makeCallAlertPacket(
            callerName: callerName,
            isRinging: isRinging,
            isOngoing: isOngoing,
            durationSeconds: durationSeconds
        )
        sendData(packet)
    }
    
    private func sendData(_ data: Data) {
        guard let conn = connection, connectionState == .connected || connectionState == .streaming else { return }
        conn.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("Failed to send UDP packet: \(error)")
            }
        }))
    }
    
    // MARK: - Inbound Dash Listener (Joystick events from Handlebar)
    private func startReceiving() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] content, _, _, error in
            guard let self = self else { return }
            if let data = content, let event = K1GPacket.parseIncoming(data: data) {
                DispatchQueue.main.async {
                    self.lastJoystickEvent = event
                    self.handleJoystickEvent(event)
                }
            }
            if error == nil && self.connectionState == .connected {
                self.startReceiving()
            }
        }
    }
    
    // MARK: - Handlebar 5-Way Joystick Action Dispatcher
    private func handleJoystickEvent(_ event: DashJoystickEvent) {
        let callService = CallHandlingService.shared
        let mediaService = MediaPlaybackService.shared
        
        // Priority 1: Handle Incoming / Active Call
        if callService.isRinging {
            switch event {
            case .centerClick, .up:
                callService.answerCall()
            case .down:
                callService.endOrRejectCall()
            default:
                break
            }
            return
        } else if callService.isOngoing {
            if event == .down || event == .centerClick {
                callService.endOrRejectCall()
            }
            return
        }
        
        // Priority 2: Music Playback Control while Riding
        switch event {
        case .centerClick:
            mediaService.togglePlayPause()
        case .right:
            mediaService.nextTrack()
        case .left:
            mediaService.previousTrack()
        default:
            break
        }
    }
}
