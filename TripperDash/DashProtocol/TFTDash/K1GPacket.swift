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
    case right       = 0x13
    case left        = 0x14
    case down        = 0x15
    case centerClick = 0x18
    case up          = 0x05
}

// MARK: - Authentic K1G Packet Builder
public struct K1GPacket {
    
    /// Builds the authentic Royal Enfield 0044 1Hz Heartbeat Status Packet
    /// (reproduced from REForeGroundService.d.run)
    public static func makeHeartbeatPacket(
        batteryPct: Int = 85,
        charging: Bool = false,
        gpsOn: Bool = true,
        tempC: Int = 25,
        cellSignal: Int = 255
    ) -> Data {
        let signalHex = String(format: "06080001%02X", min(255, max(0, cellSignal)))
        let tempByte = UInt8((tempC + 40) & 0xFF)
        let tempHex = String(format: "06100001%02X", tempByte)
        let gpsHex = "06030001" + (gpsOn ? "55" : "AA")
        let batByte = UInt8((batteryPct + 100) & 0xFF)
        let batHex = String(format: "06040001%02X", batByte)
        let chgHex = "060F0001" + (charging ? "55" : "AA")
        let musicHex = "054C000115"
        let distHex = "052D00020000"
        let alarmHex = "051B000115"
        let callTailHex = "0521000132054D000132"
        
        let inner = "0044000A00000000020100054B31472000"
            + signalHex
            + tempHex
            + gpsHex
            + batHex
            + chgHex
            + musicHex
            + distHex
            + alarmHex
            + callTailHex
            
        guard var data = DashAuthCrypto.hexToData(inner) else { return Data() }
        let count = UInt16(data.count)
        var bytes = [UInt8](data)
        bytes[0] = UInt8(count >> 8)
        bytes[1] = UInt8(count & 0xFF)
        return Data(bytes)
    }
    
    /// Builds the authentic Royal Enfield 0030 1Hz Metadata Packet
    /// (reproduced from REForeGroundService.e.run)
    public static func makeMetadata0030Packet(cellSignal: Int = 255) -> Data {
        let signalHex = String(format: "06080001%02X", min(255, max(0, cellSignal)))
        let musicHex = "054C000115"
        let distHex = "052D00020000"
        let alarmHex = "051B000115"
        let callTailHex = "0521000132054D000132"
        
        let inner = "0030000600000000020100054B31472000"
            + signalHex
            + musicHex
            + distHex
            + alarmHex
            + callTailHex
            
        guard var data = DashAuthCrypto.hexToData(inner) else { return Data() }
        let count = UInt16(data.count)
        var bytes = [UInt8](data)
        bytes[0] = UInt8(count >> 8)
        bytes[1] = UInt8(count & 0xFF)
        return Data(bytes)
    }
    
    // Build Navigation Maneuver TLV Packet
    public static func makeManeuverPacket(
        iconCode: UInt8,
        distanceMeters: UInt32,
        streetName: String
    ) -> Data {
        return DashK1GProtocol.buildActiveNavPacket(
            maneuver: iconCode,
            nextMeters: Int(distanceMeters),
            totalMeters: Int(distanceMeters),
            seq: 0
        )
    }
    
    // Build Music Playback Info Packet for the Dash Gold Band
    public static func makeMusicInfoPacket(
        title: String,
        artist: String,
        isPlaying: Bool
    ) -> Data {
        let titleClean = String(title.prefix(20).utf8)
        let artistClean = String(artist.prefix(16).utf8)
        let musicVol = isPlaying ? "054C000118" : "054C000110"
        let inner = "0022000300000000020100054B31472000" + musicVol + "0521000132054D000132"
        return DashAuthCrypto.hexToData(inner) ?? Data()
    }
    
    // Build Incoming/Ongoing Call Alert Packet for the Dash Overlay
    public static func makeCallAlertPacket(
        callerName: String,
        isRinging: Bool,
        isOngoing: Bool,
        durationSeconds: UInt32
    ) -> Data {
        // Status code: 0x31 for ringing, 0x32 for active, 0x30 for idle
        let callStatus: String = isRinging ? "31" : (isOngoing ? "32" : "30")
        let inner = "0022000300000000020100054B3147200005210001" + callStatus + "054D000132"
        return DashAuthCrypto.hexToData(inner) ?? Data()
    }
}
