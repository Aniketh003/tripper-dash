import SwiftUI

public struct ExpensesView: View {
    @Bindable var db: DatabaseService
    @Bindable var vehicleStore: VehicleStore
    
    @State private var selectedCategory: ExpenseCategory? = nil
    @State private var showingAddExpense = false
    @State private var exportURL: URL? = nil
    
    public init(db: DatabaseService, vehicleStore: VehicleStore) {
        self.db = db
        self.vehicleStore = vehicleStore
    }
    
    private var filteredExpenses: [Expense] {
        db.expenses.filter { exp in
            let matchesCategory = selectedCategory == nil || exp.category == selectedCategory
            let matchesVehicle = exp.vehicleId == vehicleStore.activeVehicleId
            return matchesCategory && matchesVehicle
        }
    }
    
    private var totalFilteredAmount: Double {
        filteredExpenses.reduce(0) { $0 + $1.amount }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Total Summary Card
                        GlassCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("TOTAL EXPENSES")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(AppTheme.textTertiary)
                                    
                                    Text(String(format: "₹%.2f", totalFilteredAmount))
                                        .font(.system(size: 32, weight: .bold, design: .rounded))
                                        .foregroundColor(AppTheme.textPrimary)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    if let url = db.exportExpensesCSV() {
                                        exportURL = url
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("Export CSV")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    }
                                    .foregroundColor(AppTheme.accent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(AppTheme.surfaceElevated)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        
                        // Category Filter Bar
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                PillBadge(text: "All", isSelected: selectedCategory == nil) {
                                    selectedCategory = nil
                                }
                                
                                ForEach(ExpenseCategory.allCases, id: \.self) { cat in
                                    PillBadge(text: cat.rawValue, icon: cat.iconName, isSelected: selectedCategory == cat) {
                                        selectedCategory = cat
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        // Header with Add Button
                        HStack {
                            Text("HISTORY (\(filteredExpenses.count))")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(AppTheme.textTertiary)
                                .tracking(1.0)
                            
                            Spacer()
                            
                            Button(action: { showingAddExpense = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("Add Expense")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(AppTheme.accent)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Expenses List
                        if filteredExpenses.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "fuelpump")
                                    .font(.system(size: 32))
                                    .foregroundColor(AppTheme.textTertiary)
                                Text("No expenses logged for this filter")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(filteredExpenses) { exp in
                                    GlassCard(padding: 14) {
                                        HStack(spacing: 12) {
                                            Image(systemName: exp.category.iconName)
                                                .font(.system(size: 18))
                                                .foregroundColor(AppTheme.accent)
                                                .frame(width: 36, height: 36)
                                                .background(AppTheme.surfaceElevated)
                                                .clipShape(Circle())
                                            
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(exp.title)
                                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                    .foregroundColor(AppTheme.textPrimary)
                                                
                                                Text(exp.date.formatted(date: .abbreviated, time: .shortened))
                                                    .font(.system(size: 12, design: .monospaced))
                                                    .foregroundColor(AppTheme.textSecondary)
                                            }
                                            
                                            Spacer()
                                            
                                            Text(String(format: "₹%.2f", exp.amount))
                                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                                .foregroundColor(AppTheme.textPrimary)
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
            .navigationTitle("Expenses")
            .sheet(isPresented: $showingAddExpense) {
                AddExpenseSheet(vehicleId: vehicleStore.activeVehicleId) { newExp in
                    db.addExpense(newExp)
                }
            }
            .sheet(item: $exportURL) { url in
                ShareSheet(items: [url])
            }
        }
    }
}

// Helper wrapper for UIActivityViewController in SwiftUI
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

#if os(iOS)
public struct ShareSheet: UIViewControllerRepresentable {
    public let items: [Any]
    
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
public struct ShareSheet: View {
    public let items: [Any]
    public var body: some View {
        VStack(spacing: 12) {
            Text("CSV Export Saved")
                .font(.headline)
            if let url = items.first as? URL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding(24)
    }
}
#endif
