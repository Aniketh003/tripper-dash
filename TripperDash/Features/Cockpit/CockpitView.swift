import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

public struct CockpitView: View {
    @Bindable var tracker: LocationTracker
    @Bindable var vehicleStore: VehicleStore
    @Bindable var dashClient: TripperDashClient
    @Bindable var podClient: TripperPodClient = TripperPodClient.shared
    @Bindable var media: MediaPlaybackService = MediaPlaybackService.shared
    @Bindable var spotify: SpotifyService = SpotifyService.shared
    @Bindable var call: CallHandlingService = CallHandlingService.shared
    @Bindable var battery: BatteryOptimizationService = BatteryOptimizationService.shared
    @Bindable var weather: WeatherService = WeatherService.shared
    @Bindable var projection: TFTProjectionService = TFTProjectionService.shared
    
    @State private var showingSpotifySheet = false
    #if canImport(PhotosUI)
    @State private var cockpitWallpaperItem: PhotosPickerItem? = nil
    #endif
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
                    VStack(spacing: 18) {
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
                                Image(systemName: weather.isLoaded ? weather.symbolName : "location.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(AppTheme.accent)
                                
                                if weather.isLoaded {
                                    Text("\(weather.temperatureC)°C")
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundColor(AppTheme.textPrimary)
                                    
                                    Text(weather.locationName.isEmpty ? weather.conditionText : "\(weather.conditionText) · \(weather.locationName)")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AppTheme.textSecondary)
                                        .lineLimit(1)
                                } else {
                                    Text(weather.isRefreshing ? "Syncing GPS Weather…" : "Tap to Sync Local Weather")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(AppTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                
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
                        
                        // Centerpiece: Live Bike TFT Digital Homescreen Dome Preview (526×300 scaled, Zero Speedometer)
                        VStack(spacing: 10) {
                            TFTHomescreenCanvas(
                                heading: tracker.currentHeading,
                                weatherLoaded: weather.isLoaded,
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
                                isCharging: battery.isCharging,
                                isCallRinging: call.isRinging,
                                isCallOngoing: call.isOngoing,
                                callerName: call.callerName,
                                callDuration: call.formattedDuration,
                                showWeather: dashClient.showWeatherOnTFT,
                                showMusic: dashClient.showMusicOnTFT,
                                activeNavInstruction: dashClient.isNavigationActive ? dashClient.activeNavStreet : nil,
                                activeNavDistanceMeters: dashClient.isNavigationActive ? dashClient.activeNavDistanceMeters : nil,
                                forDashStream: false
                            )
                            .scaleEffect(0.64)
                            .frame(width: 526 * 0.64, height: 300 * 0.64)
                            .shadow(color: .black.opacity(0.6), radius: 20, y: 6)
                            
                            HStack(spacing: 10) {
                                Text(projection.isStreaming ? "Streaming to TFT · \(String(format: "%.1f", projection.currentFPS)) fps" : "Guerrilla 450 TFT Dome")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(projection.isStreaming ? AppTheme.emerald : AppTheme.textTertiary)
                                
                                #if canImport(PhotosUI)
                                PhotosPicker(selection: $cockpitWallpaperItem, matching: .images) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text(dashClient.hasCustomWallpaper ? "Wallpaper" : "Add Wallpaper")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .foregroundColor(AppTheme.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.surfaceElevated)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .onChange(of: cockpitWallpaperItem) { _, newItem in
                                    guard let newItem = newItem else { return }
                                    Task {
                                        if let data = try? await newItem.loadTransferable(type: Data.self) {
                                            dashClient.saveCustomWallpaperData(data)
                                        }
                                    }
                                }
                                #endif
                                
                                if dashClient.isNavigationActive {
                                    Button("End Nav") {
                                        NavigationEngine.shared.stopNavigation()
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(AppTheme.coral)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.surfaceElevated)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        
                        // Live Ride Telemetry Card (No Speedometer!)
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
                                        title: "Elevation",
                                        value: String(format: "%.0f", tracker.currentAltitude),
                                        unit: "m"
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
                                        value: weather.isLoaded ? "\(weather.windSpeedKmh)" : "—",
                                        unit: weather.isLoaded ? "km/h" : ""
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Refined Apple Music & Spotify Now Playing & Volume Card
                        GlassCard(padding: 16) {
                            VStack(spacing: 14) {
                                // Top bar: Music Provider Switcher (Spotify Primary!) + Link Button
                                HStack(spacing: 8) {
                                    ForEach(MusicProvider.allCases, id: \.self) { provider in
                                        let isSelected = (media.preferredProvider == provider)
                                        Button(action: {
                                            media.preferredProvider = provider
                                        }) {
                                            HStack(spacing: 5) {
                                                Circle()
                                                    .fill(provider == .spotify ? AppTheme.emerald : AppTheme.coral)
                                                    .frame(width: 6, height: 6)
                                                Text(provider.rawValue)
                                                    .font(.system(size: 11, weight: .semibold))
                                            }
                                            .foregroundColor(isSelected ? .black : AppTheme.textSecondary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(isSelected ? Color.white : AppTheme.surfaceElevated)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Spacer()
                                    
                                    if media.preferredProvider == .spotify {
                                        Button(action: { showingSpotifySheet = true }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: spotify.isConnected ? "checkmark.circle.fill" : "link.badge.plus")
                                                    .font(.system(size: 11, weight: .semibold))
                                                Text(spotify.isConnected ? "Spotify Linked" : "Link Spotify")
                                                    .font(.system(size: 11, weight: .semibold))
                                            }
                                            .foregroundColor(spotify.isConnected ? AppTheme.emerald : AppTheme.accent)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(AppTheme.surfaceElevated)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(AppTheme.surfaceElevated)
                                            .frame(width: 42, height: 42)
                                        Image(systemName: media.isPlaying ? "waveform" : "music.note")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(media.isPlaying ? (media.preferredProvider == .spotify ? AppTheme.emerald : AppTheme.accent) : AppTheme.textSecondary)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(media.currentTitle)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(AppTheme.textPrimary)
                                            .lineLimit(1)
                                        
                                        Text(media.currentArtist.isEmpty ? "\(media.preferredProvider.rawValue) · Handlebar Linked" : media.currentArtist)
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
            .sheet(isPresented: $showingSpotifySheet) {
                SpotifyConnectSheet()
            }
            .onAppear {
                weather.refresh(for: tracker.currentLocation)
                media.updateCurrentTrack(silentIfUnchanged: true)
            }
        }
    }
    
    private var dividerLine: some View {
        Rectangle()
            .fill(AppTheme.border)
            .frame(width: 0.6, height: 34)
            .padding(.horizontal, 12)
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

// MARK: - Spotify 1-Tap OAuth PKCE Connect Sheet
public struct SpotifyConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var spotify: SpotifyService = SpotifyService.shared
    @State private var copiedURI: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Status Banner
                        GlassCard {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(spotify.isConnected ? AppTheme.emerald : AppTheme.accent)
                                    .frame(width: 10, height: 10)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(spotify.isConnected ? "Spotify Connected" : "Connect Spotify for Live Track Titles & Skip")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(AppTheme.textPrimary)
                                    
                                    Text(spotify.isConnected ? "Live track metadata & handlebar Next/Prev/Play/Pause active in background." : "Enables background song titles and handlebar skip on iOS.")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                                Spacer()
                            }
                        }
                        
                        // Quick Setup Instructions + Client ID Field
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("1-Time Spotify Setup (30 Seconds)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("1. Open developer.spotify.com/dashboard and tap Create App.")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppTheme.textSecondary)
                                    
                                    HStack {
                                        Text("2. Paste Redirect URI: ")
                                            .font(.system(size: 12))
                                            .foregroundColor(AppTheme.textSecondary)
                                        Text(SpotifyService.redirectURI)
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundColor(AppTheme.emerald)
                                        Spacer()
                                        Button(copiedURI ? "Copied" : "Copy") {
                                            #if os(iOS)
                                            UIPasteboard.general.string = SpotifyService.redirectURI
                                            #endif
                                            copiedURI = true
                                        }
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(AppTheme.accent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(AppTheme.surfaceElevated)
                                        .clipShape(Capsule())
                                    }
                                    
                                    Text("3. Copy your Client ID and paste it below:")
                                        .font(.system(size: 12))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                                
                                TextField("Paste Spotify Client ID", text: $spotify.clientId)
                                    .font(.system(size: 14, design: .monospaced))
                                    .foregroundColor(.white)
                                    .autocorrectionDisabled()
                                    #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    #endif
                                    .padding(12)
                                    .background(AppTheme.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                
                                if !spotify.authStatusMessage.isEmpty {
                                    Text(spotify.authStatusMessage)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(spotify.isConnected ? AppTheme.emerald : AppTheme.accent)
                                }
                                
                                MinimalButton(
                                    title: spotify.isConnected ? "Reconnect Spotify" : "Authorize with Spotify",
                                    icon: "music.note.list",
                                    isProminent: true,
                                    tint: AppTheme.emerald
                                ) {
                                    spotify.startAuthorization()
                                }
                                
                                if spotify.isConnected {
                                    Button("Disconnect Spotify") {
                                        spotify.disconnect()
                                    }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.coral)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 4)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Spotify Integration")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(AppTheme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
