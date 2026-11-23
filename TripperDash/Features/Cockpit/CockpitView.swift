import SwiftUI

public struct CockpitView: View {
    @Bindable var tracker: LocationTracker
    @Bindable var vehicleStore: VehicleStore
    @Bindable var dashClient: TripperDashClient
    let onRideSaved: (RideRecord) -> Void
    
    public init(
        tracker: LocationTracker,
        vehicleStore: VehicleStore,
        dashClient: TripperDashClient,
        onRideSaved: @escaping (RideRecord) -> Void
    ) {
        self.tracker = tracker
        self.vehicleStore = vehicleStore
        self.dashClient = dashClient
        self.onRideSaved = onRideSaved
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Top Status Bar: Vehicle & Dash Link
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vehicleStore.activeVehicle.title.uppercased())
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(AppTheme.textTertiary)
                                    .tracking(1.0)
                                
                                Text(vehicleStore.activeVehicle.nickname)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(AppTheme.textPrimary)
                            }
                            
                            Spacer()
                            
                            // Hardware Connection Pill
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(dashClient.connectionState == .connected ? AppTheme.emerald : AppTheme.textTertiary)
                                    .frame(width: 8, height: 8)
                                
                                Text(dashClient.connectionState == .connected ? "DASH LINKED" : "PHONE HUD")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.surfaceElevated)
                            .clipShape(Capsule())
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        
                        // Central Gauge
                        CircularGauge(
                            speed: tracker.currentSpeedKmh,
                            heading: tracker.currentHeading,
                            isRecording: tracker.isRecordingRide
                        )
                        .padding(.vertical, 10)
                        
                        // Live Ride Telemetry Cards
                        if tracker.isRecordingRide {
                            GlassCard {
                                HStack(spacing: 0) {
                                    StatTile(
                                        title: "Time",
                                        value: formattedTime(tracker.rideDurationSeconds),
                                        accentColor: AppTheme.emerald
                                    )
                                    
                                    Divider()
                                        .background(AppTheme.border)
                                        .frame(height: 36)
                                        .padding(.horizontal, 12)
                                    
                                    StatTile(
                                        title: "Trip",
                                        value: String(format: "%.1f", tracker.recordedDistanceMeters / 1000.0),
                                        unit: "km"
                                    )
                                    
                                    Divider()
                                        .background(AppTheme.border)
                                        .frame(height: 36)
                                        .padding(.horizontal, 12)
                                    
                                    StatTile(
                                        title: "Max",
                                        value: String(format: "%.0f", tracker.maxSpeedKmh),
                                        unit: "km/h"
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        } else {
                            // Standalone Cockpit Stats
                            GlassCard {
                                HStack(spacing: 0) {
                                    StatTile(
                                        title: "Odometer",
                                        value: String(format: "%.0f", vehicleStore.activeVehicle.currentOdometer),
                                        unit: "km"
                                    )
                                    
                                    Divider()
                                        .background(AppTheme.border)
                                        .frame(height: 36)
                                        .padding(.horizontal, 12)
                                    
                                    StatTile(
                                        title: "Altitude",
                                        value: String(format: "%.0f", tracker.currentAltitude),
                                        unit: "m"
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // Primary Ride Action Button
                        VStack(spacing: 12) {
                            if tracker.isRecordingRide {
                                Button(action: {
                                    let generator = UINotificationFeedbackGenerator()
                                    generator.notificationOccurred(.success)
                                    if let ride = tracker.stopRide() {
                                        // Update bike odometer automatically!
                                        vehicleStore.updateOdometer(km: vehicleStore.activeVehicle.currentOdometer + ride.distanceKm)
                                        onRideSaved(ride)
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "stop.fill")
                                            .font(.system(size: 14, weight: .bold))
                                        Text("FINISH RIDE SESSION")
                                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(AppTheme.coral)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            } else {
                                Button(action: {
                                    let generator = UIImpactFeedbackGenerator(style: .heavy)
                                    generator.impactOccurred()
                                    tracker.startRide()
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "record.circle")
                                            .font(.system(size: 16, weight: .bold))
                                        Text("START RIDE TRACKING")
                                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    }
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(AppTheme.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        Spacer(minLength: 20)
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    private func formattedTime(_ totalSeconds: Int) -> String {
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
