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
    public static let q3c_w_proj_on      = "0016000200000000020100054B314720000605000155"
    public static let q3c_g_proj_frame   = "0016000200000000020100054B314720000556000155"
    public static let q3c_h_proj_stop    = "0016000200000000020100054B3147200005560001AA"
    public static let q3c_x_proj_off     = "0016000200000000020100054B3147200006050001AA"
    public static let q3c_q_nav_ctx      = "0016000200000000020100054B31472000052E00011E"
    public static let q3c_r_empty_lists  = "002A000600000000020100054B31472000052F0001000530000100053100010005320001000533000100"
    public static let q3c_l2             = "0016000200000000020100054B314720000611000155"
    public static let buttonAckPrefix    = "0016000200000000020100054B3147200006800001"
    
    // Initial Announcement Burst sent to dash at connection start
    public static let initialBurstHex: [String?] = [
        q3c_e_request_auth,
        nil, // Hostname announce ("iPhone")
        "0018000200000000020100054b31472002060600030e3334",
        "0016000200000000020100054b314720030557000155",
        "0016000200000000020100054b3147200405560001aa",
        "0016000200000000020100054b3147200506050001aa",
        "0016000200000000020100054b3147200605170001aa",
        "001d000200000000020100054b314720080a020008aa55000000000000",
        "0044000a00000000020100054b3147200906080001ff060300015506040001a2060f0001aa0601000101054c000113052d00020000051b0001190521000132054d000132"
    ]
    
    // MARK: - Packet Helpers
    public static func patchSequence(data: Data, seq: UInt8) -> Data {
        var bytes = [UInt8](data)
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
    
    public static func buildHostnameAnnounce(hostname: String, seq: UInt8) -> Data {
        let nameBytes = Array(hostname.prefix(32).utf8)
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
    
    /// 0x007E Route Card packet: Sets destination title and gates navigation surface
    public static func buildRouteCardPacket(title: String, seq: UInt8, projectionOn: Bool) -> Data {
        let titleBytes = Array(title.prefix(40).utf8) + [0x00]
        var body = [UInt8](DashAuthCrypto.hexToData("007e001100000000020100054b314720") ?? Data())
        body.append(seq)
        body.append(contentsOf: [0x05, 0x01, UInt8(titleBytes.count >> 8), UInt8(titleBytes.count & 0xFF)])
        body.append(contentsOf: titleBytes)
        
        // Append navigation template suffix (parameters for turn display)
        let suffixHex = "050200013c050300013405050002000a050600013005070001300508000430333033055400013005090002004f0546000110050a000155050c000104050b0006303031303030055500012006050001" + (projectionOn ? "55" : "aa") + "060d0001aa"
        if let suffixData = DashAuthCrypto.hexToData(suffixHex) {
            body.append(contentsOf: suffixData)
        }
        
        let count = UInt16(body.count)
        body[0] = UInt8(count >> 8)
        body[1] = UInt8(count & 0xFF)
        return Data(body)
    }

    /// Active Navigation Instruction Packet (Turn Maneuver, Next Turn Distance, Total Distance)
    public static func buildActiveNavPacket(maneuver: UInt8 = 0x0B, nextMeters: Int = 500, totalMeters: Int = 1200, seq: UInt8) -> Data {
        var tlvs = ""
        // Primary maneuver (05 02 0001 XX)
        tlvs += String(format: "05020001%02X", maneuver)
        // Primary distance in meters (05 04 0002 XXXX)
        tlvs += String(format: "05040002%04X", min(65535, max(0, nextMeters)))
        // Primary unit: 30 = meters (05 06 0001 30)
        tlvs += "0506000130"
        // Total distance (05 09 0002 XXXX)
        tlvs += String(format: "05090002%04X", min(65535, max(0, totalMeters)))
        // Total unit: 30 = meters (05 46 0001 30)
        tlvs += "0546000130"
        // Decimal separator: 55 = dot (05 0A 0001 55)
        tlvs += "050A000155"
        // Projection flag: 55 = on (06 05 0001 55)
        tlvs += "0605000155"
        // Decimal format: AA = off (06 0D 0001 AA)
        tlvs += "060D0001AA"
        
        let segCount = 8 + 1 // TLVs + 1
        let hdr = String(format: "%04X00000000020100054B31472000", segCount)
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
