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
    
    // Calculate distance to next 5,000 km service milestone
    private var nextServiceRemainingKm: Double {
        let current = vehicleStore.activeVehicle.currentOdometer
        let interval = 5000.0
        let nextTarget = ceil(max(current + 1, 1) / interval) * interval
        return max(0, nextTarget - current)
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Vehicle Header Card
                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(vehicleStore.activeVehicle.title.uppercased())
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(AppTheme.accent)
                                            .tracking(1.0)
                                        
                                        Text(vehicleStore.activeVehicle.nickname)
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                            .foregroundColor(AppTheme.textPrimary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "motorcycle.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(AppTheme.textTertiary)
                                }
                                
                                Divider().background(AppTheme.border)
                                
                                // Odometer & Compliance pills
                                HStack(spacing: 12) {
                                    Button(action: {
                                        newOdoText = String(format: "%.0f", vehicleStore.activeVehicle.currentOdometer)
                                        showingOdoEdit = true
                                    }) {
                                        HStack(spacing: 4) {
                                            Text(String(format: "%.0f km", vehicleStore.activeVehicle.currentOdometer))
                                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                                .foregroundColor(AppTheme.textPrimary)
                                            Image(systemName: "pencil")
                                                .font(.system(size: 10))
                                                .foregroundColor(AppTheme.textTertiary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(AppTheme.surfaceElevated)
                                        .clipShape(Capsule())
                                    }
                                    
                                    HStack(spacing: 4) {
                                        Text("PUC: \(vehicleStore.activeVehicle.puc)")
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundColor(AppTheme.emerald)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(AppTheme.emerald.opacity(0.12))
                                    .clipShape(Capsule())
                                    
                                    HStack(spacing: 4) {
                                        Text("INS: \(vehicleStore.activeVehicle.insurance)")
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundColor(AppTheme.emerald)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(AppTheme.emerald.opacity(0.12))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        
                        // Maintenance Countdown Card
                        GlassCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("SERVICE INTERVAL COUNTDOWN")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(AppTheme.textTertiary)
                                    
                                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                                        Text(String(format: "%.0f", nextServiceRemainingKm))
                                            .font(.system(size: 28, weight: .bold, design: .rounded))
                                            .foregroundColor(AppTheme.accent)
                                        Text("km until next service")
                                            .font(.system(size: 13, design: .rounded))
                                            .foregroundColor(AppTheme.textSecondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.system(size: 24))
                                    .foregroundColor(AppTheme.accent.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Service Log Section Header
                        HStack {
                            Text("MAINTENANCE LOG")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(AppTheme.textTertiary)
                                .tracking(1.0)
                            
                            Spacer()
                            
                            Button(action: { showingAddLog = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Add Log")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(AppTheme.accent)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        
                        // Service Log Entries
                        if activeVehicleLogs.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 32))
                                    .foregroundColor(AppTheme.textTertiary)
                                Text("No service records logged yet")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(activeVehicleLogs) { log in
                                    GlassCard(padding: 14) {
                                        HStack(alignment: .top) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(log.title)
                                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                    .foregroundColor(AppTheme.textPrimary)
                                                
                                                Text("\(String(format: "%.0f", log.odometerKm)) km • \(log.type.rawValue)")
                                                    .font(.system(size: 12, design: .monospaced))
                                                    .foregroundColor(AppTheme.textSecondary)
                                                
                                                if !log.notes.isEmpty {
                                                    Text(log.notes)
                                                        .font(.system(size: 12, design: .rounded))
                                                        .foregroundColor(AppTheme.textTertiary)
                                                        .padding(.top, 2)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            if log.cost > 0 {
                                                Text(String(format: "₹%.0f", log.cost))
                                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                                    .foregroundColor(AppTheme.textPrimary)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer(minLength: 30)
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
                TextField("Odometer in km", text: $newOdoText)
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
