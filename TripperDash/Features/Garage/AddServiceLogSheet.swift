import SwiftUI

public struct AddServiceLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    public let vehicleId: String
    public let currentOdo: Double
    public let onSave: (GarageLogEntry) -> Void
    
    @State private var title: String = ""
    @State private var type: ServiceLogType = .oilChange
    @State private var odometer: String = ""
    @State private var cost: String = ""
    @State private var notes: String = ""
    
    public init(vehicleId: String, currentOdo: Double, onSave: @escaping (GarageLogEntry) -> Void) {
        self.vehicleId = vehicleId
        self.currentOdo = currentOdo
        self.onSave = onSave
        _odometer = State(initialValue: String(format: "%.0f", currentOdo))
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Service Type Selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SERVICE TYPE")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppTheme.textTertiary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(ServiceLogType.allCases, id: \.self) { item in
                                        PillBadge(text: item.rawValue, isSelected: item == type) {
                                            type = item
                                            if title.isEmpty || ServiceLogType.allCases.map({ $0.rawValue }).contains(title) {
                                                title = item.rawValue
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Title Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TITLE / WORK DESCRIPTION")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppTheme.textTertiary)
                            
                            TextField("e.g. 5,000 km Periodic Service", text: $title)
                                .font(.system(size: 15, design: .rounded))
                                .foregroundColor(.white)
                                .padding(14)
                                .background(AppTheme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        // Odometer & Cost
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ODOMETER (KM)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(AppTheme.textTertiary)
                                
                                TextField("km", text: $odometer)
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 15, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(14)
                                    .background(AppTheme.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("COST (AMOUNT)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(AppTheme.textTertiary)
                                
                                TextField("0.00", text: $cost)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 15, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(14)
                                    .background(AppTheme.surfaceElevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        
                        // Notes Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTES & REPLACED PARTS")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppTheme.textTertiary)
                            
                            TextField("Oil grade, brand, mechanic notes...", text: $notes, axis: .vertical)
                                .lineLimit(3...5)
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(.white)
                                .padding(14)
                                .background(AppTheme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        Spacer(minLength: 20)
                        
                        MinimalButton(title: "Save Service Entry", icon: "checkmark") {
                            let odoVal = Double(odometer) ?? currentOdo
                            let costVal = Double(cost) ?? 0.0
                            let log = GarageLogEntry(
                                vehicleId: vehicleId,
                                odometerKm: odoVal,
                                type: type,
                                title: title.isEmpty ? type.rawValue : title,
                                cost: costVal,
                                notes: notes
                            )
                            onSave(log)
                            dismiss()
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Log Service")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
    }
}
