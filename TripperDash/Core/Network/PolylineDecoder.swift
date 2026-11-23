import Foundation
import CoreLocation

public enum PolylineEncoder {
    public static func encode(coordinates: [CLLocationCoordinate2D]) -> String {
        var result = ""
        var lastLat = 0
        var lastLng = 0
        
        for coord in coordinates {
            let lat = Int(round(coord.latitude * 1e5))
            let lng = Int(round(coord.longitude * 1e5))
            
            encodeDifference(lat - lastLat, into: &result)
            encodeDifference(lng - lastLng, into: &result)
            
            lastLat = lat
            lastLng = lng
        }
        
        return result
    }
    
    public static func decode(polyline: String) -> [CLLocationCoordinate2D] {
        var coordinates: [CLLocationCoordinate2D] = []
        var index = polyline.startIndex
        var lat = 0
        var lng = 0
        
        while index < polyline.endIndex {
            guard let deltaLat = decodeDifference(from: polyline, index: &index),
                  let deltaLng = decodeDifference(from: polyline, index: &index) else {
                break
            }
            
            lat += deltaLat
            lng += deltaLng
            
            coordinates.append(CLLocationCoordinate2D(
                latitude: Double(lat) / 1e5,
                longitude: Double(lng) / 1e5
            ))
        }
        
        return coordinates
    }
    
    private static func encodeDifference(_ value: Int, into string: inout String) {
        var v = value < 0 ? ~(value << 1) : (value << 1)
        while v >= 0x20 {
            let scalar = UnicodeScalar((0x20 | (v & 0x1f)) + 63)!
            string.append(Character(scalar))
            v >>= 5
        }
        let scalar = UnicodeScalar(v + 63)!
        string.append(Character(scalar))
    }
    
    private static func decodeDifference(from string: String, index: inout String.Index) -> Int? {
        var shift = 0
        var result = 0
        
        while index < string.endIndex {
            let char = string[index]
            string.formIndex(after: &index)
            
            guard let ascii = char.asciiValue else { return nil }
            let val = Int(ascii) - 63
            result |= (val & 0x1f) << shift
            shift += 5
            
            if val < 0x20 {
                return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            }
        }
        
        return nil
    }
}
