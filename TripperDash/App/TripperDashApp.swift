import SwiftUI

@main
struct TripperDashApp: App {
    @State private var appState = AppState()
    
    init() {
        // Configure dark OLED navigation and tab bar appearance
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1.0)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    }
    
    var body: some Scene {
        WindowGroup {
            TabView {
                CockpitView(
                    tracker: appState.tracker,
                    vehicleStore: appState.vehicleStore,
                    dashClient: appState.dashClient
                ) { newRide in
                    appState.database.saveRide(newRide)
                }
                .tabItem {
                    Label("Cockpit", systemImage: "speedometer")
                }
                
                GarageView(
                    vehicleStore: appState.vehicleStore,
                    db: appState.database
                )
                .tabItem {
                    Label("Garage", systemImage: "wrench.and.screwdriver")
                }
                
                ExpensesView(
                    db: appState.database,
                    vehicleStore: appState.vehicleStore
                )
                .tabItem {
                    Label("Expenses", systemImage: "fuelpump")
                }
                
                RoutePreviewView(
                    tracker: appState.tracker,
                    dashClient: appState.dashClient
                )
                .tabItem {
                    Label("Routes", systemImage: "map")
                }
                
                RidesHistoryView(
                    db: appState.database
                )
                .tabItem {
                    Label("Rides", systemImage: "road.lanes")
                }
                
                SettingsView(
                    firebase: appState.firebase,
                    dashClient: appState.dashClient,
                    podClient: appState.podClient
                )
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .tint(AppTheme.accent)
            .preferredColorScheme(.dark)
        }
    }
}
