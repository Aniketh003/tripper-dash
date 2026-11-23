import Foundation
import CoreLocation
import MapKit

// MARK: - Live Turn-by-Turn Navigation Engine (Streams GPS Progress to Guerrilla 450 TFT)
@Observable
public final class NavigationEngine: @unchecked Sendable {
    public static let shared = NavigationEngine()
    
    public var activeRoute: DashRouteInfo? = nil
    public var currentStepIndex: Int = 0
    public var liveDistanceToNextTurnMeters: Int = 0
    public var isNavigating: Bool = false
    
    private init() {}
    
    public var currentStep: RouteStep? {
        guard let route = activeRoute,
              currentStepIndex >= 0,
              currentStepIndex < route.steps.count else { return nil }
        return route.steps[currentStepIndex]
    }
    
    public func startNavigation(route: DashRouteInfo) {
        DispatchQueue.main.async {
            self.activeRoute = route
            self.currentStepIndex = 0
            self.isNavigating = true
            if let first = route.steps.first {
                self.liveDistanceToNextTurnMeters = Int(first.distanceMeters)
            }
            self.pushCurrentStepToBike()
            TripperDashClient.shared.log("🧭 Started Live Navigation to '\(route.destinationName)' (\(route.steps.count) turns)")
        }
    }
    
    public func stopNavigation() {
        DispatchQueue.main.async {
            self.isNavigating = false
            self.activeRoute = nil
            self.currentStepIndex = 0
            self.liveDistanceToNextTurnMeters = 0
            TripperDashClient.shared.stopNavigation()
        }
    }
    
    public func nextStep() {
        DispatchQueue.main.async {
            guard let route = self.activeRoute else { return }
            if self.currentStepIndex + 1 < route.steps.count {
                self.currentStepIndex += 1
                self.liveDistanceToNextTurnMeters = Int(route.steps[self.currentStepIndex].distanceMeters)
                self.pushCurrentStepToBike()
            } else {
                // Reached final destination!
                TripperDashClient.shared.sendManeuver(
                    iconCode: ManeuverType.destination.k1gIconCode,
                    distanceMeters: 0,
                    streetName: "Arrived · \(route.destinationName)"
                )
            }
        }
    }
    
    public func previousStep() {
        DispatchQueue.main.async {
            guard let route = self.activeRoute, self.currentStepIndex > 0 else { return }
            self.currentStepIndex -= 1
            self.liveDistanceToNextTurnMeters = Int(route.steps[self.currentStepIndex].distanceMeters)
            self.pushCurrentStepToBike()
        }
    }
    
    /// Called automatically by LocationTracker as the motorcycle moves along the route
    public func updateRiderLocation(_ location: CLLocation) {
        guard isNavigating, let step = currentStep else { return }
        guard let lat = step.endLatitude, let lng = step.endLongitude else { return }
        
        let stepTarget = CLLocation(latitude: lat, longitude: lng)
        let dist = Int(max(0, location.distance(from: stepTarget)))
        
        DispatchQueue.main.async {
            self.liveDistanceToNextTurnMeters = dist
            let label = step.streetName.isEmpty ? step.instruction : step.streetName
            TripperDashClient.shared.sendManeuver(
                iconCode: step.maneuver.k1gIconCode,
                distanceMeters: UInt32(dist),
                streetName: label
            )
            
            // Automatically advance to the next maneuver when within 32 meters of the turn waypoint
            if dist <= 32 {
                self.nextStep()
            }
        }
    }
    
    private func pushCurrentStepToBike() {
        guard let step = currentStep else { return }
        let label = step.streetName.isEmpty ? step.instruction : step.streetName
        TripperDashClient.shared.sendManeuver(
            iconCode: step.maneuver.k1gIconCode,
            distanceMeters: UInt32(max(0, liveDistanceToNextTurnMeters)),
            streetName: label
        )
    }
}

// MARK: - Live Autocomplete Place Search Engine (Google Maps API + MapKit Local Search)
@Observable
public final class PlaceSearchCompleter: NSObject, MKLocalSearchCompleterDelegate, @unchecked Sendable {
    public var suggestions: [MKLocalSearchCompletion] = []
    public var searchResults: [PlaceSearchResult] = []
    public var isSearching: Bool = false
    
    private let completer = MKLocalSearchCompleter()
    
    public override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
    }
    
    public func updateQuery(_ fragment: String, near center: CLLocationCoordinate2D?) {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            DispatchQueue.main.async {
                self.suggestions = []
                self.searchResults = []
            }
            return
        }
        if let center = center {
            completer.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: 60_000,
                longitudinalMeters: 60_000
            )
        }
        completer.queryFragment = trimmed
    }
    
    public func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.suggestions = Array(completer.results.prefix(6))
        }
    }
    
    public func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

// MARK: - Route & Place Resolution Service (Google Maps SDK / Web API + MapKit Directions)
public final class RouteService: Sendable {
    public static let shared = RouteService()
    
    private init() {}
    
    public var googleMapsAPIKey: String {
        get { UserDefaults.standard.string(forKey: "pref_google_maps_api_key") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "pref_google_maps_api_key") }
    }
    
    // MARK: - Search Places by Name (Google Places API if key set, plus Apple MKLocalSearch)
    public func searchPlaces(query: String, near center: CLLocationCoordinate2D?) async throws -> [PlaceSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        // 1. Check if raw coordinates or Google Maps URL were entered directly
        if let coord = parseDestination(from: trimmed) {
            return [
                PlaceSearchResult(
                    title: "Pinned Location",
                    subtitle: String(format: "%.4f, %.4f", coord.latitude, coord.longitude),
                    latitude: coord.latitude,
                    longitude: coord.longitude
                )
            ]
        }
        
        // 2. If a Google Maps API Key is configured, query Google Maps Places Text Search API first
        let gKey = googleMapsAPIKey
        if !gKey.isEmpty,
           let gResults = try? await searchGooglePlaces(query: trimmed, near: center, apiKey: gKey),
           !gResults.isEmpty {
            return gResults
        }
        
        // 3. Query MapKit MKLocalSearch (works worldwide with zero API key!)
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = trimmed
        if let center = center {
            req.region = MKCoordinateRegion(center: center, latitudinalMeters: 80_000, longitudinalMeters: 80_000)
        }
        let search = MKLocalSearch(request: req)
        let resp = try await search.start()
        
        return resp.mapItems.prefix(8).compactMap { item in
            let coord = item.placemark.coordinate
            let title = item.name ?? trimmed
            let subtitle = [
                item.placemark.subLocality,
                item.placemark.locality,
                item.placemark.administrativeArea
            ].compactMap { $0 }.joined(separator: ", ")
            return PlaceSearchResult(
                title: title,
                subtitle: subtitle.isEmpty ? "Place" : subtitle,
                latitude: coord.latitude,
                longitude: coord.longitude
            )
        }
    }
    
    public func resolveCompletion(_ completion: MKLocalSearchCompletion) async throws -> PlaceSearchResult {
        let req = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: req)
        let resp = try await search.start()
        guard let item = resp.mapItems.first else {
            throw NSError(domain: "RouteService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Place not found"])
        }
        let coord = item.placemark.coordinate
        return PlaceSearchResult(
            title: item.name ?? completion.title,
            subtitle: completion.subtitle,
            latitude: coord.latitude,
            longitude: coord.longitude
        )
    }
    
    // MARK: - Google Maps Places Text Search API
    private func searchGooglePlaces(query: String, near center: CLLocationCoordinate2D?, apiKey: String) async throws -> [PlaceSearchResult] {
        var comps = URLComponents(string: "https://maps.googleapis.com/maps/api/place/textsearch/json")!
        var items = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "key", value: apiKey)
        ]
        if let c = center {
            items.append(URLQueryItem(name: "location", value: "\(c.latitude),\(c.longitude)"))
            items.append(URLQueryItem(name: "radius", value: "50000"))
        }
        comps.queryItems = items
        guard let url = comps.url else { return [] }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        
        return results.prefix(8).compactMap { dict in
            guard let name = dict["name"] as? String,
                  let geom = dict["geometry"] as? [String: Any],
                  let loc = geom["location"] as? [String: Any],
                  let lat = loc["lat"] as? Double,
                  let lng = loc["lng"] as? Double else { return nil }
            let addr = (dict["formatted_address"] as? String) ?? "Google Maps"
            return PlaceSearchResult(title: name, subtitle: addr, latitude: lat, longitude: lng)
        }
    }
    
    // MARK: - Location URL / Query Parser
    public func parseDestination(from input: String) -> CLLocationCoordinate2D? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let parts = trimmed.components(separatedBy: ",")
        if parts.count == 2,
           let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
           let lng = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        
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
    
    // MARK: - Turn-by-Turn Route Calculator (Google Directions API + Apple MapKit Directions)
    public func calculateRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String = "Destination"
    ) async throws -> DashRouteInfo {
        let gKey = googleMapsAPIKey
        if !gKey.isEmpty,
           let googleRoute = try? await calculateGoogleRoute(from: origin, to: destination, destinationName: destinationName, apiKey: gKey) {
            return googleRoute
        }
        
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
        
        var coordinates = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: primaryRoute.polyline.pointCount)
        primaryRoute.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: primaryRoute.polyline.pointCount))
        let encodedPolyline = PolylineEncoder.encode(coordinates: coordinates)
        
        var steps: [RouteStep] = []
        for step in primaryRoute.steps {
            if step.distance > 0 && !step.instructions.isEmpty {
                let maneuver = mapMKInstructionsToManeuver(step.instructions)
                var stepCoords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: step.polyline.pointCount)
                if step.polyline.pointCount > 0 {
                    step.polyline.getCoordinates(&stepCoords, range: NSRange(location: 0, length: step.polyline.pointCount))
                }
                let endCoord = stepCoords.last
                steps.append(RouteStep(
                    instruction: step.instructions,
                    distanceMeters: step.distance,
                    maneuver: maneuver,
                    streetName: step.instructions,
                    endLatitude: endCoord?.latitude,
                    endLongitude: endCoord?.longitude
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
    
    private func calculateGoogleRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String,
        apiKey: String
    ) async throws -> DashRouteInfo? {
        var comps = URLComponents(string: "https://maps.googleapis.com/maps/api/directions/json")!
        comps.queryItems = [
            URLQueryItem(name: "origin", value: "\(origin.latitude),\(origin.longitude)"),
            URLQueryItem(name: "destination", value: "\(destination.latitude),\(destination.longitude)"),
            URLQueryItem(name: "mode", value: "driving"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let url = comps.url else { return nil }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let routes = json["routes"] as? [[String: Any]],
              let firstRoute = routes.first,
              let legs = firstRoute["legs"] as? [[String: Any]],
              let firstLeg = legs.first else { return nil }
        
        let polyDict = firstRoute["overview_polyline"] as? [String: Any]
        let points = (polyDict?["points"] as? String) ?? ""
        let distDict = firstLeg["distance"] as? [String: Any]
        let durDict = firstLeg["duration"] as? [String: Any]
        let totalMeters = Double((distDict?["value"] as? Int) ?? 0)
        let totalSecs = (durDict?["value"] as? Int) ?? 0
        
        var routeSteps: [RouteStep] = []
        if let rawSteps = firstLeg["steps"] as? [[String: Any]] {
            for s in rawSteps {
                let html = (s["html_instructions"] as? String) ?? "Continue"
                let cleanInstruction = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                let sDist = Double(((s["distance"] as? [String: Any])?["value"] as? Int) ?? 0)
                let endLoc = s["end_location"] as? [String: Any]
                let endLat = endLoc?["lat"] as? Double
                let endLng = endLoc?["lng"] as? Double
                let maneuverStr = (s["maneuver"] as? String) ?? cleanInstruction
                let maneuver = mapMKInstructionsToManeuver(maneuverStr)
                
                routeSteps.append(RouteStep(
                    instruction: cleanInstruction,
                    distanceMeters: sDist,
                    maneuver: maneuver,
                    streetName: cleanInstruction,
                    endLatitude: endLat,
                    endLongitude: endLng
                ))
            }
        }
        
        return DashRouteInfo(
            destinationName: destinationName,
            totalDistanceMeters: totalMeters,
            totalDurationSeconds: totalSecs,
            encodedPolyline: points,
            steps: routeSteps
        )
    }
    
    private func mapMKInstructionsToManeuver(_ instruction: String) -> ManeuverType {
        let lower = instruction.lowercased()
        if lower.contains("slight left") || lower.contains("turn-slight-left") { return .turnSlightLeft }
        if lower.contains("sharp left") || lower.contains("turn-sharp-left") { return .turnSharpLeft }
        if lower.contains("left") { return .turnLeft }
        if lower.contains("slight right") || lower.contains("turn-slight-right") { return .turnSlightRight }
        if lower.contains("sharp right") || lower.contains("turn-sharp-right") { return .turnSharpRight }
        if lower.contains("right") { return .turnRight }
        if lower.contains("u-turn") || lower.contains("uturn") { return .uTurn }
        if lower.contains("roundabout") || lower.contains("rotary") { return .roundabout }
        if lower.contains("arrive") || lower.contains("destination") { return .destination }
        return .straight
    }
}
