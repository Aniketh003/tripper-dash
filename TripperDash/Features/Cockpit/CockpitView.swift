import SwiftUI

public struct CockpitView: View {
    @Bindable var tracker: LocationTracker
    @Bindable var vehicleStore: VehicleStore
    @Bindable var dashClient: TripperDashClient
    @Bindable var podClient: TripperPodClient = TripperPodClient.shared
    @Bindable var media: MediaPlaybackService = MediaPlaybackService.shared
    @Bindable var call: CallHandlingService = CallHandlingService.shared
    @Bindable var battery: BatteryOptimizationService = BatteryOptimizationService.shared
    @Bindable var weather: WeatherService = WeatherService.shared
    @Bindable var projection: TFTProjectionService = TFTProjectionService.shared
    
    @State private var showTFTPreview: Bool = false
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
    
    private var isLinked: Bool {
        dashClient.connectionState == .connected || podClient.isConnected
    }
    
    private var linkStatusLabel: String {
        if dashClient.connectionState == .connected { return "TFT Linked" }
        if podClient.isConnected { return "Pod Linked" }
        if isConnecting(dashClient.connectionState) { return "Connecting…" }
        return "Standby"
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Minimal Header: Bike Identity + Live Link Pill
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vehicleStore.activeVehicle.nickname)
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(AppTheme.textPrimary)
                                
                                Text(vehicleStore.activeVehicle.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            
                            Spacer()
                            
                            // Calm Apple Status Pill
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(isLinked ? AppTheme.emerald : (isConnecting(dashClient.connectionState) ? AppTheme.accent : AppTheme.textTertiary))
                                    .frame(width: 7, height: 7)
                                Text(linkStatusLabel)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(isLinked ? AppTheme.textPrimary : AppTheme.textSecondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(AppTheme.surface)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(isLinked ? AppTheme.emerald.opacity(0.35) : AppTheme.border, lineWidth: 0.6)
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        
                        // Ambient Weather & Battery Strip (Tap to refresh weather)
                        Button(action: {
                            weather.refresh(for: tracker.currentLocation, force: true)
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: weather.symbolName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(AppTheme.accent)
                                
                                Text("\(weather.temperatureC)°")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(AppTheme.textPrimary)
                                
                                Text("\(weather.conditionText) · \(weather.locationName)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppTheme.textSecondary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                HStack(spacing: 4) {
                                    Image(systemName: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent")
                                        .font(.system(size: 12))
                                        .foregroundColor(battery.isPowerSavingActive ? AppTheme.emerald : AppTheme.textSecondary)
                                    Text("\(battery.batteryLevelPercent)%")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(AppTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(AppTheme.borderSpecular, lineWidth: 0.6)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        
                        // Centerpiece Switcher: Phone Gauge vs Live Bike TFT Digital Homescreen Preview
                        VStack(spacing: 14) {
                            HStack(spacing: 4) {
                                modeTabButton(title: "Gauge", isSelected: !showTFTPreview) {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        showTFTPreview = false
                                    }
                                }
                                modeTabButton(title: "Bike TFT", isSelected: showTFTPreview) {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        showTFTPreview = true
                                    }
                                }
                            }
                            .padding(3)
                            .background(AppTheme.surface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(AppTheme.border, lineWidth: 0.6))
                            
                            if showTFTPreview {
                                VStack(spacing: 10) {
                                    TFTHomescreenCanvas(
                                        speedKmh: tracker.currentSpeedKmh,
                                        heading: tracker.currentHeading,
                                        weatherTempC: weather.temperatureC,
                                        weatherCondition: weather.conditionText,
                                        weatherSymbol: weather.symbolName,
                                        weatherLocation: weather.locationName,
                                        windKmh: weather.windSpeedKmh,
                                        songTitle: media.currentTitle,
                                        songArtist: media.currentArtist,
                                        isMusicPlaying: media.isPlaying,
                                        volumePercent: media.volumePercent,
                                        batteryPercent: battery.batteryLevelPercent,
                                        isCallRinging: call.isRinging,
                                        isCallOngoing: call.isOngoing,
                                        callerName: call.callerName,
                                        callDuration: call.formattedDuration,
                                        showWeather: dashClient.showWeatherOnTFT,
                                        showMusic: dashClient.showMusicOnTFT,
                                        showSpeed: dashClient.showSpeedOnTFT,
                                        activeNavInstruction: dashClient.isNavigationActive ? dashClient.activeNavStreet : nil,
                                        activeNavDistanceMeters: dashClient.isNavigationActive ? dashClient.activeNavDistanceMeters : nil
                                    )
                                    .frame(width: 264, height: 264)
                                    .shadow(color: .black.opacity(0.6), radius: 24, y: 8)
                                    
                                    Text(projection.isStreaming ? "Streaming live to TFT · \(String(format: "%.1f", projection.currentFPS)) fps" : "Digital Mode Homescreen Preview")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(projection.isStreaming ? AppTheme.emerald : AppTheme.textTertiary)
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            } else {
                                CircularGauge(
                                    speed: tracker.currentSpeedKmh,
                                    heading: tracker.currentHeading,
                                    isRecording: tracker.isRecordingRide
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            }
                        }
                        .padding(.vertical, 4)
                        
                        // Live Ride Telemetry Card
                        GlassCard {
                            if tracker.isRecordingRide {
                                HStack(spacing: 0) {
                                    StatTile(
                                        title: "Duration",
                                        value: formattedTime(tracker.rideDurationSeconds),
                                        accentColor: AppTheme.emerald
                                    )
                                    dividerLine
                                    StatTile(
                                        title: "Distance",
                                        value: String(format: "%.1f", tracker.recordedDistanceMeters / 1000.0),
                                        unit: "km"
                                    )
                                    dividerLine
                                    StatTile(
                                        title: "Max",
                                        value: String(format: "%.0f", tracker.maxSpeedKmh),
                                        unit: "km/h"
                                    )
                                }
                            } else {
                                HStack(spacing: 0) {
                                    StatTile(
                                        title: "Odometer",
                                        value: String(format: "%.0f", vehicleStore.activeVehicle.currentOdometer),
                                        unit: "km"
                                    )
                                    dividerLine
                                    StatTile(
                                        title: "Elevation",
                                        value: String(format: "%.0f", tracker.currentAltitude),
                                        unit: "m"
                                    )
                                    dividerLine
                                    StatTile(
                                        title: "Wind",
                                        value: "\(weather.windSpeedKmh)",
                                        unit: "km/h"
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Refined Apple Music-Style Now Playing & Volume Card
                        GlassCard(padding: 16) {
                            VStack(spacing: 14) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(AppTheme.surfaceElevated)
                                            .frame(width: 42, height: 42)
                                        Image(systemName: media.isPlaying ? "waveform" : "music.note")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(media.isPlaying ? AppTheme.accent : AppTheme.textSecondary)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(media.currentTitle)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(AppTheme.textPrimary)
                                            .lineLimit(1)
                                        
                                        Text(media.currentArtist.isEmpty ? "Handlebar Joystick Linked" : media.currentArtist)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(AppTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 18) {
                                        Button(action: { media.previousTrack() }) {
                                            Image(systemName: "backward.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(AppTheme.textSecondary)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        Button(action: { media.togglePlayPause() }) {
                                            Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                                                .font(.system(size: 18, weight: .semibold))
                                                .foregroundColor(AppTheme.textPrimary)
                                        }
                                        .buttonStyle(.plain)
                                        
                                        Button(action: { media.nextTrack() }) {
                                            Image(systemName: "forward.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(AppTheme.textSecondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                
                                // Volume Strip (Synced with Joystick Up / Down)
                                HStack(spacing: 10) {
                                    Button(action: { media.volumeDown() }) {
                                        Image(systemName: "speaker.wave.1.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(AppTheme.textTertiary)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.white.opacity(0.10))
                                            Capsule()
                                                .fill(AppTheme.textPrimary.opacity(0.85))
                                                .frame(width: max(6, geo.size.width * CGFloat(media.volumePercent) / 100.0))
                                        }
                                        .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { value in
                                                    let ratio = Float(min(max(0, value.location.x / max(1, geo.size.width)), 1))
                                                    media.setVolume(ratio)
                                                }
                                        )
                                    }
                                    .frame(height: 5)
                                    
                                    Button(action: { media.volumeUp() }) {
                                        Image(systemName: "speaker.wave.3.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(AppTheme.textTertiary)
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Text("\(media.volumePercent)%")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundColor(AppTheme.textTertiary)
                                        .frame(width: 32, alignment: .trailing)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Single Crisp Primary Action
                        if tracker.isRecordingRide {
                            MinimalButton(title: "Finish Ride", icon: "stop.fill", isProminent: true, tint: AppTheme.coral) {
                                #if os(iOS)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                #endif
                                if let ride = tracker.stopRide() {
                                    vehicleStore.updateOdometer(km: vehicleStore.activeVehicle.currentOdometer + ride.distanceKm)
                                    onRideSaved(ride)
                                }
                            }
                            .padding(.horizontal, 20)
                        } else {
                            MinimalButton(title: "Start Ride", icon: "play.fill", isProminent: true, tint: AppTheme.accent) {
                                tracker.startRide()
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer(minLength: 24)
                    }
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    private var dividerLine: some View {
        Rectangle()
            .fill(AppTheme.border)
            .frame(width: 0.6, height: 34)
            .padding(.horizontal, 12)
    }
    
    private func modeTabButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? .black : AppTheme.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(isSelected ? Color.white : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
