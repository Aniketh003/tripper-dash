import Foundation

public enum DashK1GProtocol {
    // Network Ports
    public static let bikeListenPort: UInt16  = 2000  // Bike receives control messages on 2000
    public static let phoneListenPort: UInt16 = 2002  // Phone receives dash segments on 2002
    public static let bikeVideoPort: UInt16   = 5000  // RTP H.264 video stream
    public static let bikeDefaultIP           = "192.168.1.1"
    public static let bikeBroadcastIP         = "192.168.1.255"

    // K1G Control Hex Strings
    public static let q3c_e_request_auth = "0016000200000000020100054B314720000804000101"
    public static let q3c_d_prefix_hex   = "0095000200000000020100054B3147200008000080"
    public static let q3c_z2_start_nav   = "0016000200000000020100054B31472000068000010B"
    public static let q3c_nav_placeholder = "0017000200000000020100054B31472000060A00020000"
    public static let q3c_w_proj_on      = "0016000200000000020100054B314720000605000155"
    public static let q3c_g_proj_frame   = "0016000200000000020100054B314720000556000155"
    public static let q3c_h_proj_stop    = "0016000200000000020100054B3147200005560001AA"
    public static let q3c_x_proj_off     = "0016000200000000020100054B3147200006050001AA"
    public static let q3c_q_nav_ctx      = "0016000200000000020100054B31472000052E00011E"
    public static let q3c_r_empty_lists  = "002A000600000000020100054B31472000052F0001000530000100053100010005320001000533000100"
    public static let q3c_l2             = "0016000200000000020100054B314720000611000155"
    public static let q3c_k2             = "0016000200000000020100054B314720000612000155"
    public static let q3c_zoom_icons     = "0016000200000000020100054B31472000060C000130"
    public static let buttonAckPrefix    = "0016000200000000020100054B3147200006800001"

    // Maneuver codes
    public static let navManeuverContinue: UInt8 = 0x09
    public static let navManeuverArrivalPin: UInt8 = 0x3C
    public static let navManeuverHidden: UInt8 = 0xFF // Hides turn-by-turn bubble completely

    // MARK: - Packet Helpers
    public static func patchSequence(data: Data, seq: UInt8) -> Data {
        var bytes = [UInt8](data)
        guard bytes.count >= 4 else { return data }
        for i in 0..<(bytes.count - 4) {
            if bytes[i] == 0x4B && bytes[i+1] == 0x31 && bytes[i+2] == 0x47 && bytes[i+3] == 0x20 {
                if i + 4 < bytes.count {
                    bytes[i + 4] = seq
                }
                break
            }
        }
        let count = UInt16(bytes.count)
        bytes[0] = UInt8(count >> 8)
        bytes[1] = UInt8(count & 0xFF)
        return Data(bytes)
    }

    /// Build a single-TLV K1G packet: [len:2][segCount=0x0002][0000000002010005]"K1G "[seq][type][sub][len:2][value]
    public static func buildSingleTLVPacket(type: UInt8, sub: UInt8, payload: [UInt8], seq: UInt8) -> Data {
        var body: [UInt8] = [
            0x00, 0x00,
            0x00, 0x02,
            0x00, 0x00, 0x00, 0x00, 0x02, 0x01, 0x00, 0x05,
            0x4B, 0x31, 0x47, 0x20,
            seq,
            type, sub,
            UInt8((payload.count >> 8) & 0xFF),
            UInt8(payload.count & 0xFF)
        ]
        body.append(contentsOf: payload)
        let count = UInt16(body.count)
        body[0] = UInt8(count >> 8)
        body[1] = UInt8(count & 0xFF)
        return Data(body)
    }

    /// Converts Unicode string into clean Latin-1 bytes (replacing typographic quotes/dashes with ASCII)
    public static func latin1Bytes(_ text: String, maxLength: Int) -> [UInt8] {
        let normalized = text
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2026}", with: "...")
            .replacingOccurrences(of: "·", with: "-")
            .replacingOccurrences(of: "♪", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var out: [UInt8] = []
        for scalar in normalized.unicodeScalars {
            if out.count >= maxLength { break }
            if scalar.value < 0x100 && scalar.value >= 0x20 {
                out.append(UInt8(scalar.value))
            } else if scalar.value >= 0x100 {
                out.append(UInt8(ascii: "?"))
            }
        }
        return out
    }

    /// 06 06 — Real-time Time-of-Day clock sync (hour, minute, second).
    /// Replaces the old hardcoded capture time (14:51:52) so the TFT clock is always accurate.
    public static func buildTimeSyncPacket(seq: UInt8) -> Data {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        let h = UInt8(comps.hour ?? 12)
        let m = UInt8(comps.minute ?? 0)
        let s = UInt8(comps.second ?? 0)
        return buildSingleTLVPacket(type: 0x06, sub: 0x06, payload: [h, m, s], seq: seq)
    }

    public static func buildHostnameAnnounce(hostname: String, seq: UInt8) -> Data {
        let nameBytes = latin1Bytes(hostname, maxLength: 32)
        var body = [UInt8](DashAuthCrypto.hexToData("0021000200000000020100054b314720") ?? Data())
        body.append(seq)
        body.append(contentsOf: [0x06, 0x0B, 0x00, UInt8(nameBytes.count + 1)])
        body.append(contentsOf: nameBytes)
        body.append(0x00) // Null terminator
        
        let count = UInt16(body.count)
        body[0] = UInt8(count >> 8)
        body[1] = UInt8(count & 0xFF)
        return Data(body)
    }

    /// Generates the initial announcement burst with real-time clock, real phone battery, and real weather
    public static func buildInitialBurstPackets(
        hostname: String,
        batteryPct: Int,
        charging: Bool,
        weatherIcon: UInt8,
        tempC: Int?,
        volumePercent: Int,
        nextSeq: () -> UInt8
    ) -> [Data] {
        var list: [Data] = []
        if let authReq = DashAuthCrypto.hexToData(q3c_e_request_auth) {
            list.append(patchSequence(data: authReq, seq: nextSeq()))
        }
        list.append(buildHostnameAnnounce(hostname: hostname, seq: nextSeq()))
        list.append(buildTimeSyncPacket(seq: nextSeq()))
        
        let staticBurstHex = [
            "0016000200000000020100054b314720030557000155",
            "0016000200000000020100054b3147200405560001aa",
            "0016000200000000020100054b3147200506050001aa",
            "0016000200000000020100054b3147200605170001aa",
            "001d000200000000020100054b314720080a020008aa55000000000000"
        ]
        for hex in staticBurstHex {
            if let raw = DashAuthCrypto.hexToData(hex) {
                list.append(patchSequence(data: raw, seq: nextSeq()))
            }
        }
        // Final packet of burst: real phone status (no fake 62% battery or fake 25°C!)
        let hb = K1GPacket.makeHeartbeatPacket(
            batteryPct: batteryPct,
            charging: charging,
            gpsOn: true,
            weatherIcon: weatherIcon,
            tempC: tempC,
            volumePercent: volumePercent,
            callStatusCode: 0x32
        )
        list.append(patchSequence(data: hb, seq: nextSeq()))
        return list
    }

    public static func buildQ3CDPacket(ciphertext: Data, seq: UInt8) -> Data {
        var data = DashAuthCrypto.hexToData(q3c_d_prefix_hex) ?? Data()
        data.append(ciphertext)
        return patchSequence(data: data, seq: seq)
    }
    
    /// Handlebar joystick button echo ack (06 80 00 01 XX)
    public static func buildButtonAck(buttonByte: UInt8, seq: UInt8) -> Data {
        let hex = buttonAckPrefix + String(format: "%02X", buttonByte)
        let raw = DashAuthCrypto.hexToData(hex) ?? Data()
        return patchSequence(data: raw, seq: seq)
    }

    private static func currentClockHHMM() -> [UInt8] {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "HHmm"
        let str = fmt.string(from: Date())
        let bytes = Array(str.utf8)
        return bytes.count == 4 ? bytes : [0x31, 0x32, 0x30, 0x30]
    }

    /// 0x007E Route Card packet:
    /// - When `isNavigating == false` (Idle / Digital Homescreen):
    ///   Hides the turn-by-turn navigation bubble (`05 02 = 0xFF`, `05 03 = 0xFF`), replaces mocked "0303"
    ///   with real `HHmm` clock, and strips mocked distance (`05 05`, `05 09`, `05 46`) and mocked duration (`05 0B`, `05 55`)!
    /// - When `isNavigating == true`:
    ///   Populates real maneuver icon, real distance, and real clock/ETA.
    public static func buildRouteCardPacket(
        title: String,
        seq: UInt8,
        projectionOn: Bool,
        isNavigating: Bool = false,
        maneuver: UInt8 = navManeuverHidden,
        totalDistanceMeters: Int = 0
    ) -> Data {
        let cleanTitle = title.isEmpty ? "TripperDash" : title
        let titleBytes = latin1Bytes(cleanTitle, maxLength: 58) + [0x00]
        let clockBytes = currentClockHHMM()
        let activeManeuver: UInt8 = isNavigating ? maneuver : navManeuverHidden

        var tlvs: [[UInt8]] = []

        // 1. 05 01: Title / Street Name
        var t0501: [UInt8] = [0x05, 0x01, UInt8((titleBytes.count >> 8) & 0xFF), UInt8(titleBytes.count & 0xFF)]
        t0501.append(contentsOf: titleBytes)
        tlvs.append(t0501)

        // 2. 05 02: Primary Maneuver (0xFF hides the turn-by-turn bubble when not navigating!)
        tlvs.append([0x05, 0x02, 0x00, 0x01, activeManeuver])

        // 3. 05 03: Secondary Maneuver (0xFF = none)
        tlvs.append([0x05, 0x03, 0x00, 0x01, 0xFF])

        // 4. 05 06 & 05 07: Primary & Secondary Units (0x30 = meters)
        tlvs.append([0x05, 0x06, 0x00, 0x01, 0x30])
        tlvs.append([0x05, 0x07, 0x00, 0x01, 0x30])

        // 5. 05 08 & 05 54: Real Clock / ETA HHMM (4 ASCII digits)
        tlvs.append([0x05, 0x08, 0x00, 0x04, clockBytes[0], clockBytes[1], clockBytes[2], clockBytes[3]])
        tlvs.append([0x05, 0x54, 0x00, 0x01, 0x30])

        // 6. Only include Total Distance (05 09 + 05 46) when actually navigating!
        if isNavigating && totalDistanceMeters > 0 {
            let clamped = UInt16(min(65535, max(0, totalDistanceMeters)))
            tlvs.append([0x05, 0x09, 0x00, 0x02, UInt8(clamped >> 8), UInt8(clamped & 0xFF)])
            tlvs.append([0x05, 0x46, 0x00, 0x01, 0x30]) // 0x30 = meters
        }

        // 7. 05 0A: Decimal separator (0x55 = dot)
        tlvs.append([0x05, 0x0A, 0x00, 0x01, 0x55])

        // 8. 05 0C: Proximity bar
        tlvs.append([0x05, 0x0C, 0x00, 0x01, 0x04])

        // 9. 06 05: Projection Flag (0x55 = ON, 0xAA = OFF)
        tlvs.append([0x06, 0x05, 0x00, 0x01, projectionOn ? 0x55 : 0xAA])

        // 10. 06 0D: Decimal formatting off (0xAA)
        tlvs.append([0x06, 0x0D, 0x00, 0x01, 0xAA])

        let segCount = UInt16(tlvs.count + 1)
        var body: [UInt8] = [
            0x00, 0x00,
            UInt8(segCount >> 8), UInt8(segCount & 0xFF),
            0x00, 0x00, 0x00, 0x00, 0x02, 0x01, 0x00, 0x05,
            0x4B, 0x31, 0x47, 0x20,
            seq
        ]
        for t in tlvs {
            body.append(contentsOf: t)
        }
        let totalLen = UInt16(body.count)
        body[0] = UInt8(totalLen >> 8)
        body[1] = UInt8(totalLen & 0xFF)
        return Data(body)
    }

    /// Active Navigation Instruction Packet (only sent when `isNavigationActive == true`)
    public static func buildActiveNavPacket(
        maneuver: UInt8 = navManeuverContinue,
        nextMeters: Int,
        totalMeters: Int,
        roadName: String = "",
        seq: UInt8
    ) -> Data {
        var tlvs = ""
        var segCount = 1

        let roadBytes = latin1Bytes(roadName, maxLength: 19)
        if !roadBytes.isEmpty {
            let nullTerm = roadBytes + [0x00]
            let hexRoad = nullTerm.map { String(format: "%02X", $0) }.joined()
            tlvs += String(format: "0501%04X", nullTerm.count) + hexRoad
            segCount += 1
        }

        // Primary maneuver (05 02 0001 XX)
        tlvs += String(format: "05020001%02X", maneuver)
        segCount += 1

        // Primary distance in meters (05 04 0002 XXXX)
        tlvs += String(format: "05040002%04X", min(65535, max(0, nextMeters)))
        segCount += 1

        // Primary unit: 30 = meters (05 06 0001 30)
        tlvs += "0506000130"
        segCount += 1

        if totalMeters > 0 {
            tlvs += String(format: "05090002%04X", min(65535, max(0, totalMeters)))
            tlvs += "0546000130"
            segCount += 2
        }

        // Decimal separator: 55 = dot (05 0A 0001 55)
        tlvs += "050A000155"
        // Projection flag: 55 = on (06 05 0001 55)
        tlvs += "0605000155"
        // Decimal format: AA = off (06 0D 0001 AA)
        tlvs += "060D0001AA"
        segCount += 3
        
        let hdr = String(format: "0000%04X00000000020100054B31472000", segCount)
        let fullHex = hdr + tlvs
        var data = DashAuthCrypto.hexToData(fullHex) ?? Data()
        data = patchSequence(data: data, seq: seq)
        return data
    }

    // MARK: - Inbound Segment Parser from Dash (0x07 for Auth, 0x09 for Buttons)
    public struct K1GSegment {
        public let type: UInt8
        public let sub: UInt8
        public let payload: Data
        public let hexString: String
    }
    
    public static func decodeSegments(data: Data) -> [K1GSegment] {
        var segments: [K1GSegment] = []
        guard data.count >= 8 else { return segments }
        
        let segCount = (Int(data[2]) << 8) | Int(data[3])
        var offset = 8
        
        for _ in 0..<segCount {
            if offset + 4 > data.count { break }
            let t = data[offset]
            let sub = data[offset + 1]
            let segLen = (Int(data[offset + 2]) << 8) | Int(data[offset + 3])
            offset += 4
            
            let payload: Data
            if offset + segLen > data.count {
                payload = data.subdata(in: offset..<data.count)
                offset = data.count
            } else {
                payload = data.subdata(in: offset..<(offset + segLen))
                offset += segLen
            }
            
            var segHex = String(format: "%02X%02X%04X", t, sub, segLen)
            segHex += payload.map { String(format: "%02X", $0) }.joined()
            segments.append(K1GSegment(type: t, sub: sub, payload: payload, hexString: segHex))
        }
        
        return segments
    }
}
