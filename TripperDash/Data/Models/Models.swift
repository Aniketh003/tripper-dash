import Foundation

// MARK: - Vehicle Profile (Default: Royal Enfield Guerrilla 450 — Apex Black)
public struct VehicleProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var nickname: String
    public var puc: String
    public var insurance: String
    public var service: String
    public var currentOdometer: Double
    public var engineSpec: String
    public var powerTorqueSpec: String
    public var fuelCapacityLiters: Double
    public var tirePressureFrontRearPSI: String
    public var dashSSID: String
    
    public init(
        id: String = UUID().uuidString,
        title: String = "Guerrilla 450",
        nickname: String = "Apex Black",
        puc: String = "Valid",
        insurance: String = "Valid",
        service: String = "Up to date",
        currentOdometer: Double = 0.0,
        engineSpec: String = "452 cc Sherpa 450 · Liquid-Cooled DOHC",
        powerTorqueSpec: String = "40 PS @ 8,000 rpm · 40 Nm @ 5,500 rpm",
        fuelCapacityLiters: Double = 11.0,
        tirePressureFrontRearPSI: String = "29 PSI Front · 33 PSI Rear",
        dashSSID: String = "RE_RLK8_260813"
    ) {
        self.id = id
        self.title = title
        self.nickname = nickname
        self.puc = puc
        self.insurance = insurance
        self.service = service
        self.currentOdometer = currentOdometer
        self.engineSpec = engineSpec
        self.powerTorqueSpec = powerTorqueSpec
        self.fuelCapacityLiters = fuelCapacityLiters
        self.tirePressureFrontRearPSI = tirePressureFrontRearPSI
        self.dashSSID = dashSSID
    }
    
    // Backward-compatible decoder for existing stored profiles
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? "default"
        self.title = (try? c.decode(String.self, forKey: .title)) ?? "Guerrilla 450"
        self.nickname = (try? c.decode(String.self, forKey: .nickname)) ?? "Apex Black"
        self.puc = (try? c.decode(String.self, forKey: .puc)) ?? "Valid"
        self.insurance = (try? c.decode(String.self, forKey: .insurance)) ?? "Valid"
        self.service = (try? c.decode(String.self, forKey: .service)) ?? "Up to date"
        self.currentOdometer = (try? c.decode(Double.self, forKey: .currentOdometer)) ?? 0.0
        self.engineSpec = (try? c.decode(String.self, forKey: .engineSpec)) ?? "452 cc Sherpa 450 · Liquid-Cooled DOHC"
        self.powerTorqueSpec = (try? c.decode(String.self, forKey: .powerTorqueSpec)) ?? "40 PS @ 8,000 rpm · 40 Nm @ 5,500 rpm"
        self.fuelCapacityLiters = (try? c.decode(Double.self, forKey: .fuelCapacityLiters)) ?? 11.0
        self.tirePressureFrontRearPSI = (try? c.decode(String.self, forKey: .tirePressureFrontRearPSI)) ?? "29 PSI Front · 33 PSI Rear"
        self.dashSSID = (try? c.decode(String.self, forKey: .dashSSID)) ?? "RE_RLK8_260813"
    }
}

// MARK: - Expense Category & Model
public enum ExpenseCategory: String, CaseIterable, Codable, Sendable {
    case fuel = "Fuel"
    case maintenance = "Maintenance"
    case accessories = "Accessories"
    case gear = "Riding Gear"
    case food = "Food"
    case stays = "Stays"
    case transport = "Transport"
    case other = "Other"
    
    public var iconName: String {
        switch self {
        case .fuel: return "fuelpump.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .accessories: return "plus.magnifyingglass"
        case .gear: return "shield.lefthalf.filled"
        case .food: return "fork.knife"
        case .stays: return "bed.double.fill"
        case .transport: return "ferry.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

public struct Expense: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var sid: String
    public var vehicleId: String
    public var dateMs: Int64
    public var category: ExpenseCategory
    public var amount: Double
    public var title: String
    public var notes: String
    
    public init(
        id: String = UUID().uuidString,
        sid: String = UUID().uuidString,
        vehicleId: String = "default",
        dateMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        category: ExpenseCategory = .fuel,
        amount: Double = 0.0,
        title: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.sid = sid
        self.vehicleId = vehicleId
        self.dateMs = dateMs
        self.category = category
        self.amount = amount
        self.title = title
        self.notes = notes
    }
    
    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(dateMs) / 1000.0)
    }
}

// MARK: - Garage & Maintenance Models
public enum ServiceLogType: String, CaseIterable, Codable, Sendable {
    case oilChange = "Oil & Filter"
    case chainService = "Chain Slack & Lube"
    case brakePads = "Brake Pads"
    case airFilter = "Air Filter"
    case coolant = "Coolant Flush"
    case tires = "Tire Replacement"
    case general = "General Service"
    case custom = "Custom"
}

public struct GarageLogEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var sid: String
    public var vehicleId: String
    public var dateMs: Int64
    public var odometerKm: Double
    public var type: ServiceLogType
    public var title: String
    public var cost: Double
    public var notes: String
    
    public init(
        id: String = UUID().uuidString,
        sid: String = UUID().uuidString,
        vehicleId: String = "default",
        dateMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        odometerKm: Double = 0.0,
        type: ServiceLogType = .oilChange,
        title: String = "",
        cost: Double = 0.0,
        notes: String = ""
    ) {
        self.id = id
        self.sid = sid
        self.vehicleId = vehicleId
        self.dateMs = dateMs
        self.odometerKm = odometerKm
        self.type = type
        self.title = title
        self.cost = cost
        self.notes = notes
    }
    
    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(dateMs) / 1000.0)
    }
}

public struct SparePart: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var sid: String
    public var vehicleId: String
    public var name: String
    public var partNumber: String
    public var quantity: Int
    public var cost: Double
    public var notes: String
    
    public init(
        id: String = UUID().uuidString,
        sid: String = UUID().uuidString,
        vehicleId: String = "default",
        name: String,
        partNumber: String = "",
        quantity: Int = 1,
        cost: Double = 0.0,
        notes: String = ""
    ) {
        self.id = id
        self.sid = sid
        self.vehicleId = vehicleId
        self.name = name
        self.partNumber = partNumber
        self.quantity = quantity
        self.cost = cost
        self.notes = notes
    }
}

// MARK: - Ride Recording Model
public struct RideRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var sid: String
    public var startMs: Int64
    public var endMs: Int64
    public var distanceMeters: Double
    public var durationSeconds: Int
    public var averageSpeedKmh: Double
    public var maxSpeedKmh: Double
    public var trackPolyline: String
    
    public init(
        id: String = UUID().uuidString,
        sid: String = UUID().uuidString,
        startMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        endMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        distanceMeters: Double = 0.0,
        durationSeconds: Int = 0,
        averageSpeedKmh: Double = 0.0,
        maxSpeedKmh: Double = 0.0,
        trackPolyline: String = ""
    ) {
        self.id = id
        self.sid = sid
        self.startMs = startMs
        self.endMs = endMs
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.averageSpeedKmh = averageSpeedKmh
        self.maxSpeedKmh = maxSpeedKmh
        self.trackPolyline = trackPolyline
    }
    
    public var distanceKm: Double {
        distanceMeters / 1000.0
    }
    
    public var startDate: Date {
        Date(timeIntervalSince1970: TimeInterval(startMs) / 1000.0)
    }
    
    public var formattedDuration: String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        let seconds = durationSeconds % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%02dm %02ds", minutes, seconds)
        }
    }
}

// MARK: - Navigation Maneuver & Route
public enum ManeuverType: String, Codable, Sendable {
    case straight = "straight"
    case turnSlightLeft = "slight_left"
    case turnLeft = "turn_left"
    case turnSharpLeft = "sharp_left"
    case turnSlightRight = "slight_right"
    case turnRight = "turn_right"
    case turnSharpRight = "sharp_right"
    case uTurn = "u_turn"
    case roundabout = "roundabout"
    case destination = "destination"
    case unknown = "unknown"
    
    public var iconName: String {
        switch self {
        case .straight: return "arrow.up"
        case .turnSlightLeft: return "arrow.up.left"
        case .turnLeft: return "arrow.turn.up.left"
        case .turnSharpLeft: return "arrow.left"
        case .turnSlightRight: return "arrow.up.right"
        case .turnRight: return "arrow.turn.up.right"
        case .turnSharpRight: return "arrow.right"
        case .uTurn: return "arrow.uturn.down"
        case .roundabout: return "arrow.triangle.2.circlepath"
        case .destination: return "flag.checkered"
        case .unknown: return "location.fill"
        }
    }
    
    /// Authentic Royal Enfield Tripper Dash K1G Maneuver Icon Byte
    public var k1gIconCode: UInt8 {
        switch self {
        case .straight: return 0x09
        case .turnSlightRight: return 0x03
        case .turnRight: return 0x04
        case .turnSharpRight: return 0x05
        case .uTurn: return 0x06
        case .turnSharpLeft: return 0x07
        case .turnLeft: return 0x08
        case .turnSlightLeft: return 0x09
        case .roundabout: return 0x1B
        case .destination: return 0x3C
        case .unknown: return 0x09
        }
    }
}

public struct PlaceSearchResult: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let latitude: Double
    public let longitude: Double
    
    public init(id: String = UUID().uuidString, title: String, subtitle: String, latitude: Double, longitude: Double) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct RouteStep: Identifiable, Codable, Equatable, Sendable {
    public var id: String = UUID().uuidString
    public var instruction: String
    public var distanceMeters: Double
    public var maneuver: ManeuverType
    public var streetName: String
    public var endLatitude: Double?
    public var endLongitude: Double?
    
    public init(
        instruction: String,
        distanceMeters: Double,
        maneuver: ManeuverType = .straight,
        streetName: String = "",
        endLatitude: Double? = nil,
        endLongitude: Double? = nil
    ) {
        self.instruction = instruction
        self.distanceMeters = distanceMeters
        self.maneuver = maneuver
        self.streetName = streetName
        self.endLatitude = endLatitude
        self.endLongitude = endLongitude
    }
}

public struct DashRouteInfo: Identifiable, Codable, Equatable, Sendable {
    public var id: String = UUID().uuidString
    public var destinationName: String
    public var totalDistanceMeters: Double
    public var totalDurationSeconds: Int
    public var encodedPolyline: String
    public var steps: [RouteStep]
    
    public init(
        destinationName: String,
        totalDistanceMeters: Double,
        totalDurationSeconds: Int,
        encodedPolyline: String,
        steps: [RouteStep]
    ) {
        self.destinationName = destinationName
        self.totalDistanceMeters = totalDistanceMeters
        self.totalDurationSeconds = totalDurationSeconds
        self.encodedPolyline = encodedPolyline
        self.steps = steps
    }
}
