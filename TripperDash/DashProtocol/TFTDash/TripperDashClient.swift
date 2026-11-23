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
    private var heartbeatTimer: Timer?
    private let queue = DispatchQueue(label: "com.tripperdash.network", qos: .userInitiated)
    
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
                    self.startHeartbeat()
                    self.startReceiving()
                case .failed(let error):
                    print("Dash connection failed: \(error)")
                    self.connectionState = .failed
                case .cancelled:
                    self.connectionState = .disconnected
                default:
                    break
                }
            }
        }
        
        conn.start(queue: queue)
    }
    
    public func disconnect() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        connection?.cancel()
        connection = nil
        connectionState = .disconnected
    }
    
    // MARK: - Keep-Alive Heartbeat
    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        DispatchQueue.main.async {
            self.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.sendHeartbeat()
            }
        }
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
    
    private func sendData(_ data: Data) {
        guard let conn = connection, connectionState == .connected || connectionState == .streaming else { return }
        conn.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("Failed to send UDP packet: \(error)")
            }
        }))
    }
    
    // MARK: - Inbound Dash Listener (Joystick events)
    private func startReceiving() {
        guard let conn = connection else { return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] content, _, _, error in
            guard let self = self else { return }
            if let data = content, let event = K1GPacket.parseIncoming(data: data) {
                DispatchQueue.main.async {
                    self.lastJoystickEvent = event
                }
            }
            if error == nil && self.connectionState == .connected {
                self.startReceiving()
            }
        }
    }
}
