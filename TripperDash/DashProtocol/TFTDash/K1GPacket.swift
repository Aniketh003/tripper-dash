import Foundation

// MARK: - K1G Command Identifiers
public enum K1GCommand: UInt8 {
    case handshake = 0x07
    case ack = 0x09
    case keepAlive = 0x05
    case navigationState = 0x10
    case joystickEvent = 0x20
    case telemetry = 0x30
}

// MARK: - Joystick Input Events from Handlebar
public enum DashJoystickEvent: UInt8, Sendable {
    case left = 0x01
    case right = 0x02
    case down = 0x03
    case centerClick = 0x04
    case up = 0x05
}

// MARK: - Packet Builder & Parser
public struct K1GPacket {
    public static let magicHeader: [UInt8] = [0xAA, 0x55]
    
    // Build 1 Hz Heartbeat Packet
    public static func makeHeartbeatPacket() -> Data {
        var bytes: [UInt8] = magicHeader
        bytes.append(K1GCommand.keepAlive.rawValue)
        bytes.append(0x01) // Length
        bytes.append(0x01) // Tick payload
        return Data(bytes)
    }
    
    // Build Navigation Maneuver TLV Packet
    public static func makeManeuverPacket(
        iconCode: UInt8,
        distanceMeters: UInt32,
        streetName: String
    ) -> Data {
        var bytes: [UInt8] = magicHeader
        bytes.append(K1GCommand.navigationState.rawValue)
        
        let streetData = streetName.prefix(16).data(using: .utf8) ?? Data()
        let payloadLength = UInt8(1 + 4 + streetData.count)
        bytes.append(payloadLength)
        
        // Maneuver Icon
        bytes.append(iconCode)
        
        // Distance (4 bytes Big Endian)
        bytes.append(UInt8((distanceMeters >> 24) & 0xFF))
        bytes.append(UInt8((distanceMeters >> 16) & 0xFF))
        bytes.append(UInt8((distanceMeters >> 8) & 0xFF))
        bytes.append(UInt8(distanceMeters & 0xFF))
        
        // Street name string
        bytes.append(contentsOf: streetData)
        
        return Data(bytes)
    }
    
    // Parse Incoming Dash Event (such as handlebar joystick clicks)
    public static func parseIncoming(data: Data) -> DashJoystickEvent? {
        guard data.count >= 4 else { return nil }
        let bytes = [UInt8](data)
        
        // Check for joystick command
        if bytes[2] == K1GCommand.joystickEvent.rawValue {
            let eventByte = bytes[4]
            return DashJoystickEvent(rawValue: eventByte)
        }
        return nil
    }
}
