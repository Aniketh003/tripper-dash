import Foundation
import CoreLocation
import MapKit

public final class RouteService: Sendable {
    public static let shared = RouteService()
    
    private init() {}
    
    // MARK: - Location URL / Query Parser
    public func parseDestination(from input: String) -> CLLocationCoordinate2D? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Raw comma separated: "12.9716, 77.5946"
        let parts = trimmed.components(separatedBy: ",")
        if parts.count == 2,
           let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
           let lng = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        
        // 2. geo: URI: "geo:12.9716,77.5946?q=..."
        if trimmed.hasPrefix("geo:") {
            let stripped = trimmed.replacingOccurrences(of: "geo:", with: "")
            let coordPart = stripped.components(separatedBy: "?").first ?? ""
            let subParts = coordPart.components(separatedBy: ",")
            if subParts.count >= 2,
               let lat = Double(subParts[0]),
               let lng = Double(subParts[1]) {
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
        }
        
        // 3. Google Maps URL patterns: /@12.9716,77.5946 or ?q=12.9716,77.5946
        if trimmed.contains("google.com/maps") || trimmed.contains("maps.app.goo.gl") {
            if let range = trimmed.range(of: "@") {
                let sub = trimmed[range.upperBound...]
                let subParts = sub.components(separatedBy: ",")
                if subParts.count >= 2,
                   let lat = Double(subParts[0]),
                   let lng = Double(subParts[1]) {
                    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Native Apple MapKit Directions Route Calculator
    public func calculateRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String = "Destination"
    ) async throws -> DashRouteInfo {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile
        request.requestsAlternateRoutes = false
        
        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        
        guard let primaryRoute = response.routes.first else {
            throw NSError(domain: "RouteService", code: 404, userInfo: [NSLocalizedDescriptionKey: "No route found"])
        }
        
        // Extract route polyline coordinates
        var coordinates = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: primaryRoute.polyline.pointCount)
        primaryRoute.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: primaryRoute.polyline.pointCount))
        let encodedPolyline = PolylineEncoder.encode(coordinates: coordinates)
        
        // Extract maneuvers
        var steps: [RouteStep] = []
        for step in primaryRoute.steps {
            // Skip trivial step instructions
            if step.distance > 0 && !step.instructions.isEmpty {
                let maneuver = mapMKInstructionsToManeuver(step.instructions)
                steps.append(RouteStep(
                    instruction: step.instructions,
                    distanceMeters: step.distance,
                    maneuver: maneuver,
                    streetName: step.notice ?? ""
                ))
            }
        }
        
        return DashRouteInfo(
            destinationName: destinationName,
            totalDistanceMeters: primaryRoute.distance,
            totalDurationSeconds: Int(primaryRoute.expectedTravelTime),
            encodedPolyline: encodedPolyline,
            steps: steps
        )
    }
    
    private func mapMKInstructionsToManeuver(_ instruction: String) -> ManeuverType {
        let lower = instruction.lowercased()
        if lower.contains("slight left") { return .turnSlightLeft }
        if lower.contains("sharp left") { return .turnSharpLeft }
        if lower.contains("left") { return .turnLeft }
        if lower.contains("slight right") { return .turnSlightRight }
        if lower.contains("sharp right") { return .turnSharpRight }
        if lower.contains("right") { return .turnRight }
        if lower.contains("u-turn") || lower.contains("uturn") { return .uTurn }
        if lower.contains("roundabout") || lower.contains("rotary") { return .roundabout }
        if lower.contains("arrive") || lower.contains("destination") { return .destination }
        return .straight
    }
}
