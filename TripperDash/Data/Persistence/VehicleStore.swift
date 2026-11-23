import Foundation

@Observable
public final class VehicleStore: @unchecked Sendable {
    public static let shared = VehicleStore()
    
    public var vehicles: [VehicleProfile] = []
    public var activeVehicleId: String = "default"
    public var lastDashSyncDate: Date? = nil
    public var dashFirmwareVersion: String = "Tripper Dash K1G"
    
    private let prefsKeyVehicles = "opendash_vehicles"
    private let prefsKeyActiveId = "opendash_active_vehicle"
    
    public var activeVehicle: VehicleProfile {
        vehicles.first { $0.id == activeVehicleId } ?? vehicles.first ?? defaultVehicle
    }
    
    /// Royal Enfield Guerrilla 450 (Apex Black) — Official Factory Specifications & Service Intervals
    /// - 1st Break-in Service: 500 km (or 45 days)
    /// - Periodic Service: Every 5,000 km (or 6 months): 5,000 km, 10,000 km, 15,000 km, etc.
    public var nextServiceTargetKm: Double {
        let odo = activeVehicle.currentOdometer
        if odo < 500.0 {
            return 500.0 // Break-in service milestone
        }
        let interval = 5000.0
        return ceil(max(odo + 1.0, 5000.0) / interval) * interval
    }
    
    public var nextServiceRemainingKm: Double {
        max(0.0, nextServiceTargetKm - activeVehicle.currentOdometer)
    }
    
    public var nextServiceMilestoneLabel: String {
        if activeVehicle.currentOdometer < 500.0 {
            return "1st Break-In Service (500 km)"
        }
        return String(format: "%.0f km Periodic Service", nextServiceTargetKm)
    }
    
    private var defaultVehicle: VehicleProfile {
        VehicleProfile(
            id: "default",
            title: "Guerrilla 450",
            nickname: "Apex Black",
            puc: "Valid",
            insurance: "Valid",
            service: "Due at 5,000 km",
            currentOdometer: 1420.0,
            engineSpec: "452 cc Sherpa 450 · Liquid-Cooled DOHC",
            powerTorqueSpec: "40 PS @ 8,000 rpm · 40 Nm @ 5,500 rpm",
            fuelCapacityLiters: 11.0,
            tirePressureFrontRearPSI: "29 PSI Front · 33 PSI Rear",
            dashSSID: "RE_RLK8_260813"
        )
    }
    
    private init() {
        loadProfiles()
    }
    
    public func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: prefsKeyVehicles),
           var decoded = try? JSONDecoder().decode([VehicleProfile].self, from: data),
           !decoded.isEmpty {
            // Auto-migrate legacy default Himalayan 450 placeholder to Guerrilla 450 Apex Black
            var didMigrate = false
            for i in decoded.indices {
                if decoded[i].title == "Himalayan 450" || decoded[i].nickname == "Default vehicle" || decoded[i].nickname == "Primary Steed" {
                    decoded[i].title = "Guerrilla 450"
                    decoded[i].nickname = "Apex Black"
                    decoded[i].dashSSID = "RE_RLK8_260813"
                    didMigrate = true
                }
            }
            self.vehicles = decoded
            if didMigrate {
                saveProfiles()
            }
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
        DispatchQueue.main.async {
            guard let index = self.vehicles.firstIndex(where: { $0.id == self.activeVehicleId }) else { return }
            self.vehicles[index].currentOdometer = max(0.0, km)
            self.vehicles[index].service = String(format: "Due in %.0f km", self.nextServiceRemainingKm)
            self.lastDashSyncDate = Date()
            self.saveProfiles()
        }
    }
    
    /// Automatically increments the active motorcycle's odometer as live GPS distance is covered while linked to the bike
    public func incrementOdometerLive(deltaMeters: Double) {
        guard deltaMeters > 0 else { return }
        let deltaKm = deltaMeters / 1000.0
        DispatchQueue.main.async {
            guard let index = self.vehicles.firstIndex(where: { $0.id == self.activeVehicleId }) else { return }
            self.vehicles[index].currentOdometer += deltaKm
            self.vehicles[index].service = String(format: "Due in %.0f km", self.nextServiceRemainingKm)
            self.lastDashSyncDate = Date()
            self.saveProfiles()
        }
    }
    
    public func deleteVehicle(id: String) {
        guard vehicles.count > 1 else { return }
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
