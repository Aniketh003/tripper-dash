import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

public struct SettingsView: View {
    @Bindable var firebase: FirebaseManager
    @Bindable var dashClient: TripperDashClient
    @Bindable var podClient: TripperPodClient
    @Bindable var media: MediaPlaybackService = MediaPlaybackService.shared
    @Bindable var call: CallHandlingService = CallHandlingService.shared
    @Bindable var projection: TFTProjectionService = TFTProjectionService.shared
    
    @State private var showingEmailSignIn = false
    @State private var emailInput = ""
    @State private var ssidInput = ""
    @State private var ipInput = ""
    @State private var showDiagnostics = false
    @State private var pendingWallpaperCrop: WallpaperCropPayload? = nil
    #if canImport(PhotosUI)
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    #endif
    @AppStorage("pref_currency_symbol") private var currencySymbol = "₹"
    @AppStorage("pref_speed_unit") private var speedUnit = "km/h"
    
    public init(
        firebase: FirebaseManager,
        dashClient: TripperDashClient,
        podClient: TripperPodClient
    ) {
        self.firebase = firebase
        self.dashClient = dashClient
        self.podClient = podClient
        _ssidInput = State(initialValue: dashClient.dashSSID)
        _ipInput = State(initialValue: dashClient.dashIP)
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // 1. Royal Enfield TFT & Pod Hardware Connection
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("Motorcycle Hardware")
                                .padding(.horizontal, 24)
                            
                            GlassCard {
                                VStack(alignment: .leading, spacing: 16) {
                                    // TFT Dash Row
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("Guerrilla 450 TFT · Apex Black")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(AppTheme.textPrimary)
                                            
                                            HStack(spacing: 6) {
                                                Circle()
                                                    .fill(dashClient.connectionState == .connected ? AppTheme.emerald : (dashClient.connectionState == .disconnected ? AppTheme.textTertiary : AppTheme.accent))
                                                    .frame(width: 7, height: 7)
                                                Text(dashClient.connectionState.displayText)
                                                    .font(.system(size: 13))
                                                    .foregroundColor(dashClient.connectionState == .connected ? AppTheme.emerald : AppTheme.textSecondary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            if dashClient.connectionState == .connected {
                                                dashClient.disconnect()
                                            } else if dashClient.connectionState == .disconnected || isFailed(dashClient.connectionState) {
                                                dashClient.connect()
                                            } else {
                                                dashClient.disconnect()
                                            }
                                        }) {
                                            HStack(spacing: 5) {
                                                if isConnecting(dashClient.connectionState) {
                                                    ProgressView().tint(.black).scaleEffect(0.75)
                                                }
                                                Text(buttonLabel(for: dashClient.connectionState))
                                                    .font(.system(size: 13, weight: .semibold))
                                            }
                                            .foregroundColor(dashClient.connectionState == .connected ? AppTheme.coral : .black)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(dashClient.connectionState == .connected ? AppTheme.surfaceElevated : AppTheme.accent)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Divider().background(AppTheme.border)
                                    
                                    // SSID Input
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Dash Wi-Fi SSID")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(AppTheme.textSecondary)
                                        
                                        TextField("RE_450_XXXXXX", text: $ssidInput)
                                            .font(.system(size: 14, design: .monospaced))
                                            .foregroundColor(.white)
                                            .autocorrectionDisabled()
                                            #if os(iOS)
                                            .textInputAutocapitalization(.characters)
                                            #endif
                                            .onChange(of: ssidInput) { _, newValue in
                                                dashClient.setDashSSID(newValue)
                                            }
                                            .padding(11)
                                            .background(AppTheme.surfaceElevated)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    
                                    // Dash Host IP Input
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Dash Host IP")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(AppTheme.textSecondary)
                                        
                                        TextField("192.168.1.1", text: $ipInput)
                                            .font(.system(size: 14, design: .monospaced))
                                            .foregroundColor(.white)
                                            .autocorrectionDisabled()
                                            #if os(iOS)
                                            .textInputAutocapitalization(.never)
                                            #endif
                                            .onChange(of: ipInput) { _, newValue in
                                                dashClient.setDashIP(newValue)
                                            }
                                            .padding(11)
                                            .background(AppTheme.surfaceElevated)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        
                                        HStack(spacing: 8) {
                                            // 1-Tap Bike Preset: Sets BOTH RE_RLK8_260813 SSID & 192.168.1.1 IP (+ 192.168.1.255 broadcast)
                                            Button(action: {
                                                ssidInput = TripperDashClient.defaultBikeSSID
                                                ipInput = TripperDashClient.defaultBikeIP
                                                dashClient.setDashSSID(TripperDashClient.defaultBikeSSID)
                                                dashClient.setDashIP(TripperDashClient.defaultBikeIP)
                                            }) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "motorcycle.fill")
                                                        .font(.system(size: 10))
                                                    Text("Bike (RE_RLK8_260813)")
                                                        .font(.system(size: 11, weight: .semibold))
                                                }
                                                .foregroundColor(dashClient.dashIP == "192.168.1.1" && dashClient.dashSSID == "RE_RLK8_260813" ? .black : AppTheme.textPrimary)
                                                .padding(.horizontal, 11)
                                                .padding(.vertical, 7)
                                                .background(dashClient.dashIP == "192.168.1.1" && dashClient.dashSSID == "RE_RLK8_260813" ? AppTheme.accent : AppTheme.surfaceElevated)
                                                .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                            
                                            // 1-Tap Local Mac Wi-Fi Preset: Sets BOTH Host IP (192.168.0.9) & Broadcast IP (192.168.0.255)
                                            Button(action: {
                                                ssidInput = TripperDashClient.defaultBikeSSID
                                                ipInput = TripperDashClient.defaultLocalMacIP
                                                dashClient.setDashSSID(TripperDashClient.defaultBikeSSID)
                                                dashClient.setDashIP(TripperDashClient.defaultLocalMacIP)
                                            }) {
                                                HStack(spacing: 4) {
                                                    Image(systemName: "laptopcomputer")
                                                        .font(.system(size: 10))
                                                    Text("Local (\(TripperDashClient.defaultLocalMacIP))")
                                                        .font(.system(size: 11, weight: .semibold))
                                                }
                                                .foregroundColor(dashClient.dashIP == TripperDashClient.defaultLocalMacIP ? .black : AppTheme.textPrimary)
                                                .padding(.horizontal, 11)
                                                .padding(.vertical, 7)
                                                .background(dashClient.dashIP == TripperDashClient.defaultLocalMacIP ? AppTheme.emerald : AppTheme.surfaceElevated)
                                                .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                            
                                            Spacer()
                                            
                                            Button("127.0.0.1") {
                                                ipInput = "127.0.0.1"
                                                dashClient.setDashIP("127.0.0.1")
                                            }
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(dashClient.dashIP == "127.0.0.1" ? AppTheme.accent : AppTheme.textTertiary)
                                        }
                                        .padding(.top, 4)
                                        
                                        Text("Active Target: \(dashClient.dashIP) · Broadcast: \(dashClient.broadcastIP)")
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(AppTheme.textTertiary)
                                            .padding(.top, 2)
                                    }
                                    
                                    Divider().background(AppTheme.border)
                                    
                                    // Tripper Pod BLE Row
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Tripper Pod (BLE)")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(AppTheme.textPrimary)
                                            Text(podClient.statusMessage)
                                                .font(.system(size: 12))
                                                .foregroundColor(AppTheme.textSecondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            if podClient.isConnected {
                                                podClient.disconnect()
                                            } else {
                                                podClient.startScanning()
                                            }
                                        }) {
                                            Text(podClient.isConnected ? "Disconnect" : (podClient.isScanning ? "Scanning…" : "Scan"))
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(podClient.isConnected ? AppTheme.coral : AppTheme.accent)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 7)
                                                .background(AppTheme.surfaceElevated)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.top, 8)
                        
                        // 2. Bike TFT Digital Homescreen Customization
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("TFT Digital Homescreen")
                                .padding(.horizontal, 24)
                            
                            GlassCard {
                                VStack(spacing: 14) {
                                    Toggle(isOn: $dashClient.showWeatherOnTFT) {
                                        Label("Live Weather & Temp", systemImage: "cloud.sun.fill")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(AppTheme.textPrimary)
                                    }
                                    .tint(AppTheme.accent)
                                    
                                    Divider().background(AppTheme.border)
                                    
                                    Toggle(isOn: $dashClient.showMusicOnTFT) {
                                        Label("Now Playing & Volume", systemImage: "music.note")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(AppTheme.textPrimary)
                                    }
                                    .tint(AppTheme.accent)
                                    
                                    Divider().background(AppTheme.border)
                                    
                                    Toggle(isOn: $dashClient.enableVideoProjection) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Label("H.264 TFT Video Stream", systemImage: "display")
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(AppTheme.textPrimary)
                                            Text(projection.isStreaming ? "Active · \(String(format: "%.1f", projection.currentFPS)) fps on UDP/5000" : "Projects 526×300 Digital Homescreen dome to bike cluster")
                                                .font(.system(size: 12))
                                                .foregroundColor(projection.isStreaming ? AppTheme.emerald : AppTheme.textSecondary)
                                        }
                                    }
                                    .tint(AppTheme.accent)
                                    
                                    Divider().background(AppTheme.border)
                                    
                                    // Homescreen Wallpaper Customization (Themes + Custom Photo Library Picker)
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Label("Homescreen Wallpaper", systemImage: "photo.on.rectangle.angled")
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(AppTheme.textPrimary)
                                            Spacer()
                                            Text(dashClient.wallpaperStyle.rawValue)
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(AppTheme.accent)
                                        }
                                        
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach(TFTWallpaperStyle.allCases, id: \.self) { style in
                                                    if style != .customPhoto || dashClient.hasCustomWallpaper {
                                                        PillBadge(
                                                            text: style.rawValue,
                                                            isSelected: dashClient.wallpaperStyle == style
                                                        ) {
                                                            dashClient.wallpaperStyle = style
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        
                                        #if canImport(PhotosUI)
                                        HStack(spacing: 10) {
                                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "photo.badge.plus")
                                                        .font(.system(size: 13, weight: .semibold))
                                                    Text(dashClient.hasCustomWallpaper ? "Change Photo" : "Add Wallpaper from Photos")
                                                        .font(.system(size: 13, weight: .semibold))
                                                }
                                                .foregroundColor(.black)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 10)
                                                .background(AppTheme.accent)
                                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                            }
                                            .buttonStyle(.plain)
                                            .onChange(of: selectedPhotoItem) { _, newItem in
                                                guard let newItem = newItem else { return }
                                                Task {
                                                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                                                        await MainActor.run {
                                                            pendingWallpaperCrop = WallpaperCropPayload(data: data)
                                                            selectedPhotoItem = nil
                                                        }
                                                    }
                                                }
                                            }
                                            
                                            if dashClient.hasCustomWallpaper {
                                                Button(action: {
                                                    if let data = dashClient.loadEditableWallpaperData() {
                                                        pendingWallpaperCrop = WallpaperCropPayload(data: data)
                                                    }
                                                }) {
                                                    HStack(spacing: 5) {
                                                        Image(systemName: "crop")
                                                            .font(.system(size: 13, weight: .semibold))
                                                        Text("Crop")
                                                            .font(.system(size: 13, weight: .semibold))
                                                    }
                                                    .foregroundColor(AppTheme.textPrimary)
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 10)
                                                    .background(AppTheme.surfaceElevated)
                                                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                                }
                                                .buttonStyle(.plain)
                                                
                                                Button(action: { dashClient.clearCustomWallpaper() }) {
                                                    Image(systemName: "trash")
                                                        .font(.system(size: 13, weight: .semibold))
                                                        .foregroundColor(AppTheme.coral)
                                                        .padding(10)
                                                        .background(AppTheme.surfaceElevated)
                                                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        #endif
                                        
                                        if dashClient.wallpaperStyle != .pureBlack {
                                            HStack(spacing: 10) {
                                                Text("Dimming")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(AppTheme.textSecondary)
                                                Slider(value: $dashClient.wallpaperDimming, in: 0.15...0.85)
                                                    .tint(AppTheme.accent)
                                                Text("\(Int(dashClient.wallpaperDimming * 100))%")
                                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                    .monospacedDigit()
                                                    .foregroundColor(AppTheme.textTertiary)
                                                    .frame(width: 34, alignment: .trailing)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // 3. Desk Testing & Handlebar Simulator
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("Desk Testing Lab")
                                .padding(.horizontal, 24)
                            
                            GlassCard {
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Simulate Bike Dash")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(AppTheme.textPrimary)
                                            Text(dashClient.isMockMode ? "Simulation connected" : "Test controls without bike or Mac")
                                                .font(.system(size: 12))
                                                .foregroundColor(dashClient.isMockMode ? AppTheme.emerald : AppTheme.textSecondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            if dashClient.isMockMode {
                                                dashClient.disconnect()
                                            } else {
                                                dashClient.startMockConnection()
                                            }
                                        }) {
                                            Text(dashClient.isMockMode ? "Stop" : "Start")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(dashClient.isMockMode ? AppTheme.coral : .black)
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 7)
                                                .background(dashClient.isMockMode ? AppTheme.surfaceElevated : AppTheme.emerald)
                                                .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Divider().background(AppTheme.border)
                                    
                                    // Direct Test Controls (Work anytime!)
                                    VStack(spacing: 10) {
                                        HStack(spacing: 8) {
                                            testPill(icon: "backward.fill", label: "Prev") {
                                                dashClient.simulateJoystickPress(.left)
                                            }
                                            testPill(icon: "playpause.fill", label: "Center") {
                                                dashClient.simulateJoystickPress(.centerClick)
                                            }
                                            testPill(icon: "forward.fill", label: "Next") {
                                                dashClient.simulateJoystickPress(.right)
                                            }
                                        }
                                        
                                        HStack(spacing: 8) {
                                            testPill(icon: "speaker.plus.fill", label: "Vol +") {
                                                dashClient.simulateJoystickPress(.up)
                                            }
                                            testPill(icon: "speaker.minus.fill", label: "Vol −") {
                                                dashClient.simulateJoystickPress(.down)
                                            }
                                            testPill(icon: "phone.arrow.down.left.fill", label: call.isRinging || call.isOngoing ? "Drop" : "Ring Call", tint: call.isRinging || call.isOngoing ? AppTheme.coral : AppTheme.emerald) {
                                                if call.isRinging || call.isOngoing {
                                                    call.endOrRejectCall()
                                                } else {
                                                    call.simulateIncomingCall(caller: "Royal Enfield Rider")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // 4. Units & Cloud Sync
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("Preferences & Sync")
                                .padding(.horizontal, 24)
                            
                            GlassCard {
                                VStack(spacing: 14) {
                                    HStack {
                                        Text("Currency")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(AppTheme.textPrimary)
                                        Spacer()
                                        Picker("Currency", selection: $currencySymbol) {
                                            Text("₹").tag("₹")
                                            Text("$").tag("$")
                                            Text("€").tag("€")
                                            Text("£").tag("£")
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(width: 160)
                                    }
                                    
                                    Divider().background(AppTheme.border)
                                    
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(firebase.isSignedIn ? (firebase.userEmail ?? "Signed In") : "Cloud Sync")
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(AppTheme.textPrimary)
                                            Text(firebase.isSignedIn ? "Synced" : "Sign in to back up rides")
                                                .font(.system(size: 12))
                                                .foregroundColor(AppTheme.textSecondary)
                                        }
                                        Spacer()
                                        Button(firebase.isSignedIn ? "Sign Out" : "Sign In") {
                                            if firebase.isSignedIn {
                                                firebase.signOut()
                                            } else {
                                                showingEmailSignIn = true
                                            }
                                        }
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(firebase.isSignedIn ? AppTheme.coral : AppTheme.accent)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // 5. Collapsible Diagnostic Console (Keeps Settings ultra-clean!)
                        VStack(alignment: .leading, spacing: 10) {
                            GlassCard(padding: 14) {
                                DisclosureGroup(isExpanded: $showDiagnostics) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("\(dashClient.diagnosticLogs.count) events")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(AppTheme.textTertiary)
                                            Spacer()
                                            Button("Clear") { dashClient.clearLogs() }
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(AppTheme.accent)
                                        }
                                        .padding(.top, 8)
                                        
                                        ScrollView {
                                            VStack(alignment: .leading, spacing: 4) {
                                                if dashClient.diagnosticLogs.isEmpty {
                                                    Text("No events yet.")
                                                        .font(.system(size: 11, design: .monospaced))
                                                        .foregroundColor(AppTheme.textTertiary)
                                                } else {
                                                    ForEach(dashClient.diagnosticLogs, id: \.self) { entry in
                                                        Text(entry)
                                                            .font(.system(size: 11, design: .monospaced))
                                                            .foregroundColor(logColor(for: entry))
                                                            .frame(maxWidth: .infinity, alignment: .leading)
                                                    }
                                                }
                                            }
                                        }
                                        .frame(maxHeight: 170)
                                    }
                                } label: {
                                    Label("Connection Diagnostics", systemImage: "terminal")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                                .tint(AppTheme.textTertiary)
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer(minLength: 32)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(item: $pendingWallpaperCrop) { payload in
                TFTWallpaperCropperSheet(rawImageData: payload.data)
            }
            .alert("Sign In", isPresented: $showingEmailSignIn) {
                TextField("Email address", text: $emailInput)
                    .keyboardType(.emailAddress)
                Button("Continue") {
                    if !emailInput.isEmpty {
                        firebase.signIn(email: emailInput) { _ in }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
    
    private func testPill(icon: String, label: String, tint: Color = AppTheme.textPrimary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    private func isConnecting(_ state: DashConnectionState) -> Bool {
        state == .verifyingNetwork || state == .requestingAuth || state == .exchangingKeys
    }
    
    private func isFailed(_ state: DashConnectionState) -> Bool {
        if case .failed = state { return true }
        return false
    }
    
    private func buttonLabel(for state: DashConnectionState) -> String {
        switch state {
        case .disconnected: return "Connect"
        case .connected: return "Disconnect"
        case .failed: return "Retry"
        default: return "Cancel"
        }
    }
    
    private func logColor(for entry: String) -> Color {
        if entry.contains("❌") || entry.contains("Failed") { return AppTheme.coral }
        if entry.contains("✅") || entry.contains("🎉") { return AppTheme.emerald }
        if entry.contains("⚠️") || entry.contains("👉") { return AppTheme.accent }
        return AppTheme.textSecondary
    }
}
