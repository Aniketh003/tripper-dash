import SwiftUI
import MapKit

public struct RoutePreviewView: View {
    @Bindable var tracker: LocationTracker
    @Bindable var dashClient: TripperDashClient
    @Bindable var navEngine: NavigationEngine = NavigationEngine.shared
    
    @State private var searchQuery: String = ""
    @State private var searchCompleter = PlaceSearchCompleter()
    @State private var placeResults: [PlaceSearchResult] = []
    @State private var selectedPlace: PlaceSearchResult? = nil
    @State private var isCalculating: Bool = false
    @State private var routeInfo: DashRouteInfo? = nil
    @State private var errorMessage: String? = nil
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var decodedRouteCoords: [CLLocationCoordinate2D] = []
    @State private var showingGoogleKeyAlert: Bool = false
    @State private var googleKeyInput: String = RouteService.shared.googleMapsAPIKey
    
    public init(tracker: LocationTracker, dashClient: TripperDashClient) {
        self.tracker = tracker
        self.dashClient = dashClient
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        // 1. Live Place Search Bar + Autocomplete Dropdown
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Search Place or Address")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppTheme.textSecondary)
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        googleKeyInput = RouteService.shared.googleMapsAPIKey
                                        showingGoogleKeyAlert = true
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: RouteService.shared.googleMapsAPIKey.isEmpty ? "key" : "checkmark.seal.fill")
                                                .font(.system(size: 10, weight: .semibold))
                                            Text(RouteService.shared.googleMapsAPIKey.isEmpty ? "Google API Key" : "Google SDK Active")
                                                .font(.system(size: 11, weight: .semibold))
                                        }
                                        .foregroundColor(RouteService.shared.googleMapsAPIKey.isEmpty ? AppTheme.textTertiary : AppTheme.emerald)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                HStack(spacing: 10) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(AppTheme.accent)
                                    
                                    TextField("Search place, cafe, landmark or paste link…", text: $searchQuery)
                                        .font(.system(size: 15))
                                        .foregroundColor(.white)
                                        .autocorrectionDisabled()
                                        .onChange(of: searchQuery) { _, newValue in
                                            searchCompleter.updateQuery(newValue, near: tracker.currentLocation)
                                        }
                                        .onSubmit {
                                            performPlaceSearch()
                                        }
                                    
                                    if !searchQuery.isEmpty {
                                        Button(action: {
                                            searchQuery = ""
                                            placeResults = []
                                            searchCompleter.suggestions = []
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 15))
                                                .foregroundColor(AppTheme.textTertiary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Button(action: {
                                        #if os(iOS)
                                        if let clipboard = UIPasteboard.general.string {
                                            searchQuery = clipboard
                                            performPlaceSearch()
                                        }
                                        #elseif os(macOS)
                                        if let clipboard = NSPasteboard.general.string(forType: .string) {
                                            searchQuery = clipboard
                                            performPlaceSearch()
                                        }
                                        #endif
                                    }) {
                                        Text("Paste")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppTheme.accent)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(AppTheme.surfaceElevated)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(12)
                                .background(AppTheme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                
                                // Live Autocomplete Suggestions as you type
                                if !searchCompleter.suggestions.isEmpty && placeResults.isEmpty {
                                    VStack(spacing: 0) {
                                        ForEach(Array(searchCompleter.suggestions.enumerated()), id: \.offset) { idx, item in
                                            Button(action: {
                                                selectCompletion(item)
                                            }) {
                                                HStack(spacing: 10) {
                                                    Image(systemName: "mappin.and.ellipse")
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(AppTheme.accent)
                                                        .frame(width: 24)
                                                    
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(item.title)
                                                            .font(.system(size: 14, weight: .semibold))
                                                            .foregroundColor(AppTheme.textPrimary)
                                                            .lineLimit(1)
                                                        if !item.subtitle.isEmpty {
                                                            Text(item.subtitle)
                                                                .font(.system(size: 12))
                                                                .foregroundColor(AppTheme.textSecondary)
                                                                .lineLimit(1)
                                                        }
                                                    }
                                                    Spacer()
                                                    Image(systemName: "arrow.up.left")
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundColor(AppTheme.textTertiary)
                                                }
                                                .padding(.vertical, 9)
                                                .padding(.horizontal, 6)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            
                                            if idx < searchCompleter.suggestions.count - 1 {
                                                Divider().background(AppTheme.border)
                                            }
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                                
                                // Direct Search Results List (if multiple places matched)
                                if !placeResults.isEmpty {
                                    VStack(spacing: 6) {
                                        ForEach(placeResults) { place in
                                            Button(action: {
                                                routeToPlace(place)
                                            }) {
                                                HStack(spacing: 10) {
                                                    Image(systemName: "location.circle.fill")
                                                        .font(.system(size: 18))
                                                        .foregroundColor(AppTheme.emerald)
                                                    
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(place.title)
                                                            .font(.system(size: 14, weight: .semibold))
                                                            .foregroundColor(AppTheme.textPrimary)
                                                            .lineLimit(1)
                                                        Text(place.subtitle)
                                                            .font(.system(size: 12))
                                                            .foregroundColor(AppTheme.textSecondary)
                                                            .lineLimit(1)
                                                    }
                                                    Spacer()
                                                    Text("Route")
                                                        .font(.system(size: 12, weight: .semibold))
                                                        .foregroundColor(.black)
                                                        .padding(.horizontal, 12)
                                                        .padding(.vertical, 5)
                                                        .background(AppTheme.accent)
                                                        .clipShape(Capsule())
                                                }
                                                .padding(10)
                                                .background(AppTheme.surfaceElevated)
                                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                
                                Button(action: performPlaceSearch) {
                                    HStack(spacing: 8) {
                                        if isCalculating {
                                            ProgressView().tint(.black)
                                        } else {
                                            Image(systemName: "location.north.line.fill")
                                                .font(.system(size: 14, weight: .semibold))
                                        }
                                        Text(isCalculating ? "Searching & Routing…" : "Search & Calculate Route")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(searchQuery.isEmpty ? AppTheme.accent.opacity(0.45) : AppTheme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(searchQuery.isEmpty || isCalculating)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.coral)
                                .padding(.horizontal, 24)
                        }
                        
                        // 2. Interactive Route Map
                        if !decodedRouteCoords.isEmpty {
                            Map(position: $mapPosition) {
                                MapPolyline(coordinates: decodedRouteCoords)
                                    .stroke(AppTheme.accent, lineWidth: 5)
                                if let start = decodedRouteCoords.first {
                                    Marker("Origin", coordinate: start).tint(AppTheme.emerald)
                                }
                                if let dest = decodedRouteCoords.last {
                                    Marker(routeInfo?.destinationName ?? "Destination", coordinate: dest).tint(AppTheme.coral)
                                }
                            }
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(AppTheme.borderSpecular, lineWidth: 0.6)
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        // 3. Route Summary & Live Bike TFT Turn-by-Turn Controller
                        if let route = routeInfo {
                            GlassCard {
                                VStack(spacing: 14) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(route.destinationName)
                                                .font(.system(size: 18, weight: .bold))
                                                .foregroundColor(AppTheme.textPrimary)
                                            Text(navEngine.isNavigating ? "Live Turn-by-Turn Active on TFT" : "Ready to navigate")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(navEngine.isNavigating ? AppTheme.emerald : AppTheme.textSecondary)
                                        }
                                        Spacer()
                                    }
                                    
                                    Divider().background(AppTheme.border)
                                    
                                    HStack(spacing: 0) {
                                        StatTile(
                                            title: "Distance",
                                            value: String(format: "%.1f", route.totalDistanceMeters / 1000.0),
                                            unit: "km"
                                        )
                                        Rectangle()
                                            .fill(AppTheme.border)
                                            .frame(width: 0.6, height: 34)
                                            .padding(.horizontal, 12)
                                        StatTile(
                                            title: "ETA",
                                            value: "\(max(1, route.totalDurationSeconds / 60))",
                                            unit: "min"
                                        )
                                        Rectangle()
                                            .fill(AppTheme.border)
                                            .frame(width: 0.6, height: 34)
                                            .padding(.horizontal, 12)
                                        StatTile(
                                            title: "Turns",
                                            value: "\(route.steps.count)"
                                        )
                                    }
                                    
                                    Divider().background(AppTheme.border)
                                    
                                    if navEngine.isNavigating {
                                        // Active Turn Stepper & Stop Controls
                                        if let step = navEngine.currentStep {
                                            HStack(spacing: 12) {
                                                Image(systemName: step.maneuver.iconName)
                                                    .font(.system(size: 20, weight: .bold))
                                                    .foregroundColor(.black)
                                                    .frame(width: 42, height: 42)
                                                    .background(AppTheme.accent)
                                                    .clipShape(Circle())
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text("Step \(navEngine.currentStepIndex + 1) of \(route.steps.count) · \(navEngine.liveDistanceToNextTurnMeters) m")
                                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                                        .foregroundColor(AppTheme.accent)
                                                    Text(step.instruction)
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(AppTheme.textPrimary)
                                                        .lineLimit(2)
                                                }
                                                Spacer()
                                            }
                                            .padding(12)
                                            .background(AppTheme.surfaceElevated)
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        }
                                        
                                        HStack(spacing: 10) {
                                            Button(action: { navEngine.previousStep() }) {
                                                Label("Prev Turn", systemImage: "chevron.left")
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(AppTheme.textPrimary)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 12)
                                                    .background(AppTheme.surfaceElevated)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            }
                                            .buttonStyle(.plain)
                                            
                                            Button(action: { navEngine.nextStep() }) {
                                                Label("Next Turn", systemImage: "chevron.right")
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(.black)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 12)
                                                    .background(AppTheme.accent)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            }
                                            .buttonStyle(.plain)
                                            
                                            Button(action: { navEngine.stopNavigation() }) {
                                                Text("End")
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(AppTheme.coral)
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 12)
                                                    .background(AppTheme.surfaceElevated)
                                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    } else {
                                        MinimalButton(
                                            title: "Start Live Navigation on Bike TFT",
                                            icon: "location.north.fill",
                                            isProminent: true,
                                            tint: AppTheme.emerald
                                        ) {
                                            navEngine.startNavigation(route: route)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // 4. All Turn-by-Turn Steps (Tap any step to jump & project to TFT!)
                            VStack(alignment: .leading, spacing: 10) {
                                SectionLabel("Turn-by-Turn Steps (\(route.steps.count))")
                                    .padding(.horizontal, 24)
                                
                                ForEach(Array(route.steps.enumerated()), id: \.element.id) { idx, step in
                                    Button(action: {
                                        navEngine.activeRoute = route
                                        navEngine.currentStepIndex = idx
                                        navEngine.liveDistanceToNextTurnMeters = Int(step.distanceMeters)
                                        navEngine.isNavigating = true
                                        dashClient.sendManeuver(
                                            iconCode: step.maneuver.k1gIconCode,
                                            distanceMeters: UInt32(step.distanceMeters),
                                            streetName: step.streetName.isEmpty ? step.instruction : step.streetName
                                        )
                                    }) {
                                        GlassCard(cornerRadius: 16, padding: 14) {
                                            HStack(spacing: 12) {
                                                Image(systemName: step.maneuver.iconName)
                                                    .font(.system(size: 18, weight: .semibold))
                                                    .foregroundColor(navEngine.isNavigating && navEngine.currentStepIndex == idx ? .black : AppTheme.accent)
                                                    .frame(width: 38, height: 38)
                                                    .background(navEngine.isNavigating && navEngine.currentStepIndex == idx ? AppTheme.accent : AppTheme.surfaceElevated)
                                                    .clipShape(Circle())
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(step.instruction)
                                                        .font(.system(size: 14, weight: .medium))
                                                        .foregroundColor(AppTheme.textPrimary)
                                                        .multilineTextAlignment(.leading)
                                                    
                                                    Text(String(format: "%.0f m", step.distanceMeters))
                                                        .font(.system(size: 12, design: .rounded))
                                                        .monospacedDigit()
                                                        .foregroundColor(AppTheme.textSecondary)
                                                }
                                                
                                                Spacer()
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        
                        Spacer(minLength: 32)
                    }
                }
            }
            .navigationTitle("Navigate")
            .alert("Google Maps API Key (Optional)", isPresented: $showingGoogleKeyAlert) {
                TextField("AIzaSy...", text: $googleKeyInput)
                Button("Save") {
                    RouteService.shared.googleMapsAPIKey = googleKeyInput
                }
                Button("Use Built-In Search (Free)", role: .destructive) {
                    RouteService.shared.googleMapsAPIKey = ""
                    googleKeyInput = ""
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Place search and turn-by-turn routing work out-of-the-box. Paste a Google Maps Places/Directions API key if you prefer Google's routing engine.")
            }
        }
    }
    
    private func selectCompletion(_ completion: MKLocalSearchCompletion) {
        searchQuery = completion.title
        searchCompleter.suggestions = []
        errorMessage = nil
        isCalculating = true
        
        Task {
            do {
                let place = try await RouteService.shared.resolveCompletion(completion)
                await MainActor.run {
                    routeToPlace(place)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Could not resolve place: \(error.localizedDescription)"
                    self.isCalculating = false
                }
            }
        }
    }
    
    private func performPlaceSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchCompleter.suggestions = []
        errorMessage = nil
        isCalculating = true
        
        Task {
            do {
                let results = try await RouteService.shared.searchPlaces(query: query, near: tracker.currentLocation)
                await MainActor.run {
                    if let first = results.first {
                        self.placeResults = results.count > 1 ? Array(results.prefix(4)) : []
                        routeToPlace(first)
                    } else {
                        self.errorMessage = "No matching places found for '\(query)'."
                        self.isCalculating = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Search failed: \(error.localizedDescription)"
                    self.isCalculating = false
                }
            }
        }
    }
    
    private func routeToPlace(_ place: PlaceSearchResult) {
        selectedPlace = place
        placeResults = []
        searchCompleter.suggestions = []
        errorMessage = nil
        isCalculating = true
        
        let origin = tracker.currentLocation ?? CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946)
        let dest = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        
        Task {
            do {
                let info = try await RouteService.shared.calculateRoute(
                    from: origin,
                    to: dest,
                    destinationName: place.title
                )
                await MainActor.run {
                    self.routeInfo = info
                    self.decodedRouteCoords = PolylineEncoder.decode(polyline: info.encodedPolyline)
                    if let first = self.decodedRouteCoords.first {
                        self.mapPosition = .region(MKCoordinateRegion(
                            center: first,
                            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)
                        ))
                    }
                    self.isCalculating = false
                    // Automatically start streaming turn-by-turn to TFT if bike is connected!
                    if self.dashClient.connectionState == .connected {
                        self.navEngine.startNavigation(route: info)
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Could not calculate route to \(place.title): \(error.localizedDescription)"
                    self.isCalculating = false
                }
            }
        }
    }
}
