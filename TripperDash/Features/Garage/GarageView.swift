import SwiftUI

public struct GarageView: View {
    @Bindable var vehicleStore: VehicleStore
    @Bindable var db: DatabaseService
    
    @State private var showingAddLog = false
    @State private var showingOdoEdit = false
    @State private var newOdoText = ""
    
    public init(vehicleStore: VehicleStore, db: DatabaseService) {
        self.vehicleStore = vehicleStore
        self.db = db
    }
    
    private var activeVehicleLogs: [GarageLogEntry] {
        db.garageLogs.filter { $0.vehicleId == vehicleStore.activeVehicleId }
    }
    
    private var nextServiceRemainingKm: Double {
        let current = vehicleStore.activeVehicle.currentOdometer
        let interval = 5000.0
        let nextTarget = ceil(max(current + 1, 1) / interval) * interval
        return max(0, nextTarget - current)
    }
    
    private var serviceProgress: Double {
        let used = 5000.0 - nextServiceRemainingKm
        return min(max(used / 5000.0, 0.0), 1.0)
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Clean Bike Identity Showcase Card
                        GlassCard {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(vehicleStore.activeVehicle.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(AppTheme.accent)
                                        
                                        Text(vehicleStore.activeVehicle.nickname)
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundColor(AppTheme.textPrimary)
                                    }
                                    
                                    Spacer()
                                    
                                    ZStack {
                                        Circle()
                                            .fill(AppTheme.surfaceElevated)
                                            .frame(width: 48, height: 48)
                                        Image(systemName: "bicycle")
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(AppTheme.textSecondary)
                                    }
                                }
                                
                                Divider().background(AppTheme.border)
                                
                                HStack(spacing: 8) {
                                    Button(action: {
                                        newOdoText = String(format: "%.0f", vehicleStore.activeVehicle.currentOdometer)
                                        showingOdoEdit = true
                                    }) {
                                        HStack(spacing: 5) {
                                            Text(String(format: "%.0f km", vehicleStore.activeVehicle.currentOdometer))
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .monospacedDigit()
                                                .foregroundColor(AppTheme.textPrimary)
                                            Image(systemName: "pencil")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(AppTheme.textTertiary)
                                        }
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 6)
                                        .background(AppTheme.surfaceElevated)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Text("PUC · \(vehicleStore.activeVehicle.puc)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.emerald)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(AppTheme.emerald.opacity(0.14))
                                        .clipShape(Capsule())
                                    
                                    Text("INS · \(vehicleStore.activeVehicle.insurance)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(AppTheme.emerald)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(AppTheme.emerald.opacity(0.14))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        
                        // Service Interval Progress Card
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Next Service")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(AppTheme.textSecondary)
                                    Spacer()
                                    Text(String(format: "%.0f km left", nextServiceRemainingKm))
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundColor(AppTheme.accent)
                                }
                                
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.08))
                                        Capsule()
                                            .fill(AppTheme.accent)
                                            .frame(width: max(8, geo.size.width * serviceProgress))
                                    }
                                }
                                .frame(height: 6)
                                
                                Text("5,000 km scheduled maintenance cycle")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Maintenance Log Header
                        HStack {
                            Text("Maintenance Log")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.textSecondary)
                            
                            Spacer()
                            
                            Button(action: { showingAddLog = true }) {
                                Label("Add Record", systemImage: "plus")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppTheme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 24)
                        
                        if activeVehicleLogs.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundColor(AppTheme.textTertiary)
                                Text("No service records yet")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(AppTheme.textPrimary)
                                Text("Log oil changes, chain maintenance, and inspections.")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 44)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(activeVehicleLogs) { log in
                                    GlassCard(cornerRadius: 16, padding: 15) {
                                        HStack(alignment: .top) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(log.title)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundColor(AppTheme.textPrimary)
                                                
                                                Text("\(String(format: "%.0f", log.odometerKm)) km · \(log.type.rawValue)")
                                                    .font(.system(size: 12, design: .rounded))
                                                    .monospacedDigit()
                                                    .foregroundColor(AppTheme.textSecondary)
                                                
                                                if !log.notes.isEmpty {
                                                    Text(log.notes)
                                                        .font(.system(size: 12))
                                                        .foregroundColor(AppTheme.textTertiary)
                                                        .padding(.top, 2)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            if log.cost > 0 {
                                                Text(String(format: "₹%.0f", log.cost))
                                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                    .monospacedDigit()
                                                    .foregroundColor(AppTheme.textPrimary)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer(minLength: 32)
                    }
                }
            }
            .navigationTitle("Garage")
            .sheet(isPresented: $showingAddLog) {
                AddServiceLogSheet(
                    vehicleId: vehicleStore.activeVehicleId,
                    currentOdo: vehicleStore.activeVehicle.currentOdometer
                ) { newLog in
                    db.addGarageLog(newLog)
                }
            }
            .alert("Update Odometer", isPresented: $showingOdoEdit) {
                TextField("Odometer (km)", text: $newOdoText)
                    .keyboardType(.numberPad)
                Button("Save") {
                    if let km = Double(newOdoText) {
                        vehicleStore.updateOdometer(km: km)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
