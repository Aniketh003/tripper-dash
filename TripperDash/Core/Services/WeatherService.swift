import Foundation
import CoreLocation

@Observable
public final class WeatherService: @unchecked Sendable {
    public static let shared = WeatherService()
    
    public var temperatureC: Int = 0
    public var feelsLikeC: Int = 0
    public var conditionText: String = "Syncing…"
    public var symbolName: String = "cloud.sun.fill"
    public var windSpeedKmh: Int = 0
    public var humidityPercent: Int = 0
    public var locationName: String = ""
    /// Authentic Royal Enfield TFT 06 08 Weather Icon: 1=Cloudy, 2=Thunder, 3=Rain, 4=Snow, 5=Sun, 0xFF=No Data
    public var dashWeatherIcon: UInt8 = 0xFF
    public var isLoaded: Bool = false
    public var isRefreshing: Bool = false
    public var lastUpdated: Date? = nil
    
    private var lastFetchCoordinate: CLLocationCoordinate2D? = nil
    private let geocoder = CLGeocoder()
    private let cellularSession: URLSession
    
    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.allowsCellularAccess = true
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 8.0
        #if os(iOS)
        config.multipathServiceType = .handover
        #endif
        self.cellularSession = URLSession(configuration: config)
        
        // Restore last real cached weather from UserDefaults (never fake placeholder numbers)
        if UserDefaults.standard.bool(forKey: "cache_weather_valid") {
            self.temperatureC = UserDefaults.standard.integer(forKey: "cache_weather_temp")
            self.feelsLikeC = UserDefaults.standard.integer(forKey: "cache_weather_feels")
            self.conditionText = UserDefaults.standard.string(forKey: "cache_weather_cond") ?? "Clear"
            self.symbolName = UserDefaults.standard.string(forKey: "cache_weather_sym") ?? "sun.max.fill"
            self.windSpeedKmh = UserDefaults.standard.integer(forKey: "cache_weather_wind")
            self.humidityPercent = UserDefaults.standard.integer(forKey: "cache_weather_hum")
            self.locationName = UserDefaults.standard.string(forKey: "cache_weather_loc") ?? ""
            let iconRaw = UserDefaults.standard.integer(forKey: "cache_weather_icon")
            self.dashWeatherIcon = iconRaw > 0 ? UInt8(iconRaw & 0xFF) : 0x05
            self.isLoaded = true
        }
    }
    
    public var compactTFTString: String {
        guard isLoaded else { return "Weather Syncing" }
        return "\(temperatureC)°C \(conditionText)"
    }
    
    public var fullTFTString: String {
        guard isLoaded else { return "Waiting for GPS Weather…" }
        if locationName.isEmpty {
            return "\(temperatureC)°C \(conditionText) · Wind \(windSpeedKmh) km/h"
        }
        return "\(temperatureC)°C \(conditionText) · \(locationName)"
    }
    
    /// Fetches live weather for the rider's current GPS coordinates (throttled to every 5 minutes unless forced)
    public func refresh(for coordinate: CLLocationCoordinate2D?, force: Bool = false) {
        guard let coord = coordinate ?? lastFetchCoordinate else {
            return
        }
        
        if !force, let last = lastUpdated, Date().timeIntervalSince(last) < 300, isLoaded {
            return
        }
        guard !isRefreshing else { return }
        
        lastFetchCoordinate = coord
        DispatchQueue.main.async { self.isRefreshing = true }
        
        // 1. Reverse geocode real locality name
        let clLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        geocoder.reverseGeocodeLocation(clLocation) { [weak self] placemarks, _ in
            if let place = placemarks?.first {
                let name = place.locality ?? place.subLocality ?? place.subAdministrativeArea ?? place.administrativeArea ?? ""
                if !name.isEmpty {
                    DispatchQueue.main.async {
                        self?.locationName = name
                        UserDefaults.standard.set(name, forKey: "cache_weather_loc")
                        TFTProjectionService.shared.triggerImmediateFrame()
                    }
                }
            }
        }
        
        // 2. Fetch live weather from Open-Meteo over cellular/multipath session
        let urlString = String(
            format: "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,is_day",
            coord.latitude, coord.longitude
        )
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { self.isRefreshing = false }
            return
        }
        
        cellularSession.dataTask(with: url) { [weak self] data, _, error in
            defer { DispatchQueue.main.async { self?.isRefreshing = false } }
            guard let self = self, let data = data, error == nil else { return }
            
            do {
                let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
                let cur = decoded.current
                let isDay = (cur.is_day ?? 1) == 1
                let mapped = Self.mapWMOCode(cur.weather_code, isDay: isDay)
                
                DispatchQueue.main.async {
                    self.temperatureC = Int(round(cur.temperature_2m))
                    self.feelsLikeC = Int(round(cur.apparent_temperature ?? cur.temperature_2m))
                    self.humidityPercent = cur.relative_humidity_2m ?? 50
                    self.windSpeedKmh = Int(round(cur.wind_speed_10m ?? 0))
                    self.conditionText = mapped.text
                    self.symbolName = mapped.symbol
                    self.dashWeatherIcon = mapped.dashIcon
                    self.isLoaded = true
                    self.lastUpdated = Date()
                    
                    // Cache real weather
                    UserDefaults.standard.set(true, forKey: "cache_weather_valid")
                    UserDefaults.standard.set(self.temperatureC, forKey: "cache_weather_temp")
                    UserDefaults.standard.set(self.feelsLikeC, forKey: "cache_weather_feels")
                    UserDefaults.standard.set(self.conditionText, forKey: "cache_weather_cond")
                    UserDefaults.standard.set(self.symbolName, forKey: "cache_weather_sym")
                    UserDefaults.standard.set(self.windSpeedKmh, forKey: "cache_weather_wind")
                    UserDefaults.standard.set(self.humidityPercent, forKey: "cache_weather_hum")
                    UserDefaults.standard.set(Int(self.dashWeatherIcon), forKey: "cache_weather_icon")
                    
                    TripperDashClient.shared.log("🌤️ Live Weather synced: \(self.fullTFTString)")
                    TripperDashClient.shared.sendWeatherUpdate()
                    TFTProjectionService.shared.triggerImmediateFrame()
                }
            } catch {
                print("WeatherService decode error: \(error)")
            }
        }.resume()
    }
    
    // MARK: - WMO Weather Codes → SF Symbols & Royal Enfield TFT 06 08 Icon Byte
    /// Dash 06 08 icons: 1 = Cloudy, 2 = Thunder, 3 = Rain, 4 = Snow, 5 = Sun
    private static func mapWMOCode(_ code: Int, isDay: Bool) -> (text: String, symbol: String, dashIcon: UInt8) {
        switch code {
        case 0:
            return ("Clear", isDay ? "sun.max.fill" : "moon.stars.fill", 0x05)
        case 1:
            return ("Mostly Clear", isDay ? "sun.min.fill" : "moon.fill", 0x05)
        case 2:
            return ("Partly Cloudy", isDay ? "cloud.sun.fill" : "cloud.moon.fill", 0x01)
        case 3:
            return ("Overcast", "cloud.fill", 0x01)
        case 45, 48:
            return ("Fog", "cloud.fog.fill", 0x01)
        case 51, 53, 55:
            return ("Drizzle", "cloud.drizzle.fill", 0x03)
        case 61, 63, 65:
            return ("Rain", "cloud.rain.fill", 0x03)
        case 66, 67:
            return ("Freezing Rain", "cloud.sleet.fill", 0x03)
        case 71, 73, 75, 77:
            return ("Snow", "cloud.snow.fill", 0x04)
        case 80, 81, 82:
            return ("Showers", "cloud.heavyrain.fill", 0x03)
        case 95, 96, 99:
            return ("Thunderstorm", "cloud.bolt.rain.fill", 0x02)
        default:
            return ("Clear", isDay ? "sun.max.fill" : "moon.fill", 0x05)
        }
    }
}

private struct OpenMeteoResponse: Decodable {
    let current: CurrentWeather
    
    struct CurrentWeather: Decodable {
        let temperature_2m: Double
        let relative_humidity_2m: Int?
        let apparent_temperature: Double?
        let weather_code: Int
        let wind_speed_10m: Double?
        let is_day: Int?
    }
}
