import SwiftUI

@main
struct TripperDashApp: App {
    @State private var appState = AppState()
    
    init() {
        #if os(iOS)
        // Refined translucent OLED Tab & Navigation Bar (Apple HIG)
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        tabAppearance.backgroundColor = UIColor.black.withAlphaComponent(0.92)
        tabAppearance.shadowColor = UIColor.white.withAlphaComponent(0.08)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        navAppearance.backgroundColor = UIColor.black.withAlphaComponent(0.92)
        navAppearance.shadowColor = .clear
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                // Permanently mounted invisible system volume bridge so joystick Up/Down
                // adjusts real iOS media volume reliably from ANY tab
                SystemVolumeBridge()
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                
                // Clean 5-Tab Apple HIG Architecture (no overflow "More" tab)
                TabView {
                    CockpitView(
                        tracker: appState.tracker,
                        vehicleStore: appState.vehicleStore,
                        dashClient: appState.dashClient
                    ) { newRide in
                        appState.database.saveRide(newRide)
                    }
                    .tabItem {
                        Label("Cockpit", systemImage: "gauge.with.dots.needle.67percent")
                    }
                    
                    RoutePreviewView(
                        tracker: appState.tracker,
                        dashClient: appState.dashClient
                    )
                    .tabItem {
                        Label("Navigate", systemImage: "location.north.fill")
                    }
                    
                    LogbookView(
                        db: appState.database,
                        vehicleStore: appState.vehicleStore
                    )
                    .tabItem {
                        Label("Logbook", systemImage: "road.lanes")
                    }
                    
                    GarageView(
                        vehicleStore: appState.vehicleStore,
                        db: appState.database
                    )
                    .tabItem {
                        Label("Garage", systemImage: "wrench.and.screwdriver")
                    }
                    
                    SettingsView(
                        firebase: appState.firebase,
                        dashClient: appState.dashClient,
                        podClient: appState.podClient
                    )
                    .tabItem {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                }
                .tint(AppTheme.accent)
                .preferredColorScheme(.dark)
                
                // Global Apple Dynamic Island-style Live Overlays (Calls & Volume HUD)
                GlobalLiveHUD(call: appState.call, media: appState.media)
            }
            .onOpenURL { url in
                SpotifyService.shared.handleCallbackURL(url)
            }
        }
    }
}

// MARK: - Unified Logbook Tab (Rides + Expenses with Apple Segmented Control)
public struct LogbookView: View {
    @Bindable var db: DatabaseService
    @Bindable var vehicleStore: VehicleStore
    @State private var selectedSection: Int = 0
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Picker("Logbook", selection: $selectedSection) {
                        Text("Rides").tag(0)
                        Text("Expenses").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    
                    if selectedSection == 0 {
                        RidesHistoryView(db: db, embedded: true)
                    } else {
                        ExpensesView(db: db, vehicleStore: vehicleStore, embedded: true)
                    }
                }
            }
            .navigationTitle("Logbook")
        }
    }
}

// MARK: - Global Floating Apple Dynamic Island-Style HUD (Incoming Calls + Volume)
private struct GlobalLiveHUD: View {
    @Bindable var call: CallHandlingService
    @Bindable var media: MediaPlaybackService
    
    var body: some View {
        VStack(spacing: 10) {
            // 1. Incoming / Ongoing Call Banner (Visible across every tab!)
            if call.isRinging || call.isOngoing {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill((call.isRinging ? AppTheme.emerald : AppTheme.accent).opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: call.isRinging ? "phone.down.waves.left.and.right" : "phone.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(call.isRinging ? AppTheme.emerald : AppTheme.accent)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(call.callerName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            Text(call.isRinging ? "Incoming · ↑/● Answer · ↓ Drop" : call.formattedDuration)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(call.isOngoing ? AppTheme.emerald : AppTheme.textSecondary)
                        }
                    }
                    
                    Spacer()
                    
                    if call.isRinging {
                        Button(action: { call.answerCall() }) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 38, height: 38)
                                .background(AppTheme.emerald)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: { call.endOrRejectCall() }) {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(AppTheme.coral)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.65))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppTheme.borderSpecular, lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
                .padding(.horizontal, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // 2. Sleek System Volume HUD Pill (Appears when handlebar joystick Up/Down changes volume)
            if media.showVolumeHUD {
                HStack(spacing: 12) {
                    Image(systemName: media.volumePercent == 0 ? "speaker.slash.fill" : (media.volumePercent < 40 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 20)
                    
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.18))
                            Capsule()
                                .fill(Color.white)
                                .frame(width: max(6, geo.size.width * CGFloat(media.volumePercent) / 100.0))
                        }
                    }
                    .frame(width: 120, height: 5)
                    
                    Text("\(media.volumePercent)%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(AppTheme.textSecondary)
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .background(Color.black.opacity(0.7))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppTheme.borderSpecular, lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.5), radius: 14, y: 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 6)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: call.isRinging)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: call.isOngoing)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: media.showVolumeHUD)
    }
}
