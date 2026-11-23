import SwiftUI

public struct CockpitView: View {
    @Bindable var tracker: LocationTracker
    @Bindable var vehicleStore: VehicleStore
    @Bindable var dashClient: TripperDashClient
    @Bindable var podClient: TripperPodClient = TripperPodClient.shared
    @Bindable var media: MediaPlaybackService = MediaPlaybackService.shared
    @Bindable var call: CallHandlingService = CallHandlingService.shared
    @Bindable var battery: BatteryOptimizationService = BatteryOptimizationService.shared
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
                    VStack(spacing: 16) {
                        // Top Status Bar: Vehicle, Battery ECO & Dash Link
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
                            
                            // Battery & Hardware Connection Pills
                            HStack(spacing: 8) {
                                // Battery ECO Badge
                                HStack(spacing: 4) {
                                    Image(systemName: battery.isPowerSavingActive ? "leaf.fill" : "bolt.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(battery.isPowerSavingActive ? AppTheme.emerald : AppTheme.accent)
                                    Text("\(battery.batteryLevelPercent)%")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(AppTheme.surfaceElevated)
                                .clipShape(Capsule())
                                
                                // Dash Link Pill
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(dashClient.connectionState == .connected || podClient.isConnected ? AppTheme.emerald : (isConnecting(dashClient.connectionState) ? AppTheme.accent : AppTheme.textTertiary))
                                        .frame(width: 7, height: 7)
                                    
                                    Text(dashClient.connectionState == .connected ? "TFT LINKED" : (podClient.isConnected ? "POD LINKED" : (isConnecting(dashClient.connectionState) ? "LINKING..." : "PHONE HUD")))
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AppTheme.surfaceElevated)
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        
                        // Incoming / Ongoing Call Overlay (if call active)
                        if call.isRinging || call.isOngoing {
                            GlassCard(padding: 14) {
                                HStack(spacing: 12) {
                                    Image(systemName: call.isRinging ? "phone.down.waves.and.radiowaves" : "phone.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(call.isRinging ? AppTheme.emerald : AppTheme.accent)
                                        .frame(width: 40, height: 40)
                                        .background(AppTheme.surfaceElevated)
                                        .clipShape(Circle())
                                    
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(call.callerName)
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                        
                                        HStack(spacing: 4) {
                                            Image(systemName: "headphones")
                                                .font(.system(size: 10))
                                            Text(call.activeAudioDeviceName)
                                                .font(.system(size: 11, design: .monospaced))
                                        }
                                        .foregroundColor(AppTheme.textSecondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if call.isRinging {
                                        Button(action: { call.answerCall() }) {
                                            Image(systemName: "phone.fill")
                                                .foregroundColor(.white)
                                                .frame(width: 36, height: 36)
                                                .background(AppTheme.emerald)
                                                .clipShape(Circle())
                                        }
                                    }
                                    
                                    Button(action: { call.endOrRejectCall() }) {
                                        Image(systemName: "phone.down.fill")
                                            .foregroundColor(.white)
                                            .frame(width: 36, height: 36)
                                            .background(AppTheme.coral)
                                            .clipShape(Circle())
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        
                        // Central Gauge
                        CircularGauge(
                            speed: tracker.currentSpeedKmh,
                            heading: tracker.currentHeading,
                            isRecording: tracker.isRecordingRide
                        )
                        .padding(.vertical, 6)
                        
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
                        
                        // Minimalist Media Playback Controller (Bike Handlebar Joystick Linked)
                        GlassCard(padding: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 15))
                                    .foregroundColor(AppTheme.accent)
                                    .frame(width: 32, height: 32)
                                    .background(AppTheme.surfaceElevated)
                                    .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(media.currentTitle)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(AppTheme.textPrimary)
                                        .lineLimit(1)
                                    
                                    Text(media.currentArtist.isEmpty ? "Handlebar controls active" : media.currentArtist)
                                        .font(.system(size: 11, design: .rounded))
                                        .foregroundColor(AppTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 16) {
                                    Button(action: { media.previousTrack() }) {
                                        Image(systemName: "backward.fill")
                                            .font(.system(size: 13))
                                            .foregroundColor(AppTheme.textSecondary)
                                    }
                                    
                                    Button(action: { media.togglePlayPause() }) {
                                        Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(AppTheme.accent)
                                    }
                                    
                                    Button(action: { media.nextTrack() }) {
                                        Image(systemName: "forward.fill")
                                            .font(.system(size: 13))
                                            .foregroundColor(AppTheme.textSecondary)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Primary Ride Action Button
                        VStack(spacing: 12) {
                            if tracker.isRecordingRide {
                                Button(action: {
                                    let generator = UINotificationFeedbackGenerator()
                                    generator.notificationOccurred(.success)
                                    if let ride = tracker.stopRide() {
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
    
    private func isConnecting(_ state: DashConnectionState) -> Bool {
        state == .verifyingNetwork || state == .requestingAuth || state == .exchangingKeys
    }
}
