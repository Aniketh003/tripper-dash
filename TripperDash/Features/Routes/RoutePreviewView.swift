import SwiftUI
import MapKit

public struct RoutePreviewView: View {
    @Bindable var tracker: LocationTracker
    @Bindable var dashClient: TripperDashClient
    
    @State private var inputDestination: String = ""
    @State private var isCalculating: Bool = false
    @State private var routeInfo: DashRouteInfo? = nil
    @State private var errorMessage: String? = nil
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var decodedRouteCoords: [CLLocationCoordinate2D] = []
    
    public init(tracker: LocationTracker, dashClient: TripperDashClient) {
        self.tracker = tracker
        self.dashClient = dashClient
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Input Card
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("DESTINATION OR MAP LINK")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(AppTheme.textTertiary)
                                
                                HStack(spacing: 8) {
                                    TextField("Paste Google Maps link or coordinates...", text: $inputDestination)
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundColor(.white)
                                    
                                    Button(action: {
                                        #if os(iOS)
                                        if let clipboard = UIPasteboard.general.string {
                                            inputDestination = clipboard
                                        }
                                        #elseif os(macOS)
                                        if let clipboard = NSPasteboard.general.string(forType: .string) {
                                            inputDestination = clipboard
                                        }
                                        #endif
                                    }) {
                                        Text("Paste")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundColor(AppTheme.accent)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(AppTheme.surfaceElevated)
                                            .clipShape(Capsule())
                                    }
                                }
                                .padding(12)
                                .background(AppTheme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                
                                Button(action: calculateRoute) {
                                    HStack(spacing: 6) {
                                        if isCalculating {
                                            ProgressView()
                                                .tint(.black)
                                        } else {
                                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                                .font(.system(size: 14))
                                        }
                                        Text(isCalculating ? "Calculating Route..." : "Preview Route")
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(AppTheme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .disabled(inputDestination.isEmpty || isCalculating)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(AppTheme.coral)
                                .padding(.horizontal, 20)
                        }
                        
                        // Interactive Map Preview
                        if !decodedRouteCoords.isEmpty {
                            Map(position: $mapPosition) {
                                MapPolyline(coordinates: decodedRouteCoords)
                                    .stroke(AppTheme.accent, lineWidth: 5)
                            }
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        // Route Stats & Steps
                        if let route = routeInfo {
                            GlassCard {
                                HStack(spacing: 0) {
                                    StatTile(
                                        title: "Distance",
                                        value: String(format: "%.1f", route.totalDistanceMeters / 1000.0),
                                        unit: "km"
                                    )
                                    
                                    Divider()
                                        .background(AppTheme.border)
                                        .frame(height: 36)
                                        .padding(.horizontal, 12)
                                    
                                    StatTile(
                                        title: "Duration",
                                        value: String(format: "%d", route.totalDurationSeconds / 60),
                                        unit: "min"
                                    )
                                    
                                    if dashClient.connectionState == .connected {
                                        Divider()
                                            .background(AppTheme.border)
                                            .frame(height: 36)
                                            .padding(.horizontal, 12)
                                        
                                        Button(action: streamFirstStepToDash) {
                                            VStack(spacing: 2) {
                                                Image(systemName: "dot.radiowaves.up.forward")
                                                    .font(.system(size: 18))
                                                Text("Dash Sync")
                                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            }
                                            .foregroundColor(AppTheme.accent)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Turn-by-Turn Steps
                            VStack(alignment: .leading, spacing: 10) {
                                Text("TURN MANEUVERS (\(route.steps.count))")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(AppTheme.textTertiary)
                                    .padding(.horizontal, 20)
                                
                                ForEach(route.steps) { step in
                                    GlassCard(padding: 12) {
                                        HStack(spacing: 12) {
                                            Image(systemName: step.maneuver.iconName)
                                                .font(.system(size: 20))
                                                .foregroundColor(AppTheme.accent)
                                                .frame(width: 36, height: 36)
                                                .background(AppTheme.surfaceElevated)
                                                .clipShape(Circle())
                                            
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(step.instruction)
                                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                                    .foregroundColor(AppTheme.textPrimary)
                                                
                                                Text(String(format: "%.0f meters", step.distanceMeters))
                                                    .font(.system(size: 12, design: .monospaced))
                                                    .foregroundColor(AppTheme.textSecondary)
                                            }
                                            
                                            Spacer()
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        
                        Spacer(minLength: 30)
                    }
                }
            }
            .navigationTitle("Route Preview")
        }
    }
    
    private func calculateRoute() {
        guard let origin = tracker.currentLocation ?? CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946) as CLLocationCoordinate2D? else {
            errorMessage = "Location required to calculate route"
            return
        }
        
        guard let dest = RouteService.shared.parseDestination(from: inputDestination) else {
            errorMessage = "Could not parse coordinates. Enter lat,lng or Google Maps link"
            return
        }
        
        errorMessage = nil
        isCalculating = true
        
        Task {
            do {
                let info = try await RouteService.shared.calculateRoute(from: origin, to: dest)
                await MainActor.run {
                    self.routeInfo = info
                    self.decodedRouteCoords = PolylineEncoder.decode(polyline: info.encodedPolyline)
                    if let first = self.decodedRouteCoords.first {
                        self.mapPosition = .region(MKCoordinateRegion(
                            center: first,
                            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
                        ))
                    }
                    self.isCalculating = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to route: \(error.localizedDescription)"
                    self.isCalculating = false
                }
            }
        }
    }
    
    private func streamFirstStepToDash() {
        guard let firstStep = routeInfo?.steps.first else { return }
        dashClient.sendManeuver(
            iconCode: 0x01,
            distanceMeters: UInt32(firstStep.distanceMeters),
            streetName: firstStep.streetName.isEmpty ? firstStep.instruction : firstStep.streetName
        )
    }
}
