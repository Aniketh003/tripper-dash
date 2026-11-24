import Foundation
import CoreLocation
import MapKit

// MARK: - Live Turn-by-Turn Navigation Engine (Streams GPS Progress & Moving Map to Royal Enfield TFT)
@Observable
public final class NavigationEngine: @unchecked Sendable {
    public static let shared = NavigationEngine()
    
    public var activeRoute: DashRouteInfo? = nil
    public var currentStepIndex: Int = 0
    public var liveDistanceToNextTurnMeters: Int = 0
    public var totalRemainingDistanceMeters: Int = 0
    public var estimatedRemainingSeconds: Int = 0
    public var etaFormatted: String = ""
    public var isNavigating: Bool = false
    
    // Live Moving Map Geometry & Rider Pose for 526x300 TFT Projection
    public var decodedCoordinates: [CLLocationCoordinate2D] = []
    public var closestPolylineIndex: Int = 0
    public var riderCoordinate: CLLocationCoordinate2D? = nil
    public var riderHeadingDegrees: Double = 0.0
    
    private init() {}
    
    public var currentStep: RouteStep? {
        guard let route = activeRoute,
              currentStepIndex >= 0,
              currentStepIndex < route.steps.count else { return nil }
        return route.steps[currentStepIndex]
    }
    
    public var nextStepItem: RouteStep? {
        guard let route = activeRoute,
              currentStepIndex + 1 >= 0,
              currentStepIndex + 1 < route.steps.count else { return nil }
        return route.steps[currentStepIndex + 1]
    }
    
    public func startNavigation(route: DashRouteInfo) {
        let coords = PolylineEncoder.decode(polyline: route.encodedPolyline)
        DispatchQueue.main.async {
            self.activeRoute = route
            self.decodedCoordinates = coords
            self.closestPolylineIndex = 0
            self.currentStepIndex = 0
            self.isNavigating = true
            self.riderCoordinate = LocationTracker.shared?.currentLocation ?? coords.first
            if let heading = LocationTracker.shared?.currentHeading, heading > 0 {
                self.riderHeadingDegrees = heading
            } else if coords.count >= 2 {
                self.riderHeadingDegrees = Self.bearingDegrees(from: coords[0], to: coords[1])
            }
            if let first = route.steps.first {
                self.liveDistanceToNextTurnMeters = Int(first.distanceMeters)
            }
            self.recalculateRemainingTotals()
            self.pushCurrentStepToBike()
            TripperDashClient.shared.log("🧭 Started Live Navigation to '\(route.destinationName)' (\(route.steps.count) turns, \(String(format: "%.1f km", route.totalDistanceMeters / 1000.0)))")
        }
    }
    
    public func stopNavigation() {
        DispatchQueue.main.async {
            self.isNavigating = false
            self.activeRoute = nil
            self.decodedCoordinates = []
            self.closestPolylineIndex = 0
            self.currentStepIndex = 0
            self.liveDistanceToNextTurnMeters = 0
            self.totalRemainingDistanceMeters = 0
            self.estimatedRemainingSeconds = 0
            self.etaFormatted = ""
            TripperDashClient.shared.stopNavigation()
        }
    }
    
    public func jumpToStep(_ index: Int) {
        DispatchQueue.main.async {
            guard let route = self.activeRoute, index >= 0, index < route.steps.count else { return }
            self.currentStepIndex = index
            let step = route.steps[index]
            self.liveDistanceToNextTurnMeters = Int(step.distanceMeters)
            if let lat = step.endLatitude, let lng = step.endLongitude {
                let stepCoord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                self.riderCoordinate = stepCoord
                self.updateClosestPolylineIndex(to: stepCoord)
            }
            self.recalculateRemainingTotals()
            self.pushCurrentStepToBike()
        }
    }
    
    public func nextStep() {
        DispatchQueue.main.async {
            guard let route = self.activeRoute else { return }
            if self.currentStepIndex + 1 < route.steps.count {
                self.currentStepIndex += 1
                let step = route.steps[self.currentStepIndex]
                self.liveDistanceToNextTurnMeters = Int(step.distanceMeters)
                if let lat = step.endLatitude, let lng = step.endLongitude {
                    let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                    self.updateClosestPolylineIndex(to: coord)
                }
                self.recalculateRemainingTotals()
                self.pushCurrentStepToBike()
            } else {
                // Reached final destination!
                self.liveDistanceToNextTurnMeters = 0
                self.totalRemainingDistanceMeters = 0
                self.estimatedRemainingSeconds = 0
                TripperDashClient.shared.sendManeuver(
                    iconCode: ManeuverType.destination.k1gIconCode,
                    distanceMeters: 0,
                    totalDistanceMeters: 0,
                    remainingSeconds: 0,
                    streetName: "Arrived - \(route.destinationName)",
                    nextIconCode: DashK1GProtocol.navManeuverHidden,
                    etaText: self.etaFormatted
                )
            }
        }
    }
    
    public func previousStep() {
        DispatchQueue.main.async {
            guard let route = self.activeRoute, self.currentStepIndex > 0 else { return }
            self.currentStepIndex -= 1
            self.liveDistanceToNextTurnMeters = Int(route.steps[self.currentStepIndex].distanceMeters)
            self.recalculateRemainingTotals()
            self.pushCurrentStepToBike()
        }
    }
    
    /// Called automatically by LocationTracker as the motorcycle moves along the route
    public func updateRiderLocation(_ location: CLLocation) {
        guard isNavigating, let step = currentStep else { return }
        
        let coord = location.coordinate
        var newHeading = riderHeadingDegrees
        if location.course >= 0 && location.speed >= 0.8 {
            newHeading = location.course
        } else if let magHeading = LocationTracker.shared?.currentHeading, magHeading > 0 {
            newHeading = magHeading
        }
        
        var dist = liveDistanceToNextTurnMeters
        if let lat = step.endLatitude, let lng = step.endLongitude {
            let stepTarget = CLLocation(latitude: lat, longitude: lng)
            dist = Int(max(0, location.distance(from: stepTarget)))
        }
        
        DispatchQueue.main.async {
            self.riderCoordinate = coord
            self.riderHeadingDegrees = newHeading
            self.updateClosestPolylineIndex(to: coord)
            self.liveDistanceToNextTurnMeters = dist
            self.recalculateRemainingTotals()
            self.pushCurrentStepToBike()
            
            // Automatically advance to the next maneuver when within 30 meters of the turn waypoint
            if dist <= 30 {
                self.nextStep()
            }
        }
    }
    
    private func updateClosestPolylineIndex(to coord: CLLocationCoordinate2D) {
        guard !decodedCoordinates.isEmpty else { return }
        let searchStart = max(0, closestPolylineIndex - 5)
        let searchEnd = min(decodedCoordinates.count - 1, closestPolylineIndex + 80)
        var bestIdx = closestPolylineIndex
        var bestDistSq = Double.greatestFiniteMagnitude
        
        for i in searchStart...max(searchStart, searchEnd) {
            let p = decodedCoordinates[i]
            let dLat = p.latitude - coord.latitude
            let dLng = p.longitude - coord.longitude
            let dSq = dLat * dLat + dLng * dLng
            if dSq < bestDistSq {
                bestDistSq = dSq
                bestIdx = i
            }
        }
        self.closestPolylineIndex = bestIdx
        
        // If GPS course wasn't moving fast enough, orient along the upcoming road segment
        if (LocationTracker.shared?.currentSpeedKmh ?? 0) < 3.0,
           bestIdx + 1 < decodedCoordinates.count {
            self.riderHeadingDegrees = Self.bearingDegrees(from: decodedCoordinates[bestIdx], to: decodedCoordinates[bestIdx + 1])
        }
    }
    
    private func recalculateRemainingTotals() {
        guard let route = activeRoute else { return }
        var remMeters = max(0, liveDistanceToNextTurnMeters)
        if currentStepIndex + 1 < route.steps.count {
            for idx in (currentStepIndex + 1)..<route.steps.count {
                remMeters += Int(route.steps[idx].distanceMeters)
            }
        }
        self.totalRemainingDistanceMeters = max(liveDistanceToNextTurnMeters, remMeters)
        
        let totalRouteMeters = max(1.0, route.totalDistanceMeters)
        let ratio = min(1.0, max(0.0, Double(self.totalRemainingDistanceMeters) / totalRouteMeters))
        let estSecs = max(30, Int(Double(route.totalDurationSeconds) * ratio))
        self.estimatedRemainingSeconds = estSecs
        
        let arrival = Date().addingTimeInterval(TimeInterval(estSecs))
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        self.etaFormatted = fmt.string(from: arrival)
    }
    
    private func pushCurrentStepToBike() {
        guard let step = currentStep else { return }
        let label = step.streetName.isEmpty ? step.instruction : step.streetName
        let nextCode = nextStepItem?.maneuver.k1gIconCode ?? DashK1GProtocol.navManeuverHidden
        TripperDashClient.shared.sendManeuver(
            iconCode: step.maneuver.k1gIconCode,
            distanceMeters: UInt32(max(0, liveDistanceToNextTurnMeters)),
            totalDistanceMeters: UInt32(max(0, totalRemainingDistanceMeters)),
            remainingSeconds: estimatedRemainingSeconds,
            streetName: label,
            nextIconCode: nextCode,
            etaText: etaFormatted
        )
    }
    
    public static func bearingDegrees(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180.0
        let lon1 = a.longitude * .pi / 180.0
        let lat2 = b.latitude * .pi / 180.0
        let lon2 = b.longitude * .pi / 180.0
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let brng = atan2(y, x) * 180.0 / .pi
        return (brng + 360.0).truncatingRemainder(dividingBy: 360.0)
    }
}

// MARK: - Live Autocomplete Place Search Engine (Cellular-Aware Photon/Google + MapKit Local Search)
@Observable
public final class PlaceSearchCompleter: NSObject, MKLocalSearchCompleterDelegate, @unchecked Sendable {
    public var suggestions: [MKLocalSearchCompletion] = []
    public var searchResults: [PlaceSearchResult] = []
    public var isSearching: Bool = false
    
    private let completer = MKLocalSearchCompleter()
    private var debounceTask: Task<Void, Never>?
    
    public override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
    }
    
    public func updateQuery(_ fragment: String, near center: CLLocationCoordinate2D?) {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        debounceTask?.cancel()
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
        
        // Also fetch cellular-routed place suggestions after 320ms debounce so autocomplete
        // works even when iPhone Wi-Fi is connected to the bike's no-internet hotspot!
        if trimmed.count >= 3 {
            debounceTask = Task {
                try? await Task.sleep(nanoseconds: 320_000_000)
                guard !Task.isCancelled else { return }
                if let results = try? await RouteService.shared.searchPlaces(query: trimmed, near: center),
                   !Task.isCancelled {
                    await MainActor.run {
                        self.searchResults = Array(results.prefix(5))
                    }
                }
            }
        }
    }
    
    public func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.suggestions = Array(completer.results.prefix(6))
        }
    }
    
    public func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

// MARK: - Route & Place Resolution Service (Cellular Multipath Google / OSRM / Photon + MapKit)
public final class RouteService: @unchecked Sendable {
    public static let shared = RouteService()
    
    /// Dedicated cellular/multipath URLSession that routes over 4G/5G cellular data even when
    /// Wi-Fi (`en0`) is connected to the Royal Enfield TFT Dash AP (`192.168.1.1`) with no internet.
    private let cellularSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.allowsCellularAccess = true
        cfg.allowsExpensiveNetworkAccess = true
        cfg.allowsConstrainedNetworkAccess = true
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        #if os(iOS)
        cfg.multipathServiceType = .handover
        #endif
        return URLSession(configuration: cfg)
    }()
    
    private init() {}
    
    public var googleMapsAPIKey: String {
        get { UserDefaults.standard.string(forKey: "pref_google_maps_api_key") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "pref_google_maps_api_key") }
    }
    
    // MARK: - Search Places by Name (Google Places + Photon/Nominatim Cellular + Apple MKLocalSearch)
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
        
        // 2. If a Google Maps API Key is configured, query Google Maps Places Text Search API first (over cellularSession)
        let gKey = googleMapsAPIKey
        if !gKey.isEmpty,
           let gResults = try? await searchGooglePlaces(query: trimmed, near: center, apiKey: gKey),
           !gResults.isEmpty {
            return gResults
        }
        
        // 3. Query OpenStreetMap Photon/Nominatim over cellularSession (works reliably when connected to Bike Wi-Fi!)
        if let osmResults = try? await searchPhotonPlaces(query: trimmed, near: center),
           !osmResults.isEmpty {
            return osmResults
        }
        
        if let nomResults = try? await searchNominatimPlaces(query: trimmed, near: center),
           !nomResults.isEmpty {
            return nomResults
        }
        
        // 4. Fallback to Apple MapKit MKLocalSearch
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
        if let results = try? await searchPlaces(query: "\(completion.title) \(completion.subtitle)", near: LocationTracker.shared?.currentLocation),
           let first = results.first {
            return first
        }
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
    
    // MARK: - OpenStreetMap Photon & Nominatim Place Search (Works over Cellular while on Bike Wi-Fi)
    private func searchPhotonPlaces(query: String, near center: CLLocationCoordinate2D?) async throws -> [PlaceSearchResult] {
        var comps = URLComponents(string: "https://photon.komoot.io/api/")!
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "6")
        ]
        if let c = center {
            items.append(URLQueryItem(name: "lat", value: "\(c.latitude)"))
            items.append(URLQueryItem(name: "lon", value: "\(c.longitude)"))
        }
        comps.queryItems = items
        guard let url = comps.url else { return [] }
        
        var req = URLRequest(url: url)
        req.setValue("TripperDash-iOS/2.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await cellularSession.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else { return [] }
        
        return features.compactMap { feat in
            guard let geom = feat["geometry"] as? [String: Any],
                  let coords = geom["coordinates"] as? [Double],
                  coords.count >= 2,
                  let props = feat["properties"] as? [String: Any] else { return nil }
            let lng = coords[0]
            let lat = coords[1]
            let name = (props["name"] as? String) ?? (props["street"] as? String) ?? query
            let subParts = [
                props["street"] as? String,
                props["district"] as? String,
                props["city"] as? String,
                props["state"] as? String
            ].compactMap { $0 }.filter { $0 != name }
            let subtitle = subParts.isEmpty ? ((props["country"] as? String) ?? "Place") : subParts.joined(separator: ", ")
            return PlaceSearchResult(title: name, subtitle: subtitle, latitude: lat, longitude: lng)
        }
    }
    
    private func searchNominatimPlaces(query: String, near center: CLLocationCoordinate2D?) async throws -> [PlaceSearchResult] {
        var comps = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "6")
        ]
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url)
        req.setValue("TripperDash-iOS/2.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await cellularSession.data(for: req)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        
        return arr.compactMap { item in
            guard let latStr = item["lat"] as? String,
                  let lonStr = item["lon"] as? String,
                  let lat = Double(latStr),
                  let lon = Double(lonStr),
                  let displayName = item["display_name"] as? String else { return nil }
            let comps = displayName.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let title = comps.first ?? query
            let subtitle = comps.dropFirst().prefix(3).joined(separator: ", ")
            return PlaceSearchResult(title: title, subtitle: subtitle.isEmpty ? displayName : subtitle, latitude: lat, longitude: lon)
        }
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
        
        let (data, _) = try await cellularSession.data(from: url)
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
    
    // MARK: - Turn-by-Turn Route Calculator (Google Directions + OSRM Cellular + Apple MapKit)
    public func calculateRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String = "Destination"
    ) async throws -> DashRouteInfo {
        // 1. Google Directions API (if API key configured)
        let gKey = googleMapsAPIKey
        if !gKey.isEmpty,
           let googleRoute = try? await calculateGoogleRoute(from: origin, to: destination, destinationName: destinationName, apiKey: gKey) {
            return googleRoute
        }
        
        // 2. OSRM Turn-by-Turn Routing over Cellular Multipath Session (works reliably even when connected to Bike Wi-Fi!)
        if let osrmRoute = try? await calculateOSRMRoute(from: origin, to: destination, destinationName: destinationName) {
            return osrmRoute
        }
        
        // 3. Fallback to Apple MapKit MKDirections
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
    
    // MARK: - OSRM Turn-by-Turn Driving Directions (Zero-Key Cellular Routing)
    private func calculateOSRMRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        destinationName: String
    ) async throws -> DashRouteInfo? {
        let urlStr = "https://router.project-osrm.org/route/v1/driving/\(origin.longitude),\(origin.latitude);\(destination.longitude),\(destination.latitude)?overview=full&geometries=polyline&steps=true"
        guard let url = URL(string: urlStr) else { return nil }
        
        var req = URLRequest(url: url)
        req.setValue("TripperDash-iOS/2.0", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await cellularSession.data(for: req)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let routes = json["routes"] as? [[String: Any]],
              let firstRoute = routes.first,
              let geometry = firstRoute["geometry"] as? String,
              let legs = firstRoute["legs"] as? [[String: Any]],
              let firstLeg = legs.first,
              let rawSteps = firstLeg["steps"] as? [[String: Any]] else {
            return nil
        }
        
        let totalMeters = (firstRoute["distance"] as? Double) ?? 0
        let totalSecs = Int((firstRoute["duration"] as? Double) ?? 0)
        
        // Parse OSRM steps: in OSRM, each step starts at its maneuver.location and continues for step.distance
        // until the NEXT step's maneuver.location (which is where the rider performs the next turn!).
        // To match turn-by-turn navigation UX (where each card tells you the upcoming turn at the end of the current segment),
        // we pair each segment's distance with the maneuver at the end of that segment.
        struct ParsedOSRMStep {
            let maneuverType: String
            let modifier: String
            let roadName: String
            let distance: Double
            let lat: Double
            let lng: Double
        }
        
        var parsed: [ParsedOSRMStep] = []
        for s in rawSteps {
            let dist = (s["distance"] as? Double) ?? 0
            let name = ((s["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let ref = ((s["ref"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let road = !name.isEmpty ? name : (!ref.isEmpty ? ref : "")
            let manDict = (s["maneuver"] as? [String: Any]) ?? [:]
            let mType = (manDict["type"] as? String) ?? "continue"
            let mMod = (manDict["modifier"] as? String) ?? ""
            let loc = (manDict["location"] as? [Double]) ?? []
            let lng = loc.count >= 2 ? loc[0] : destination.longitude
            let lat = loc.count >= 2 ? loc[1] : destination.latitude
            parsed.append(ParsedOSRMStep(maneuverType: mType, modifier: mMod, roadName: road, distance: dist, lat: lat, lng: lng))
        }
        
        var routeSteps: [RouteStep] = []
        if parsed.count >= 2 {
            for i in 0..<(parsed.count - 1) {
                let currentSeg = parsed[i]
                let upcomingTurn = parsed[i + 1]
                if currentSeg.distance < 3 && upcomingTurn.maneuverType != "arrive" {
                    continue
                }
                let (maneuver, instruction, shortRoad) = formatOSRMManeuver(
                    type: upcomingTurn.maneuverType,
                    modifier: upcomingTurn.modifier,
                    roadName: upcomingTurn.roadName.isEmpty ? currentSeg.roadName : upcomingTurn.roadName,
                    destinationName: destinationName
                )
                routeSteps.append(RouteStep(
                    instruction: instruction,
                    distanceMeters: max(5, currentSeg.distance),
                    maneuver: maneuver,
                    streetName: shortRoad,
                    endLatitude: upcomingTurn.lat,
                    endLongitude: upcomingTurn.lng
                ))
            }
        } else if let only = parsed.first {
            routeSteps.append(RouteStep(
                instruction: "Head to \(destinationName)",
                distanceMeters: max(10, only.distance),
                maneuver: .destination,
                streetName: destinationName,
                endLatitude: destination.latitude,
                endLongitude: destination.longitude
            ))
        }
        
        guard !routeSteps.isEmpty else { return nil }
        return DashRouteInfo(
            destinationName: destinationName,
            totalDistanceMeters: totalMeters,
            totalDurationSeconds: totalSecs,
            encodedPolyline: geometry,
            steps: routeSteps
        )
    }
    
    private func formatOSRMManeuver(
        type: String,
        modifier: String,
        roadName: String,
        destinationName: String
    ) -> (ManeuverType, String, String) {
        let t = type.lowercased()
        let m = modifier.lowercased()
        let cleanRoad = roadName.isEmpty ? destinationName : roadName
        
        if t == "arrive" {
            return (.destination, "Arrive at \(destinationName)", destinationName)
        }
        if t.contains("roundabout") || t.contains("rotary") {
            let label = roadName.isEmpty ? "Roundabout" : "Roundabout -> \(roadName)"
            return (.roundabout, "Take roundabout onto \(cleanRoad)", label)
        }
        if m.contains("uturn") {
            return (.uTurn, "Make a U-turn onto \(cleanRoad)", cleanRoad)
        }
        if m.contains("sharp left") {
            return (.turnSharpLeft, "Sharp left onto \(cleanRoad)", cleanRoad)
        }
        if m.contains("sharp right") {
            return (.turnSharpRight, "Sharp right onto \(cleanRoad)", cleanRoad)
        }
        if m.contains("slight left") {
            return (.turnSlightLeft, "Slight left onto \(cleanRoad)", cleanRoad)
        }
        if m.contains("slight right") {
            return (.turnSlightRight, "Slight right onto \(cleanRoad)", cleanRoad)
        }
        if m.contains("left") {
            return (.turnLeft, "Turn left onto \(cleanRoad)", cleanRoad)
        }
        if m.contains("right") {
            return (.turnRight, "Turn right onto \(cleanRoad)", cleanRoad)
        }
        return (.straight, "Continue on \(cleanRoad)", cleanRoad)
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
        
        let (data, _) = try await cellularSession.data(from: url)
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
