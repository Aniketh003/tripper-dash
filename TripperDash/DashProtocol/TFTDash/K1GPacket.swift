import Foundation

// MARK: - K1G Command Identifiers
public enum K1GCommand: UInt8 {
    case handshake = 0x07
    case ack = 0x09
    case keepAlive = 0x05
    case navigationState = 0x10
    case joystickEvent = 0x20
    case musicState = 0x21
    case callState = 0x22
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
    
    // Build Music Playback Info Packet for the Dash Gold Band
    public static func makeMusicInfoPacket(
        title: String,
        artist: String,
        isPlaying: Bool
    ) -> Data {
        var bytes: [UInt8] = magicHeader
        bytes.append(K1GCommand.musicState.rawValue)
        
        let titleData = title.prefix(20).data(using: .utf8) ?? Data()
        let artistData = artist.prefix(16).data(using: .utf8) ?? Data()
        let totalPayload = 1 + 1 + titleData.count + 1 + artistData.count
        bytes.append(UInt8(min(totalPayload, 255)))
        
        // Playback state byte: 0x01 = playing, 0x00 = paused
        bytes.append(isPlaying ? 0x01 : 0x00)
        
        // Title length + title bytes
        bytes.append(UInt8(titleData.count))
        bytes.append(contentsOf: titleData)
        
        // Artist length + artist bytes
        bytes.append(UInt8(artistData.count))
        bytes.append(contentsOf: artistData)
        
        return Data(bytes)
    }
    
    // Build Incoming/Ongoing Call Alert Packet for the Dash Overlay
    public static func makeCallAlertPacket(
        callerName: String,
        isRinging: Bool,
        isOngoing: Bool,
        durationSeconds: UInt32
    ) -> Data {
        var bytes: [UInt8] = magicHeader
        bytes.append(K1GCommand.callState.rawValue)
        
        let nameData = callerName.prefix(20).data(using: .utf8) ?? Data()
        let payloadLength = 1 + 4 + nameData.count
        bytes.append(UInt8(min(payloadLength, 255)))
        
        // Call status: 0x01 = ringing, 0x02 = ongoing, 0x00 = idle/ended
        let statusByte: UInt8 = isRinging ? 0x01 : (isOngoing ? 0x02 : 0x00)
        bytes.append(statusByte)
        
        // Call duration in seconds (4 bytes)
        bytes.append(UInt8((durationSeconds >> 24) & 0xFF))
        bytes.append(UInt8((durationSeconds >> 16) & 0xFF))
        bytes.append(UInt8((durationSeconds >> 8) & 0xFF))
        bytes.append(UInt8(durationSeconds & 0xFF))
        
        // Caller name
        bytes.append(contentsOf: nameData)
        
        return Data(bytes)
    }
    
    // Parse Incoming Dash Event (handlebar joystick clicks)
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
