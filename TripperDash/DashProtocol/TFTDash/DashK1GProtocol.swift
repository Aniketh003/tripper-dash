import Foundation

public enum DashK1GProtocol {
    public static let q3c_e_request_auth = "0016000200000000020100054B314720000804000101"
    public static let q3c_d_prefix_hex   = "0095000200000000020100054B3147200008000080"
    public static let q3c_z2_start_nav   = "0016000200000000020100054B31472000068000010B"
    public static let q3c_w_proj_on      = "0016000200000000020100054B314720000605000155"
    public static let q3c_q_nav_ctx      = "0016000200000000020100054B31472000052E00011E"
    public static let q3c_r_empty_lists  = "002A000600000000020100054B31472000052F0001000530000100053100010005320001000533000100"
    public static let q3c_l2             = "0016000200000000020100054B314720000611000155"
    
    public static let initialBurstHex: [String?] = [
        q3c_e_request_auth,
        nil, // Hostname announce
        "0018000200000000020100054b31472002060600030e3334",
        "0016000200000000020100054b314720030557000155",
        "0016000200000000020100054b3147200405560001aa",
        "0016000200000000020100054b3147200506050001aa",
        "0016000200000000020100054b3147200605170001aa",
        "001d000200000000020100054b314720080a020008aa55000000000000",
        "0044000a00000000020100054b3147200906080001ff060300015506040001a2060f0001aa0601000101054c000113052d00020000051b0001190521000132054d000132"
    ]
    
    public static func patchSequence(data: Data, seq: UInt8) -> Data {
        var bytes = [UInt8](data)
        // Find "K1G " marker: 0x4B, 0x31, 0x47, 0x20
        for i in 0..<(bytes.count - 4) {
            if bytes[i] == 0x4B && bytes[i+1] == 0x31 && bytes[i+2] == 0x47 && bytes[i+3] == 0x20 {
                if i + 4 < bytes.count {
                    bytes[i + 4] = seq
                }
                break
            }
        }
        // Patch 2-byte outer length Big Endian
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
    
    // Inbound Segment Parser from Dash (0x07 for Auth, 0x09 for Buttons)
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
