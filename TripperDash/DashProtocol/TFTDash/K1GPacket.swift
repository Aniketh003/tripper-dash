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

// MARK: - Joystick Input Events from Handlebar (Map Mode + Media Mode + Call Screen)
public enum DashJoystickEvent: UInt8, Sendable {
    case callRejectRight = 0x01 // Call Screen Right (Reject / End Call)
    case callAnswerLeft  = 0x02 // Call Screen Left (Answer Incoming Call)
    case callVolumeUp    = 0x03 // Call Screen Volume Up
    case callVolumeDown  = 0x04 // Call Screen Volume Down
    case centerClick     = 0x05 // Media Mode Play/Pause (0x05)
    case up              = 0x06 // Media Mode Vol Up (0x06)
    case down            = 0x15 // Map Mode Down (0x15) & Media Mode Vol Down (0x07)
    case right           = 0x13 // Map Mode Right (0x13) & Media Mode Next Track (0x09)
    case left            = 0x14 // Map Mode Left (0x14) & Media Mode Prev Track (0x0A)
    case mediaModeBack   = 0x12 // Joystick Back / Up (Exits Dash Media Mode / Map Mode Vol Up)
    case callEndMiddle   = 0x16 // Call Screen Middle (End Active Call)
    case mediaModeEnter  = 0x18 // Map Mode Center Click (Enters Dash Media Mode)
}

// MARK: - Authentic K1G Packet Builder (Verified on Royal Enfield TFT Firmware 11.63 / 13.10)
public struct K1GPacket {

    /// Maps 0..100% media volume to the authentic 11-step K1G volume bucket (0x10 mute .. 0x1A max)
    public static func musicVolumeBucketByte(volumePercent: Int) -> UInt8 {
        if volumePercent <= 0 { return 0x10 }
        let idx = min(9, max(0, (volumePercent * 10) / 100))
        return UInt8(0x11 + idx)
    }

    /// Builds the authentic Royal Enfield 0049 1Hz Heartbeat Status Packet:
    /// - 06 08: Weather Icon (1=Cloudy, 2=Thunder, 3=Rain, 4=Snow, 5=Sun, 0xFF=None)
    /// - 06 10: Weather Temp (tempC + 40; omitted if tempC is nil so no fake temperature is shown)
    /// - 06 03: Phone GPS On (0x55 = on, 0xAA = off)
    /// - 06 04: Phone Battery (batteryPct + 100)
    /// - 06 0F: Phone Charging (0x55 = charging, 0xAA = not charging)
    /// - 06 01: Cell Signal Present (0x01)
    /// - 05 4C: Music Volume Bucket (0x10..0x1A)
    /// - 05 2D: Nav distance placeholder (0x0000)
    /// - 05 1B: Alarm volume bucket (0x19)
    /// - 05 21: Call State (0x0A = Ringing, 0x14 = In-Call, 0x1E = Calling Out, 0x32 = None)
    /// - 05 4D: Call State Trailer (0x32)
    public static func makeHeartbeatPacket(
        batteryPct: Int = 85,
        charging: Bool = false,
        gpsOn: Bool = true,
        weatherIcon: UInt8 = 0xFF,
        tempC: Int? = nil,
        volumePercent: Int = 50,
        callStatusCode: UInt8 = 0x32 // 0x0A = Ringing, 0x14 = In-Call, 0x32 = None
    ) -> Data {
        var tlvs: [[UInt8]] = []

        // 06 08: Weather Icon (NOT cell signal!)
        tlvs.append([0x06, 0x08, 0x00, 0x01, weatherIcon])

        // 06 10: Outdoor Temperature (tempC + 40) — only sent when real weather is loaded
        if let realTemp = tempC {
            let clamped = min(100, max(-40, realTemp))
            let tempByte = UInt8((clamped + 40) & 0xFF)
            tlvs.append([0x06, 0x10, 0x00, 0x01, tempByte])
        }

        // 06 03: GPS On
        tlvs.append([0x06, 0x03, 0x00, 0x01, gpsOn ? 0x55 : 0xAA])

        // 06 04: Battery Percentage + 100
        let batByte = UInt8((min(100, max(0, batteryPct)) + 100) & 0xFF)
        tlvs.append([0x06, 0x04, 0x00, 0x01, batByte])

        // 06 0F: Charging state
        tlvs.append([0x06, 0x0F, 0x00, 0x01, charging ? 0x55 : 0xAA])

        // 06 01: Cell signal present
        tlvs.append([0x06, 0x01, 0x00, 0x01, 0x01])

        // 05 4C: Real 11-step media volume bucket
        tlvs.append([0x05, 0x4C, 0x00, 0x01, musicVolumeBucketByte(volumePercent: volumePercent)])

        // 05 2D: Distance bucket
        tlvs.append([0x05, 0x2D, 0x00, 0x02, 0x00, 0x00])

        // 05 1B: Alarm stream bucket
        tlvs.append([0x05, 0x1B, 0x00, 0x01, 0x19])

        // 05 21 & 05 4D: Call state + trailer
        tlvs.append([0x05, 0x21, 0x00, 0x01, callStatusCode])
        tlvs.append([0x05, 0x4D, 0x00, 0x01, 0x32])

        let segCount = UInt16(tlvs.count + 1)
        var body: [UInt8] = [
            0x00, 0x00,
            UInt8(segCount >> 8), UInt8(segCount & 0xFF),
            0x00, 0x00, 0x00, 0x00, 0x02, 0x01, 0x00, 0x05,
            0x4B, 0x31, 0x47, 0x20,
            0x00
        ]
        for t in tlvs {
            body.append(contentsOf: t)
        }
        let totalLen = UInt16(body.count)
        body[0] = UInt8(totalLen >> 8)
        body[1] = UInt8(totalLen & 0xFF)
        return Data(body)
    }

    // MARK: - Authentic K1G Music Now-Playing Cards (05 17, 05 0D, 05 58, 05 19)
    /// Builds the exact 4-packet K1G sequence the TFT dash uses for its Now Playing music card:
    /// 1) 05 17 = 0x55 (music active) or 0xAA (none)
    /// 2) 05 0D = [album]\0[title]\0[artist] (Latin-1, max 19 chars each)
    /// 3) 05 58 = 0xAA (no JPEG cover slices)
    /// 4) 05 19 = 0x55 (playing) or 0xAA (paused)
    public static func makeMusicCardPackets(
        title: String,
        album: String = "",
        artist: String,
        isPlaying: Bool,
        nextSeq: () -> UInt8
    ) -> [Data] {
        let hasTrack = !title.isEmpty && title != "Not Playing"
        guard hasTrack else {
            return [
                DashK1GProtocol.buildSingleTLVPacket(type: 0x05, sub: 0x17, payload: [0xAA], seq: nextSeq())
            ]
        }

        let albumBytes = DashK1GProtocol.latin1Bytes(album.isEmpty ? (artist.isEmpty ? "Music" : artist) : album, maxLength: 19)
        let titleBytes = DashK1GProtocol.latin1Bytes(title, maxLength: 19)
        let artistBytes = DashK1GProtocol.latin1Bytes(artist.isEmpty ? "iPhone" : artist, maxLength: 19)

        var nowPlayingPayload: [UInt8] = []
        nowPlayingPayload.append(contentsOf: albumBytes)
        nowPlayingPayload.append(0x00)
        nowPlayingPayload.append(contentsOf: titleBytes)
        nowPlayingPayload.append(0x00)
        nowPlayingPayload.append(contentsOf: artistBytes)

        return [
            DashK1GProtocol.buildSingleTLVPacket(type: 0x05, sub: 0x17, payload: [0x55], seq: nextSeq()),
            DashK1GProtocol.buildSingleTLVPacket(type: 0x05, sub: 0x0D, payload: nowPlayingPayload, seq: nextSeq()),
            DashK1GProtocol.buildSingleTLVPacket(type: 0x05, sub: 0x58, payload: [0xAA], seq: nextSeq()),
            DashK1GProtocol.buildSingleTLVPacket(type: 0x05, sub: 0x19, payload: [isPlaying ? 0x55 : 0xAA], seq: nextSeq())
        ]
    }

    // MARK: - Authentic K1G Call Alert Cards (05 21, 05 4D, and AES-256-CBC Encrypted 05 22)
    /// Builds the exact K1G call notification packets:
    /// - 05 21: CallState (0x0A = Ringing, 0x14 = In-Call, 0x32 = None)
    /// - 05 4D: 0x32 (mandatory trailer after every 05 21)
    /// - 05 22: AES-256-CBC encrypted caller name (Latin-1, max 19 chars + NUL) under session `aesKey`
    public static func makeCallCardPackets(
        callerName: String,
        isRinging: Bool,
        isOngoing: Bool,
        aesKey: Data?,
        nextSeq: () -> UInt8
    ) -> [Data] {
        let stateCode: UInt8 = isRinging ? 0x0A : (isOngoing ? 0x14 : 0x32)
        var packets: [Data] = [
            DashK1GProtocol.buildSingleTLVPacket(type: 0x05, sub: 0x21, payload: [stateCode], seq: nextSeq()),
            DashK1GProtocol.buildSingleTLVPacket(type: 0x05, sub: 0x4D, payload: [0x32], seq: nextSeq())
        ]

        if (isRinging || isOngoing), !callerName.isEmpty, let key = aesKey {
            let plainBytes = DashK1GProtocol.latin1Bytes(callerName, maxLength: 19) + [0x00]
            if let encryptedPayload = DashAuthCrypto.aesEncryptCBC(plaintext: Data(plainBytes), aesKey: key) {
                packets.append(
                    DashK1GProtocol.buildSingleTLVPacket(
                        type: 0x05,
                        sub: 0x22,
                        payload: [UInt8](encryptedPayload),
                        seq: nextSeq()
                    )
                )
            }
        }
        return packets
    }

    // Build Navigation Maneuver TLV Packet
    public static func makeManeuverPacket(
        iconCode: UInt8,
        distanceMeters: UInt32,
        totalMeters: UInt32 = 0,
        streetName: String,
        nextIconCode: UInt8 = 0xFF,
        seq: UInt8 = 0
    ) -> Data {
        let total = totalMeters > 0 ? Int(totalMeters) : Int(distanceMeters)
        return DashK1GProtocol.buildActiveNavPacket(
            maneuver: iconCode,
            nextMeters: Int(distanceMeters),
            totalMeters: total,
            roadName: streetName,
            nextManeuver: nextIconCode,
            seq: seq
        )
    }
}
