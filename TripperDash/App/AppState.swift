import SwiftUI

@Observable
public final class AppState: @unchecked Sendable {
    public let tracker = LocationTracker()
    public let vehicleStore = VehicleStore.shared
    public let database = DatabaseService.shared
    public let firebase = FirebaseManager.shared
    public let dashClient = TripperDashClient.shared
    public let podClient = TripperPodClient.shared
    
    public init() {
        tracker.requestPermissions()
        tracker.startLiveTracking()
    }
}
