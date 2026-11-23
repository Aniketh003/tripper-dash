import SwiftUI

public struct AddExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    public let vehicleId: String
    public let onSave: (Expense) -> Void
    
    @State private var title: String = ""
    @State private var amount: String = ""
    @State private var category: ExpenseCategory = .fuel
    @State private var notes: String = ""
    
    public init(vehicleId: String, onSave: @escaping (Expense) -> Void) {
        self.vehicleId = vehicleId
        self.onSave = onSave
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Category Pills
                        VStack(alignment: .leading, spacing: 8) {
                            Text("EXPENSE CATEGORY")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppTheme.textTertiary)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(ExpenseCategory.allCases, id: \.self) { cat in
                                        PillBadge(text: cat.rawValue, icon: cat.iconName, isSelected: cat == category) {
                                            category = cat
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Amount Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AMOUNT")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppTheme.textTertiary)
                            
                            HStack {
                                Text("₹")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(AppTheme.accent)
                                
                                TextField("0.00", text: $amount)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .padding(14)
                            .background(AppTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        // Title Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DESCRIPTION / TITLE")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppTheme.textTertiary)
                            
                            TextField("e.g. Tank full at Shell", text: $title)
                                .font(.system(size: 15, design: .rounded))
                                .foregroundColor(.white)
                                .padding(14)
                                .background(AppTheme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        // Notes Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTES (OPTIONAL)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(AppTheme.textTertiary)
                            
                            TextField("Liters filled, location, payment mode...", text: $notes)
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(.white)
                                .padding(14)
                                .background(AppTheme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        Spacer(minLength: 20)
                        
                        MinimalButton(title: "Save Expense", icon: "checkmark") {
                            let amt = Double(amount) ?? 0.0
                            let exp = Expense(
                                vehicleId: vehicleId,
                                category: category,
                                amount: amt,
                                title: title.isEmpty ? category.rawValue : title,
                                notes: notes
                            )
                            onSave(exp)
                            dismiss()
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
    }
}
