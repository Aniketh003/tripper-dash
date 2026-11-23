import SwiftUI

public struct ExpensesView: View {
    @Bindable var db: DatabaseService
    @Bindable var vehicleStore: VehicleStore
    public var embedded: Bool = false
    
    @State private var selectedCategory: ExpenseCategory? = nil
    @State private var showingAddExpense = false
    @State private var exportURL: URL? = nil
    
    public init(db: DatabaseService, vehicleStore: VehicleStore, embedded: Bool = false) {
        self.db = db
        self.vehicleStore = vehicleStore
        self.embedded = embedded
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
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .navigationTitle("Expenses")
            }
        }
    }
    
    private var content: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    GlassCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Total Spent")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(AppTheme.textSecondary)
                                
                                Text(String(format: "₹%.2f", totalFilteredAmount))
                                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundColor(AppTheme.textPrimary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                if let url = db.exportExpensesCSV() {
                                    exportURL = url
                                }
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("CSV")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundColor(AppTheme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AppTheme.surfaceElevated)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Category Filter Pills
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
                    
                    // Section Header + Add Action
                    HStack {
                        Text("History (\(filteredExpenses.count))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.textSecondary)
                        
                        Spacer()
                        
                        Button(action: { showingAddExpense = true }) {
                            Label("Add Expense", systemImage: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    
                    if filteredExpenses.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "fuelpump")
                                .font(.system(size: 34, weight: .light))
                                .foregroundColor(AppTheme.textTertiary)
                            Text("No expenses logged")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("Track fuel, service, tolls, and gear costs here.")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 44)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(filteredExpenses) { exp in
                                GlassCard(cornerRadius: 16, padding: 14) {
                                    HStack(spacing: 12) {
                                        Image(systemName: exp.category.iconName)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(AppTheme.accent)
                                            .frame(width: 38, height: 38)
                                            .background(AppTheme.surfaceElevated)
                                            .clipShape(Circle())
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(exp.title)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(AppTheme.textPrimary)
                                            
                                            Text(exp.date.formatted(date: .abbreviated, time: .shortened))
                                                .font(.system(size: 12))
                                                .foregroundColor(AppTheme.textSecondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Text(String(format: "₹%.2f", exp.amount))
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundColor(AppTheme.textPrimary)
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
            Text("CSV Export Saved").font(.headline)
            if let url = items.first as? URL {
                Text(url.lastPathComponent).font(.caption).foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding(24)
    }
}
#endif
