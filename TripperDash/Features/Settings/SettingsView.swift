import SwiftUI

public struct SettingsView: View {
    @Bindable var firebase: FirebaseManager
    @Bindable var dashClient: TripperDashClient
    @Bindable var podClient: TripperPodClient
    
    @State private var showingEmailSignIn = false
    @State private var emailInput = ""
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
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
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
                        .padding(.top, 12)
                        
                        // Motorcycle Dash Hardware Connection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("BIKE DASH HARDWARE (ROYAL ENFIELD)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(AppTheme.textTertiary)
                                .padding(.horizontal, 20)
                            
                            GlassCard {
                                VStack(alignment: .leading, spacing: 14) {
                                    // TFT Dash (Himalayan 450)
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Himalayan 450 TFT (Wi-Fi)")
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                .foregroundColor(AppTheme.textPrimary)
                                            Text("Direct UDP/K1G Connection (\(dashClient.dashIP))")
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(AppTheme.textTertiary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            if dashClient.connectionState == .connected {
                                                dashClient.disconnect()
                                            } else {
                                                dashClient.connect()
                                            }
                                        }) {
                                            Text(dashClient.connectionState == .connected ? "Disconnect" : "Connect")
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                                .foregroundColor(dashClient.connectionState == .connected ? AppTheme.coral : AppTheme.accent)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(AppTheme.surfaceElevated)
                                                .clipShape(Capsule())
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
}
