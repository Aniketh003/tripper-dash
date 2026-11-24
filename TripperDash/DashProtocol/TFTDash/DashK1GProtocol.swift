import Foundation

public enum DashK1GProtocol {
    // Network Ports
    public static let bikeListenPort: UInt16  = 2000  // Bike receives control messages on 2000
    public static let phoneListenPort: UInt16 = 2002  // Phone receives dash segments on 2002
    public static let bikeVideoPort: UInt16   = 5000  // RTP H.264 video stream
    public static let bikeDefaultIP           = "192.168.1.1"
    public static let bikeBroadcastIP         = "192.168.1.255"

    // K1G Control Hex Strings
    public static let q3c_e_request_auth  = "0016000200000000020100054B314720000804000101"
    public static let q3c_d_prefix_hex    = "0095000200000000020100054B3147200008000080"
    public static let q3c_z2_start_nav    = "0016000200000000020100054B31472000068000010B"
    public static let q3c_nav_placeholder = "0017000200000000020100054B31472000060A00020000"
    public static let q3c_w_proj_on       = "0016000200000000020100054B314720000605000155"
    public static let q3c_g_proj_frame    = "0016000200000000020100054B314720000556000155"
    public static let q3c_h_proj_stop     = "0016000200000000020100054B3147200005560001AA"
    public static let q3c_x_proj_off      = "0016000200000000020100054B3147200006050001AA"
    public static let q3c_q_nav_ctx       = "0016000200000000020100054B31472000052E00011E"
    public static let q3c_r_empty_lists   = "002A000600000000020100054B31472000052F0001000530000100053100010005320001000533000100"
    public static let q3c_l2              = "0016000200000000020100054B314720000611000155"
    public static let q3c_k2              = "0016000200000000020100054B314720000612000155"
    public static let q3c_zoom_icons      = "0016000200000000020100054B31472000060C000130"
    public static let buttonAckPrefix     = "0016000200000000020100054B3147200006800001"

    // Maneuver codes
    public static let navManeuverArrive: UInt8      = 0x00
    public static let navManeuverContinue: UInt8    = 0x09
    public static let navManeuverTurnLeft: UInt8    = 0x14
    public static let navManeuverTurnRight: UInt8   = 0x15
    public static let navManeuverSharpLeft: UInt8   = 0x16
    public static let navManeuverSharpRight: UInt8  = 0x17
    public static let navManeuverSlightLeft: UInt8  = 0x18
    public static let navManeuverSlightRight: UInt8 = 0x19
    public static let navManeuverUTurnRight: UInt8  = 0x1A
    public static let navManeuverUTurnLeft: UInt8   = 0x1B
    public static let navManeuverRoundabout: UInt8  = 0x32
    public static let navManeuverArrivalPin: UInt8  = 0x3C
    public static let navManeuverHidden: UInt8      = 0xFF // Hides turn-by-turn bubble when idle

    // Distance units
    public static let navUnitKmTenths: UInt8 = 0x10 // value = km * 10 (e.g. 24 -> "2.4 km")
    public static let navUnitMeters: UInt8   = 0x30 // value = plain meters (e.g. 350 -> "350 m")

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
        body.append(0x00)
        
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

    // MARK: - Authentic Navigation Unit & Proximity Math (Matches Official RE App)

    /// Encodes distance in meters into (onWireValue, unitByte):
    /// - `< 1000 m`: plain meters (`0x30`, e.g. `450` -> `"450 m"`)
    /// - `>= 1000 m`: tenths of a kilometer (`0x10`, e.g. `2400 m` -> `24` -> `"2.4 km"`)
    public static func encodeDistanceAndUnit(meters: Int) -> (value: UInt16, unit: UInt8) {
        let clamped = max(0, meters)
        if clamped < 1000 {
            return (UInt16(clamped), navUnitMeters)
        } else {
            let tenthsKm = min(65535, max(10, Int(round(Double(clamped) / 100.0))))
            return (UInt16(tenthsKm), navUnitKmTenths)
        }
    }

    /// Computes the proximity bar level (`05 0C`, 0..6) drawn beside the turn glyph on the TFT:
    /// 4 up to 20 m, 3 to 40 m, 2 to 60 m, 1 to 80 m, 0 to 100 m (fills as turn approaches), 6 up to 500 m, 5 beyond.
    public static func proximityLevel(meters: Int) -> UInt8 {
        if meters <= 20 { return 4 }
        if meters <= 100 { return UInt8(max(0, 3 - (meters - 21) / 20)) }
        if meters <= 500 { return 6 }
        return 5
    }

    /// Encodes remaining trip seconds as 6 ASCII digits (`HHMMDD`) + unit byte (`0x30` days, `0x10` hours, `0x20` mins)
    public static func encodeRemainingTime(seconds: Int) -> (asciiBytes: [UInt8], unit: UInt8) {
        let clamped = max(0, seconds)
        let days = min(99, clamped / 86_400)
        let hours = (clamped % 86_400) / 3_600
        let minutes = max(1, (clamped % 3_600) / 60)
        let unit: UInt8 = days > 0 ? 0x30 : (hours >= 1 ? 0x10 : 0x20)
        let text = String(format: "%02d%02d%02d", hours, minutes, days)
        return (Array(text.utf8), unit)
    }

    private static func formatClockHHMM(date: Date = Date()) -> [UInt8] {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "HHmm"
        let str = fmt.string(from: date)
        let bytes = Array(str.utf8)
        return bytes.count == 4 ? bytes : [0x31, 0x32, 0x30, 0x30]
    }

    /// 0x007E Route Card packet:
    /// - When `isNavigating == true`:
    ///   Populates real maneuver glyph, real primary unit, real total distance & unit, real arrival ETA `HHmm`,
    ///   real remaining duration `HHMMDD`, and real proximity bar (`05 0C`)!
    /// - When `isCallActive == true` (Incoming or Ongoing Call):
    ///   Enables the overlay ring (`maneuver = 0x3C` if not navigating) so the dash forwards call joystick presses!
    /// - When idle (`isNavigating == false && isCallActive == false`):
    ///   Hides the turn-by-turn bubble (`05 02 = 0xFF`) and omits distance/remaining time fields.
    public static func buildRouteCardPacket(
        title: String,
        seq: UInt8,
        projectionOn: Bool,
        isNavigating: Bool = false,
        isCallActive: Bool = false,
        maneuver: UInt8 = navManeuverHidden,
        nextTurnMeters: Int = 0,
        totalDistanceMeters: Int = 0,
        remainingSeconds: Int = 0,
        remainingTimeSeconds: Int = 0,
        arrivalDate: Date? = nil,
        nextManeuver: UInt8 = 0xFF
    ) -> Data {
        let cleanTitle = title.isEmpty ? "TripperDash" : title
        let titleBytes = latin1Bytes(cleanTitle, maxLength: 58) + [0x00]

        let effRemSeconds = remainingSeconds > 0 ? remainingSeconds : remainingTimeSeconds
        let etaDate = arrivalDate ?? ((isNavigating && effRemSeconds > 0) ? Date().addingTimeInterval(TimeInterval(effRemSeconds)) : Date())
        let clockBytes = formatClockHHMM(date: etaDate)

        // Keep maneuver hidden (0xFF) whenever not actively navigating so the stock TFT banner never covers our H.264 stream
        let activeManeuver: UInt8
        if isNavigating {
            activeManeuver = (maneuver == navManeuverHidden) ? navManeuverContinue : maneuver
        } else {
            activeManeuver = navManeuverHidden
        }

        let primaryEncoded = encodeDistanceAndUnit(meters: nextTurnMeters)
        let prox = isNavigating ? proximityLevel(meters: nextTurnMeters) : 0x04
        let shownNextManeuver: UInt8 = (isNavigating && prox < 5) ? nextManeuver : 0xFF

        var tlvs: [[UInt8]] = []

        // 1. 05 01: Title / Street Name
        var t0501: [UInt8] = [0x05, 0x01, UInt8((titleBytes.count >> 8) & 0xFF), UInt8(titleBytes.count & 0xFF)]
        t0501.append(contentsOf: titleBytes)
        tlvs.append(t0501)

        // 2. 05 02: Primary Maneuver
        tlvs.append([0x05, 0x02, 0x00, 0x01, activeManeuver])

        // 3. 05 03: Secondary Maneuver (shown when within 100m of turn, else 0xFF)
        tlvs.append([0x05, 0x03, 0x00, 0x01, shownNextManeuver])

        // 4. 05 06 & 05 07: Primary & Secondary Units
        tlvs.append([0x05, 0x06, 0x00, 0x01, isNavigating ? primaryEncoded.unit : 0x30])
        tlvs.append([0x05, 0x07, 0x00, 0x01, 0x30])

        // 5. 05 08 & 05 54: Real Clock or Real Arrival ETA HHMM (4 ASCII digits)
        tlvs.append([0x05, 0x08, 0x00, 0x04, clockBytes[0], clockBytes[1], clockBytes[2], clockBytes[3]])
        tlvs.append([0x05, 0x54, 0x00, 0x01, 0x30])

        // 6. Total Remaining Distance (05 09 + 05 46) when actively navigating
        if isNavigating && totalDistanceMeters > 0 {
            let totalEncoded = encodeDistanceAndUnit(meters: totalDistanceMeters)
            tlvs.append([0x05, 0x09, 0x00, 0x02, UInt8(totalEncoded.value >> 8), UInt8(totalEncoded.value & 0xFF)])
            tlvs.append([0x05, 0x46, 0x00, 0x01, totalEncoded.unit])
        }

        // 7. 05 0A: Decimal separator (0x55 = dot)
        tlvs.append([0x05, 0x0A, 0x00, 0x01, 0x55])

        // 8. 05 0C: Proximity countdown bar (0..6)
        tlvs.append([0x05, 0x0C, 0x00, 0x01, prox])

        // 9. Remaining Trip Time (05 0B + 05 55) when actively navigating
        if isNavigating && effRemSeconds > 0 {
            let rem = encodeRemainingTime(seconds: effRemSeconds)
            if rem.asciiBytes.count == 6 {
                var t050B: [UInt8] = [0x05, 0x0B, 0x00, 0x06]
                t050B.append(contentsOf: rem.asciiBytes)
                tlvs.append(t050B)
                tlvs.append([0x05, 0x55, 0x00, 0x01, rem.unit])
            }
        }

        // 10. 06 05: Projection Flag (0x55 = ON, 0xAA = OFF)
        tlvs.append([0x06, 0x05, 0x00, 0x01, projectionOn ? 0x55 : 0xAA])

        // 11. 06 0D: Decimal formatting off (0xAA)
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

    /// Active Navigation Instruction Packet (sent at 1 Hz when `isNavigationActive == true`, matching official RE app)
    public static func buildActiveNavPacket(
        maneuver: UInt8 = navManeuverContinue,
        nextMeters: Int,
        totalMeters: Int,
        roadName: String = "",
        nextManeuver: UInt8 = 0xFF,
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

        // Primary maneuver (05 02 0001 XX) — never send 0xFF while guiding
        let safeManeuver = (maneuver == navManeuverHidden) ? navManeuverContinue : maneuver
        tlvs += String(format: "05020001%02X", safeManeuver)
        segCount += 1

        // Secondary maneuver (05 03 0001 XX)
        let prox = proximityLevel(meters: nextMeters)
        let shownNext: UInt8 = (prox < 5) ? nextManeuver : 0xFF
        tlvs += String(format: "05030001%02X", shownNext)
        segCount += 1

        // Primary distance + unit (05 04 0002 XXXX + 05 06 0001 UU)
        let primaryEncoded = encodeDistanceAndUnit(meters: nextMeters)
        tlvs += String(format: "05040002%04X", primaryEncoded.value)
        tlvs += String(format: "05060001%02X", primaryEncoded.unit)
        segCount += 2

        // Total distance + unit (05 09 0002 XXXX + 05 46 0001 UU)
        if totalMeters > 0 {
            let totalEncoded = encodeDistanceAndUnit(meters: totalMeters)
            tlvs += String(format: "05090002%04X", totalEncoded.value)
            tlvs += String(format: "05460001%02X", totalEncoded.unit)
            segCount += 2
        }

        // Decimal separator: 55 = dot (05 0A 0001 55)
        tlvs += "050A000155"
        // Proximity bar: 0..6 (05 0C 0001 XX)
        tlvs += String(format: "050C0001%02X", prox)
        // Projection flag: 55 = on (06 05 0001 55)
        tlvs += "0605000155"
        // Decimal format: AA = off (06 0D 0001 AA)
        tlvs += "060D0001AA"
        segCount += 4
        
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
