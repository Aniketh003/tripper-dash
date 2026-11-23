import SwiftUI

public struct SettingsView: View {
    @Bindable var firebase: FirebaseManager
    @Bindable var dashClient: TripperDashClient
    @Bindable var podClient: TripperPodClient
    
    @State private var showingEmailSignIn = false
    @State private var emailInput = ""
    @State private var ssidInput = ""
    @State private var ipInput = ""
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
                    VStack(spacing: 20) {
                        // Motorcycle Dash Hardware Connection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("BIKE DASH HARDWARE (ROYAL ENFIELD)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(AppTheme.textTertiary)
                                .padding(.horizontal, 20)
                            
                            GlassCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    // TFT Dash (Himalayan 450)
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Himalayan 450 TFT (Wi-Fi)")
                                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                    .foregroundColor(AppTheme.textPrimary)
                                                
                                                HStack(spacing: 6) {
                                                    Circle()
                                                        .fill(dashClient.connectionState == .connected ? AppTheme.emerald : (dashClient.connectionState == .disconnected ? AppTheme.textTertiary : AppTheme.accent))
                                                        .frame(width: 7, height: 7)
                                                    
                                                    Text(dashClient.connectionState.displayText)
                                                        .font(.system(size: 11, design: .monospaced))
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
                                                HStack(spacing: 4) {
                                                    if isConnecting(dashClient.connectionState) {
                                                        ProgressView().tint(.white).scaleEffect(0.8)
                                                    }
                                                    Text(buttonLabel(for: dashClient.connectionState))
                                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                                }
                                                .foregroundColor(dashClient.connectionState == .connected ? AppTheme.coral : .white)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 8)
                                                .background(dashClient.connectionState == .connected ? AppTheme.surfaceElevated : AppTheme.accent)
                                                .clipShape(Capsule())
                                            }
                                        }
                                        
                                        // SSID input field
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("DASH WI-FI SSID (From Bike Screen)")
                                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                                .foregroundColor(AppTheme.textTertiary)
                                            
                                            HStack {
                                                TextField("RE_450_XXXXXX", text: $ssidInput)
                                                    .font(.system(size: 13, design: .monospaced))
                                                    .foregroundColor(.white)
                                                    .autocorrectionDisabled()
                                                    .textInputAutocapitalization(.characters)
                                                    .onChange(of: ssidInput) { _, newValue in
                                                        dashClient.setDashSSID(newValue)
                                                    }
                                                
                                                if ssidInput != dashClient.dashSSID {
                                                    Button("Save") {
                                                        dashClient.setDashSSID(ssidInput)
                                                    }
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(AppTheme.accent)
                                                }
                                            }
                                            .padding(8)
                                            .background(AppTheme.surfaceElevated)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            
                                            Text("Look under: Menu > Appearance > Screen Type > Digital")
                                                .font(.system(size: 10, design: .rounded))
                                                .foregroundColor(AppTheme.textTertiary)
                                        }
                                        
                                        // Dash IP Host Field (Enables Local / Mac Testing)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("DASH IP ADDRESS (Default 192.168.1.1)")
                                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                                .foregroundColor(AppTheme.textTertiary)
                                            
                                            HStack {
                                                TextField("192.168.1.1", text: $ipInput)
                                                    .font(.system(size: 13, design: .monospaced))
                                                    .foregroundColor(.white)
                                                    .autocorrectionDisabled()
                                                    .textInputAutocapitalization(.never)
                                                    .onChange(of: ipInput) { _, newValue in
                                                        dashClient.setDashIP(newValue)
                                                    }
                                                
                                                if ipInput != dashClient.dashIP {
                                                    Button("Save") {
                                                        dashClient.setDashIP(ipInput)
                                                    }
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(AppTheme.accent)
                                                }
                                            }
                                            .padding(8)
                                            .background(AppTheme.surfaceElevated)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            
                                            HStack(spacing: 8) {
                                                Button("Bike Default (192.168.1.1)") {
                                                    ipInput = "192.168.1.1"
                                                    dashClient.setDashIP("192.168.1.1")
                                                }
                                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                                .foregroundColor(dashClient.dashIP == "192.168.1.1" ? AppTheme.accent : AppTheme.textTertiary)
                                                
                                                Spacer()
                                                
                                                Button("Simulator (127.0.0.1)") {
                                                    ipInput = "127.0.0.1"
                                                    dashClient.setDashIP("127.0.0.1")
                                                }
                                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                                .foregroundColor(dashClient.dashIP == "127.0.0.1" ? AppTheme.accent : AppTheme.textTertiary)
                                            }
                                        }
                                    }
                                    
                                    Divider().background(AppTheme.border)
                                    
                                    // Tripper Pod (BLE)
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Tripper Pod (Bluetooth)")
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                .foregroundColor(AppTheme.textPrimary)
                                            Text(podClient.statusMessage)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(AppTheme.textTertiary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            if podClient.isConnected {
                                                podClient.disconnect()
                                            } else {
                                                podClient.startScanning()
                                            }
                                        }) {
                                            Text(podClient.isConnected ? "Disconnect" : (podClient.isScanning ? "Scanning..." : "Scan BLE"))
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                                .foregroundColor(podClient.isConnected ? AppTheme.coral : AppTheme.accent)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(AppTheme.surfaceElevated)
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.top, 12)
                        
                        // Desk Testing & In-App Simulation Mode
                        VStack(alignment: .leading, spacing: 8) {
                            Text("LOCAL DESK TESTING & SIMULATION")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(AppTheme.textTertiary)
                                .padding(.horizontal, 20)
                            
                            GlassCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Simulate TFT Dash (No Bike Needed)")
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundColor(AppTheme.textPrimary)
                                            Text(dashClient.isMockMode ? "Mock Dash Active (Cockpit Unlocked)" : "Test navigation, music & calls indoors")
                                                .font(.system(size: 11, design: .rounded))
                                                .foregroundColor(dashClient.isMockMode ? AppTheme.emerald : AppTheme.textTertiary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            if dashClient.isMockMode {
                                                dashClient.disconnect()
                                            } else {
                                                dashClient.startMockConnection()
                                            }
                                        }) {
                                            Text(dashClient.isMockMode ? "Stop Sim" : "Start Sim")
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                                .foregroundColor(dashClient.isMockMode ? AppTheme.coral : .white)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 7)
                                                .background(dashClient.isMockMode ? AppTheme.surfaceElevated : AppTheme.emerald)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    
                                    if dashClient.connectionState == .connected {
                                        Divider().background(AppTheme.border)
                                        
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("HANDLEBAR JOYSTICK TEST BUTTONS")
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .foregroundColor(AppTheme.textTertiary)
                                            
                                            HStack(spacing: 8) {
                                                Button("⏮️ Left") {
                                                    dashClient.simulateJoystickPress(.left)
                                                }
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(AppTheme.surfaceElevated)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                
                                                Button("⏯️ Center") {
                                                    dashClient.simulateJoystickPress(.centerClick)
                                                }
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(AppTheme.surfaceElevated)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                
                                                Button("⏭️ Right") {
                                                    dashClient.simulateJoystickPress(.right)
                                                }
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(AppTheme.surfaceElevated)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                
                                                Button("📞 Down") {
                                                    dashClient.simulateJoystickPress(.down)
                                                }
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(AppTheme.surfaceElevated)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // Live Diagnostic Console
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("CONNECTION DIAGNOSTIC CONSOLE")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(AppTheme.textTertiary)
                                
                                Spacer()
                                
                                Button(action: { dashClient.clearLogs() }) {
                                    Text("Clear")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(AppTheme.textTertiary)
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                if dashClient.diagnosticLogs.isEmpty {
                                    Text("Tap 'Connect' to begin diagnostic check...")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(AppTheme.textTertiary)
                                        .padding(12)
                                } else {
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 3) {
                                            ForEach(dashClient.diagnosticLogs, id: \.self) { log in
                                                Text(log)
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundColor(logColor(for: log))
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                        .padding(10)
                                    }
                                    .frame(maxHeight: 180)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(AppTheme.border, lineWidth: 1)
                            )
                            .padding(.horizontal, 20)
                        }
                        
                        // Firebase Cloud Sync Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FIREBASE CLOUD SYNC")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(AppTheme.textTertiary)
                                .padding(.horizontal, 20)
                            
                            GlassCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "icloud.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(firebase.isConfigured ? AppTheme.accent : AppTheme.textTertiary)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(firebase.isSignedIn ? (firebase.userEmail ?? "Signed In") : "Cloud Backup & Sync")
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                .foregroundColor(AppTheme.textPrimary)
                                            
                                            Text(firebase.syncStatusMessage)
                                                .font(.system(size: 12, design: .rounded))
                                                .foregroundColor(AppTheme.textSecondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if firebase.isSignedIn {
                                            Button("Sign Out") {
                                                firebase.signOut()
                                            }
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppTheme.coral)
                                        } else {
                                            Button("Connect") {
                                                showingEmailSignIn = true
                                            }
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundColor(AppTheme.accent)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(AppTheme.surfaceElevated)
                                            .clipShape(Capsule())
                                        }
                                    }
                                    
                                    if firebase.isSignedIn {
                                        Divider().background(AppTheme.border)
                                        
                                        Button(action: {
                                            Task { await firebase.triggerSync() }
                                        }) {
                                            HStack {
                                                if firebase.isSyncing {
                                                    ProgressView().tint(AppTheme.accent)
                                                } else {
                                                    Image(systemName: "arrow.triangle.2.circlepath")
                                                }
                                                Text(firebase.isSyncing ? "Syncing..." : "Sync Cloud Now")
                                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            }
                                            .foregroundColor(AppTheme.accent)
                                        }
                                        .disabled(firebase.isSyncing)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // Preferences Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PREFERENCES")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(AppTheme.textTertiary)
                                .padding(.horizontal, 20)
                            
                            GlassCard {
                                VStack(spacing: 12) {
                                    HStack {
                                        Text("Currency Symbol")
                                            .font(.system(size: 14, design: .rounded))
                                            .foregroundColor(AppTheme.textPrimary)
                                        Spacer()
                                        Picker("Currency", selection: $currencySymbol) {
                                            Text("₹ INR").tag("₹")
                                            Text("$ USD").tag("$")
                                            Text("€ EUR").tag("€")
                                            Text("£ GBP").tag("£")
                                        }
                                        .pickerStyle(.menu)
                                        .tint(AppTheme.accent)
                                    }
                                    
                                    Divider().background(AppTheme.border)
                                    
                                    HStack {
                                        Text("Speed Units")
                                            .font(.system(size: 14, design: .rounded))
                                            .foregroundColor(AppTheme.textPrimary)
                                        Spacer()
                                        Picker("Unit", selection: $speedUnit) {
                                            Text("km/h").tag("km/h")
                                            Text("mph").tag("mph")
                                        }
                                        .pickerStyle(.menu)
                                        .tint(AppTheme.accent)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // About Section
                        VStack(spacing: 4) {
                            Text("TripperDash • Open Source Motorcycle Companion")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(AppTheme.textTertiary)
                            Text("Native Swift & SwiftUI • v1.0.0")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(AppTheme.textTertiary)
                        }
                        .padding(.top, 10)
                        
                        Spacer(minLength: 30)
                    }
                }
            }
            .navigationTitle("Settings & Sync")
            .alert("Connect Firebase", isPresented: $showingEmailSignIn) {
                TextField("Enter email address", text: $emailInput)
                Button("Sign In") {
                    if !emailInput.isEmpty {
                        firebase.signIn(email: emailInput) { _ in }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
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
        case .connected: return "Disconnect"
        case .verifyingNetwork, .requestingAuth, .exchangingKeys: return "Cancel"
        case .disconnected, .failed: return "Connect"
        }
    }
    
    private func logColor(for log: String) -> Color {
        if log.contains("❌") || log.contains("failed") {
            return AppTheme.coral
        } else if log.contains("⚠️") || log.contains("WARNING") {
            return AppTheme.accent
        } else if log.contains("🎉") || log.contains("SUCCESS") || log.contains("✅") {
            return AppTheme.emerald
        }
        return AppTheme.textSecondary
    }
}
