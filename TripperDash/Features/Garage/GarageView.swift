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
        vehicleStore.nextServiceRemainingKm
    }
    
    private var serviceProgress: Double {
        let target = vehicleStore.nextServiceTargetKm
        let cycleSpan = target <= 500.0 ? 500.0 : 5000.0
        let used = cycleSpan - nextServiceRemainingKm
        return min(max(used / cycleSpan, 0.0), 1.0)
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Royal Enfield Guerrilla 450 — Apex Black Showcase Card
                        GlassCard {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(alignment: .center) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text("ROYAL ENFIELD")
                                                .font(.system(size: 11, weight: .bold))
                                                .tracking(0.8)
                                                .foregroundColor(AppTheme.accent)
                                            
                                            Text("· \(vehicleStore.activeVehicle.dashSSID)")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundColor(AppTheme.textTertiary)
                                        }
                                        
                                        Text("\(vehicleStore.activeVehicle.title) · \(vehicleStore.activeVehicle.nickname)")
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundColor(AppTheme.textPrimary)
                                        
                                        Text(vehicleStore.activeVehicle.engineSpec)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(AppTheme.textSecondary)
                                    }
                                    
                                    Spacer()
                                    
                                    ZStack {
                                        Circle()
                                            .fill(AppTheme.surfaceElevated)
                                            .frame(width: 48, height: 48)
                                        Image(systemName: "motorcycle.fill")
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(AppTheme.accent)
                                    }
                                }
                                
                                Divider().background(AppTheme.border)
                                
                                // Odometer & Live Sync Pills
                                HStack(spacing: 8) {
                                    Button(action: {
                                        newOdoText = String(format: "%.1f", vehicleStore.activeVehicle.currentOdometer)
                                        showingOdoEdit = true
                                    }) {
                                        HStack(spacing: 5) {
                                            Text(String(format: "%.1f km", vehicleStore.activeVehicle.currentOdometer))
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
                                
                                // Factory Specs Row (Sherpa 450 Power, Tank, Tyres)
                                Divider().background(AppTheme.border)
                                
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Output")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppTheme.textTertiary)
                                        Text("40 PS · 40 Nm")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppTheme.textSecondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Fuel Tank")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppTheme.textTertiary)
                                        Text("11.0 L")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppTheme.textSecondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("Tyre Pressure")
                                            .font(.system(size: 11))
                                            .foregroundColor(AppTheme.textTertiary)
                                        Text("29F / 33R PSI")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(AppTheme.textSecondary)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        
                        // Official Guerrilla 450 Service Schedule Card
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(vehicleStore.nextServiceMilestoneLabel)
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
                                
                                Text("Auto-updates odometer via GPS & K1G link whenever connected to \(vehicleStore.activeVehicle.dashSSID)")
                                    .font(.system(size: 11))
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
                                Text("Log break-in service (500 km), 10W-50 oil changes, chain lube, and inspections.")
                                    .font(.system(size: 13))
                                    .foregroundColor(AppTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 44)
                            .padding(.horizontal, 24)
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
            .alert("Sync Odometer", isPresented: $showingOdoEdit) {
                TextField("Odometer (km)", text: $newOdoText)
                    .keyboardType(.decimalPad)
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
