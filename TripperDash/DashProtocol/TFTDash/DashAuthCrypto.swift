import Foundation
import Security

public enum DashAuthCrypto {
    
    /// Encrypts (SSID + 32-byte AES key) using the Dash's RSA-1024 public key and PKCS#1 v1.5 padding.
    public static func encryptSessionKey(
        ssid: String,
        modulusHex: String,
        exponentHex: String,
        aesKey: Data
    ) throws -> Data {
        guard let modData = hexToData(modulusHex),
              let expData = hexToData(exponentHex) else {
            throw NSError(domain: "DashAuthCrypto", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid modulus or exponent hex string"])
        }
        
        // 1. Build PKCS#1 RSAPublicKey DER format:
        // SEQUENCE {
        //    INTEGER modulus
        //    INTEGER publicExponent
        // }
        let derKeyData = buildRSAPublicKeyDER(modulus: modData, exponent: expData)
        
        // 2. Create SecKey from DER
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic
        ]
        
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(derKeyData as CFData, attributes as CFDictionary, &error) else {
            let errDesc = error?.takeRetainedValue().localizedDescription ?? "Unknown SecKey error"
            throw NSError(domain: "DashAuthCrypto", code: 2, userInfo: [NSLocalizedDescriptionKey: "SecKeyCreateWithData failed: \(errDesc)"])
        }
        
        // 3. Assemble Payload: SSID bytes + 32-byte random AES Key
        var payload = Data(ssid.utf8)
        payload.append(aesKey)
        
        // 4. Encrypt using PKCS#1 v1.5 padding
        guard let ciphertext = SecKeyCreateEncryptedData(secKey, .rsaEncryptionPKCS1, payload as CFData, &error) as Data? else {
            let errDesc = error?.takeRetainedValue().localizedDescription ?? "Unknown encryption error"
            throw NSError(domain: "DashAuthCrypto", code: 3, userInfo: [NSLocalizedDescriptionKey: "SecKeyCreateEncryptedData failed: \(errDesc)"])
        }
        
        guard ciphertext.count == 128 else {
            throw NSError(domain: "DashAuthCrypto", code: 4, userInfo: [NSLocalizedDescriptionKey: "Expected 128-byte ciphertext for RSA-1024, got \(ciphertext.count) bytes"])
        }
        
        return ciphertext
    }
    
    // MARK: - ASN.1 DER Builder for RSA Public Key
    private static func buildRSAPublicKeyDER(modulus: Data, exponent: Data) -> Data {
        let modInteger = encodeASN1Integer(modulus)
        let expInteger = encodeASN1Integer(exponent)
        
        var seqPayload = Data()
        seqPayload.append(modInteger)
        seqPayload.append(expInteger)
        
        var result = Data([0x30]) // SEQUENCE Tag
        result.append(encodeASN1Length(seqPayload.count))
        result.append(seqPayload)
        
        return result
    }
    
    private static func encodeASN1Integer(_ data: Data) -> Data {
        var value = [UInt8](data)
        // In DER integer encoding, remove redundant leading zeros
        while value.count > 1 && value[0] == 0 && (value[1] & 0x80) == 0 {
            value.removeFirst()
        }
        // If highest bit is 1, prefix with 0x00 to denote positive signed integer
        if let first = value.first, (first & 0x80) != 0 {
            value.insert(0x00, at: 0)
        }
        var result = Data([0x02]) // INTEGER Tag
        result.append(encodeASN1Length(value.count))
        result.append(contentsOf: value)
        return result
    }
    
    private static func encodeASN1Length(_ length: Int) -> Data {
        if length < 128 {
            return Data([UInt8(length)])
        } else if length < 256 {
            return Data([0x81, UInt8(length)])
        } else {
            return Data([0x82, UInt8(length >> 8), UInt8(length & 0xFF)])
        }
    }
    
    public static func hexToData(_ hex: String) -> Data? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count % 2 != 0 { cleaned = "0" + cleaned }
        
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            if let byte = UInt8(cleaned[index..<nextIndex], radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        return data
    }
}
