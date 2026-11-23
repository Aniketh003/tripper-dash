import Foundation

@Observable
public final class VehicleStore: @unchecked Sendable {
    public static let shared = VehicleStore()
    
    public var vehicles: [VehicleProfile] = []
    public var activeVehicleId: String = "default"
    
    private let prefsKeyVehicles = "opendash_vehicles"
    private let prefsKeyActiveId = "opendash_active_vehicle"
    
    public var activeVehicle: VehicleProfile {
        vehicles.first { $0.id == activeVehicleId } ?? vehicles.first ?? defaultVehicle
    }
    
    private var defaultVehicle: VehicleProfile {
        VehicleProfile(
            id: "default",
            title: "Himalayan 450",
            nickname: "Default vehicle",
            puc: "Valid",
            insurance: "Valid",
            service: "Due in 3,500 km",
            currentOdometer: 1420.0
        )
    }
    
    private init() {
        loadProfiles()
    }
    
    public func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: prefsKeyVehicles),
           let decoded = try? JSONDecoder().decode([VehicleProfile].self, from: data),
           !decoded.isEmpty {
            self.vehicles = decoded
        } else {
            self.vehicles = [defaultVehicle]
            saveProfiles()
        }
        
        self.activeVehicleId = UserDefaults.standard.string(forKey: prefsKeyActiveId) ?? "default"
    }
    
    public func setActiveVehicle(id: String) {
        guard vehicles.contains(where: { $0.id == id }) else { return }
        self.activeVehicleId = id
        UserDefaults.standard.set(id, forKey: prefsKeyActiveId)
    }
    
    public func addOrUpdateVehicle(_ vehicle: VehicleProfile) {
        if let index = vehicles.firstIndex(where: { $0.id == vehicle.id }) {
            vehicles[index] = vehicle
        } else {
            vehicles.append(vehicle)
        }
        saveProfiles()
    }
    
    public func updateOdometer(km: Double) {
        guard let index = vehicles.firstIndex(where: { $0.id == activeVehicleId }) else { return }
        vehicles[index].currentOdometer = km
        saveProfiles()
    }
    
    public func deleteVehicle(id: String) {
        guard vehicles.count > 1 else { return } // Keep at least one
        vehicles.removeAll { $0.id == id }
        if activeVehicleId == id {
            activeVehicleId = vehicles.first?.id ?? "default"
            UserDefaults.standard.set(activeVehicleId, forKey: prefsKeyActiveId)
        }
        saveProfiles()
    }
    
    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(vehicles) {
            UserDefaults.standard.set(encoded, forKey: prefsKeyVehicles)
        }
    }
}
