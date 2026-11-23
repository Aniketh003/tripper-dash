import Foundation

@Observable
public final class DatabaseService: @unchecked Sendable {
    public static let shared = DatabaseService()
    
    // In-memory reactive state synced with disk
    public var expenses: [Expense] = []
    public var garageLogs: [GarageLogEntry] = []
    public var spareParts: [SparePart] = []
    public var rides: [RideRecord] = []
    
    private let fileManager = FileManager.default
    private let storageQueue = DispatchQueue(label: "com.tripperdash.database", qos: .userInitiated)
    
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private var expensesFileURL: URL { documentsDirectory.appendingPathComponent("expenses.json") }
    private var garageLogsFileURL: URL { documentsDirectory.appendingPathComponent("garage_logs.json") }
    private var sparePartsFileURL: URL { documentsDirectory.appendingPathComponent("spare_parts.json") }
    private var ridesFileURL: URL { documentsDirectory.appendingPathComponent("rides.json") }
    
    private init() {
        loadAll()
    }
    
    // MARK: - Initial Load
    public func loadAll() {
        expenses = load([Expense].self, from: expensesFileURL) ?? []
        garageLogs = load([GarageLogEntry].self, from: garageLogsFileURL) ?? []
        spareParts = load([SparePart].self, from: sparePartsFileURL) ?? []
        rides = load([RideRecord].self, from: ridesFileURL) ?? []
    }
    
    // MARK: - Expenses Operations
    public func addExpense(_ expense: Expense) {
        expenses.insert(expense, at: 0)
        persist(expenses, to: expensesFileURL)
    }
    
    public func deleteExpense(id: String) {
        expenses.removeAll { $0.id == id }
        persist(expenses, to: expensesFileURL)
    }
    
    public func totalExpenses(for vehicleId: String? = nil) -> Double {
        let filtered = vehicleId == nil ? expenses : expenses.filter { $0.vehicleId == vehicleId }
        return filtered.reduce(0) { $0 + $1.amount }
    }
    
    public func exportExpensesCSV() -> URL? {
        var csv = "Date,Category,Amount,Title,Notes,VehicleID\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        for e in expenses {
            let dateStr = formatter.string(from: e.date)
            let line = "\"\(dateStr)\",\"\(e.category.rawValue)\",\(e.amount),\"\(e.title)\",\"\(e.notes)\",\"\(e.vehicleId)\"\n"
            csv.append(line)
        }
        
        let path = documentsDirectory.appendingPathComponent("OpenDash_Expenses.csv")
        do {
            try csv.write(to: path, atomically: true, encoding: .utf8)
            return path
        } catch {
            print("Failed to export CSV: \(error)")
            return nil
        }
    }
    
    // MARK: - Garage Log Operations
    public func addGarageLog(_ log: GarageLogEntry) {
        garageLogs.insert(log, at: 0)
        persist(garageLogs, to: garageLogsFileURL)
    }
    
    public func deleteGarageLog(id: String) {
        garageLogs.removeAll { $0.id == id }
        persist(garageLogs, to: garageLogsFileURL)
    }
    
    // MARK: - Spare Parts Operations
    public func addSparePart(_ part: SparePart) {
        spareParts.insert(part, at: 0)
        persist(spareParts, to: sparePartsFileURL)
    }
    
    public func deleteSparePart(id: String) {
        spareParts.removeAll { $0.id == id }
        persist(spareParts, to: sparePartsFileURL)
    }
    
    // MARK: - Rides Operations
    public func saveRide(_ ride: RideRecord) {
        rides.insert(ride, at: 0)
        persist(rides, to: ridesFileURL)
    }
    
    public func deleteRide(id: String) {
        rides.removeAll { $0.id == id }
        persist(rides, to: ridesFileURL)
    }
    
    // MARK: - Persistence Helpers
    private func persist<T: Encodable>(_ data: T, to url: URL) {
        storageQueue.async {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let encoded = try encoder.encode(data)
                try encoded.write(to: url, options: .atomic)
            } catch {
                print("Failed to persist data to \(url.lastPathComponent): \(error)")
            }
        }
    }
    
    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("Failed to load \(url.lastPathComponent): \(error)")
            return nil
        }
    }
}
