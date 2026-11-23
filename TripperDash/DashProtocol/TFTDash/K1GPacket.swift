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
    /// Dynamically encodes REAL battery, outdoor weather temperature, music & call states
    /// (fixing the old hardcoded 0521000132 bug that overwrote call states every second!)
    public static func makeHeartbeatPacket(
        batteryPct: Int = 85,
        charging: Bool = false,
        gpsOn: Bool = true,
        tempC: Int = 25,
        cellSignal: Int = 255,
        isMusicPlaying: Bool = false,
        callStatusCode: UInt8 = 0x30 // 0x30 = Idle, 0x31 = Ringing, 0x32 = Ongoing
    ) -> Data {
        let signalHex = String(format: "06080001%02X", min(255, max(0, cellSignal)))
        let tempByte = UInt8((tempC + 40) & 0xFF)
        let tempHex = String(format: "06100001%02X", tempByte)
        let gpsHex = "06030001" + (gpsOn ? "55" : "AA")
        let batByte = UInt8((min(100, max(0, batteryPct)) + 100) & 0xFF)
        let batHex = String(format: "06040001%02X", batByte)
        let chgHex = "060F0001" + (charging ? "55" : "AA")
        let musicHex = isMusicPlaying ? "054C000118" : "054C000110"
        let distHex = "052D00020000"
        let alarmHex = "051B000115"
        let callTailHex = String(format: "05210001%02X054D000132", callStatusCode)
        
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
            
        guard let data = DashAuthCrypto.hexToData(inner) else { return Data() }
        let count = UInt16(data.count)
        var bytes = [UInt8](data)
        bytes[0] = UInt8(count >> 8)
        bytes[1] = UInt8(count & 0xFF)
        return Data(bytes)
    }
    
    /// Builds the authentic Royal Enfield 0030 1Hz Metadata Packet
    public static func makeMetadata0030Packet(
        cellSignal: Int = 255,
        isMusicPlaying: Bool = false,
        callStatusCode: UInt8 = 0x30
    ) -> Data {
        let signalHex = String(format: "06080001%02X", min(255, max(0, cellSignal)))
        let musicHex = isMusicPlaying ? "054C000118" : "054C000110"
        let distHex = "052D00020000"
        let alarmHex = "051B000115"
        let callTailHex = String(format: "05210001%02X054D000132", callStatusCode)
        
        let inner = "0030000600000000020100054B31472000"
            + signalHex
            + musicHex
            + distHex
            + alarmHex
            + callTailHex
            
        guard let data = DashAuthCrypto.hexToData(inner) else { return Data() }
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
    
    // Build Music Playback + Volume Info Packet for TFT Homescreen & Gold Band
    public static func makeMusicInfoPacket(
        title: String,
        artist: String,
        isPlaying: Bool,
        volumePercent: Int = 50
    ) -> Data {
        var bytes = [UInt8](DashAuthCrypto.hexToData("0000000500000000020100054B31472000") ?? Data())
        
        // 05 4C: Play/Pause state (0x18 playing, 0x10 paused)
        bytes.append(contentsOf: [0x05, 0x4C, 0x00, 0x01, isPlaying ? 0x18 : 0x10])
        
        // 05 50: System Volume Percentage (0..100)
        let volByte = UInt8(min(100, max(0, volumePercent)))
        bytes.append(contentsOf: [0x05, 0x50, 0x00, 0x01, volByte])
        
        // 05 4E: Song Title UTF-8
        let titleData = Array(title.prefix(36).utf8) + [0x00]
        bytes.append(contentsOf: [0x05, 0x4E, UInt8(titleData.count >> 8), UInt8(titleData.count & 0xFF)])
        bytes.append(contentsOf: titleData)
        
        // 05 4F: Artist Name UTF-8
        let artistData = Array(artist.prefix(32).utf8) + [0x00]
        bytes.append(contentsOf: [0x05, 0x4F, UInt8(artistData.count >> 8), UInt8(artistData.count & 0xFF)])
        bytes.append(contentsOf: artistData)
        
        let count = UInt16(bytes.count)
        bytes[0] = UInt8(count >> 8)
        bytes[1] = UInt8(count & 0xFF)
        return Data(bytes)
    }
    
    // Build Outdoor Weather Packet for TFT Digital Homescreen
    public static func makeWeatherPacket(
        tempC: Int,
        condition: String,
        location: String,
        windKmh: Int
    ) -> Data {
        var bytes = [UInt8](DashAuthCrypto.hexToData("0000000400000000020100054B31472000") ?? Data())
        
        // 06 10: Authentic K1G Temperature Byte (tempC + 40)
        let tempByte = UInt8((tempC + 40) & 0xFF)
        bytes.append(contentsOf: [0x06, 0x10, 0x00, 0x01, tempByte])
        
        // 05 51: Weather Summary String UTF-8
        let summary = "\(tempC)°C \(condition)" + (location.isEmpty ? "" : " · \(location)")
        let summaryData = Array(summary.prefix(40).utf8) + [0x00]
        bytes.append(contentsOf: [0x05, 0x51, UInt8(summaryData.count >> 8), UInt8(summaryData.count & 0xFF)])
        bytes.append(contentsOf: summaryData)
        
        // 05 52: Wind km/h
        bytes.append(contentsOf: [0x05, 0x52, 0x00, 0x01, UInt8(min(255, max(0, windKmh)))])
        
        let count = UInt16(bytes.count)
        bytes[0] = UInt8(count >> 8)
        bytes[1] = UInt8(count & 0xFF)
        return Data(bytes)
    }
    
    // Build Incoming/Ongoing Call Alert Packet with Caller Name & Duration
    public static func makeCallAlertPacket(
        callerName: String,
        isRinging: Bool,
        isOngoing: Bool,
        durationSeconds: UInt32
    ) -> Data {
        var bytes = [UInt8](DashAuthCrypto.hexToData("0000000400000000020100054B31472000") ?? Data())
        
        // 05 21: Call Status (0x31 ringing, 0x32 active, 0x30 idle)
        let callStatus: UInt8 = isRinging ? 0x31 : (isOngoing ? 0x32 : 0x30)
        bytes.append(contentsOf: [0x05, 0x21, 0x00, 0x01, callStatus])
        
        // 05 22: Caller Name UTF-8
        let callerData = Array(callerName.prefix(32).utf8) + [0x00]
        bytes.append(contentsOf: [0x05, 0x22, UInt8(callerData.count >> 8), UInt8(callerData.count & 0xFF)])
        bytes.append(contentsOf: callerData)
        
        // 05 23: Call Duration (2-byte big endian seconds)
        let dur = UInt16(min(65535, durationSeconds))
        bytes.append(contentsOf: [0x05, 0x23, 0x00, 0x02, UInt8(dur >> 8), UInt8(dur & 0xFF)])
        
        let count = UInt16(bytes.count)
        bytes[0] = UInt8(count >> 8)
        bytes[1] = UInt8(count & 0xFF)
        return Data(bytes)
    }
}
