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
                        // Destination Input Card
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Destination")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.textSecondary)
                                
                                HStack(spacing: 10) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(AppTheme.textTertiary)
                                    
                                    TextField("Google Maps link or lat, lng", text: $inputDestination)
                                        .font(.system(size: 15))
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
                                
                                Button(action: calculateRoute) {
                                    HStack(spacing: 8) {
                                        if isCalculating {
                                            ProgressView().tint(.black)
                                        } else {
                                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                                .font(.system(size: 14, weight: .semibold))
                                        }
                                        Text(isCalculating ? "Calculating…" : "Preview Route")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(inputDestination.isEmpty ? AppTheme.accent.opacity(0.45) : AppTheme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .disabled(inputDestination.isEmpty || isCalculating)
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
                        
                        // Map Preview
                        if !decodedRouteCoords.isEmpty {
                            Map(position: $mapPosition) {
                                MapPolyline(coordinates: decodedRouteCoords)
                                    .stroke(AppTheme.accent, lineWidth: 5)
                            }
                            .frame(height: 230)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(AppTheme.borderSpecular, lineWidth: 0.6)
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        // Route Stats & TFT Sync
                        if let route = routeInfo {
                            GlassCard {
                                VStack(spacing: 14) {
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
                                            title: "Duration",
                                            value: "\(route.totalDurationSeconds / 60)",
                                            unit: "min"
                                        )
                                    }
                                    
                                    if dashClient.connectionState == .connected {
                                        Divider().background(AppTheme.border)
                                        
                                        HStack(spacing: 10) {
                                            MinimalButton(
                                                title: dashClient.isNavigationActive ? "Update TFT Turn" : "Send to Bike TFT",
                                                icon: "dot.radiowaves.up.forward",
                                                isProminent: true,
                                                tint: AppTheme.accent,
                                                action: streamFirstStepToDash
                                            )
                                            
                                            if dashClient.isNavigationActive {
                                                Button(action: { dashClient.stopNavigation() }) {
                                                    Text("End")
                                                        .font(.system(size: 15, weight: .semibold))
                                                        .foregroundColor(AppTheme.coral)
                                                        .padding(.horizontal, 18)
                                                        .padding(.vertical, 16)
                                                        .background(AppTheme.surfaceElevated)
                                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Turn-by-Turn Steps
                            VStack(alignment: .leading, spacing: 10) {
                                SectionLabel("Turn-by-Turn (\(route.steps.count))")
                                    .padding(.horizontal, 24)
                                
                                ForEach(route.steps) { step in
                                    GlassCard(cornerRadius: 16, padding: 14) {
                                        HStack(spacing: 12) {
                                            Image(systemName: step.maneuver.iconName)
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(AppTheme.accent)
                                                .frame(width: 38, height: 38)
                                                .background(AppTheme.surfaceElevated)
                                                .clipShape(Circle())
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(step.instruction)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundColor(AppTheme.textPrimary)
                                                
                                                Text(String(format: "%.0f m", step.distanceMeters))
                                                    .font(.system(size: 12, design: .rounded))
                                                    .monospacedDigit()
                                                    .foregroundColor(AppTheme.textSecondary)
                                            }
                                            
                                            Spacer()
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        
                        Spacer(minLength: 32)
                    }
                }
            }
            .navigationTitle("Navigate")
        }
    }
    
    private func calculateRoute() {
        let origin = tracker.currentLocation ?? CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946)
        
        guard let dest = RouteService.shared.parseDestination(from: inputDestination) else {
            errorMessage = "Enter coordinates (lat, lng) or a Google Maps link."
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
                    self.errorMessage = "Could not calculate route: \(error.localizedDescription)"
                    self.isCalculating = false
                }
            }
        }
    }
    
    private func streamFirstStepToDash() {
        guard let firstStep = routeInfo?.steps.first else { return }
        dashClient.sendManeuver(
            iconCode: 0x04,
            distanceMeters: UInt32(firstStep.distanceMeters),
            streetName: firstStep.streetName.isEmpty ? firstStep.instruction : firstStep.streetName
        )
    }
}
