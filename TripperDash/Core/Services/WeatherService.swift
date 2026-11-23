import Foundation
import CoreLocation

@Observable
public final class WeatherService: @unchecked Sendable {
    public static let shared = WeatherService()
    
    public var temperatureC: Int = 26
    public var feelsLikeC: Int = 27
    public var conditionText: String = "Clear"
    public var symbolName: String = "sun.max.fill"
    public var windSpeedKmh: Int = 10
    public var humidityPercent: Int = 55
    public var locationName: String = "Local"
    public var isLoaded: Bool = false
    public var isRefreshing: Bool = false
    public var lastUpdated: Date? = nil
    
    private var lastFetchCoordinate: CLLocationCoordinate2D? = nil
    private let geocoder = CLGeocoder()
    
    private init() {}
    
    public var compactTFTString: String {
        "\(temperatureC)°C \(conditionText)"
    }
    
    public var fullTFTString: String {
        if locationName.isEmpty || locationName == "Local" {
            return "\(temperatureC)°C \(conditionText) · Wind \(windSpeedKmh) km/h"
        }
        return "\(temperatureC)°C \(conditionText) · \(locationName)"
    }
    
    /// Fetches live weather for the rider's current GPS coordinates (throttled to every 10 minutes unless forced)
    public func refresh(for coordinate: CLLocationCoordinate2D?, force: Bool = false) {
        let coord = coordinate ?? lastFetchCoordinate ?? CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946)
        
        if !force, let last = lastUpdated, Date().timeIntervalSince(last) < 600, isLoaded {
            return
        }
        guard !isRefreshing else { return }
        
        lastFetchCoordinate = coord
        DispatchQueue.main.async { self.isRefreshing = true }
        
        // 1. Reverse geocode locality name
        let clLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        geocoder.reverseGeocodeLocation(clLocation) { [weak self] placemarks, _ in
            if let place = placemarks?.first {
                let name = place.locality ?? place.subAdministrativeArea ?? place.administrativeArea ?? "Local"
                DispatchQueue.main.async {
                    self?.locationName = name
                }
            }
        }
        
        // 2. Fetch live weather from Open-Meteo (free, no API key required, fast HTTPS JSON)
        let urlString = String(
            format: "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m,is_day",
            coord.latitude, coord.longitude
        )
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { self.isRefreshing = false }
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
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
                    self.isLoaded = true
                    self.lastUpdated = Date()
                    
                    TripperDashClient.shared.log("🌤️ Weather updated: \(self.fullTFTString)")
                    TripperDashClient.shared.sendWeatherUpdate()
                }
            } catch {
                print("WeatherService decode error: \(error)")
            }
        }.resume()
    }
    
    // MARK: - WMO Weather Interpretation Codes → SF Symbols
    private static func mapWMOCode(_ code: Int, isDay: Bool) -> (text: String, symbol: String) {
        switch code {
        case 0:
            return ("Clear", isDay ? "sun.max.fill" : "moon.stars.fill")
        case 1:
            return ("Mostly Clear", isDay ? "sun.min.fill" : "moon.fill")
        case 2:
            return ("Partly Cloudy", isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3:
            return ("Overcast", "cloud.fill")
        case 45, 48:
            return ("Fog", "cloud.fog.fill")
        case 51, 53, 55:
            return ("Drizzle", "cloud.drizzle.fill")
        case 61, 63, 65:
            return ("Rain", "cloud.rain.fill")
        case 66, 67:
            return ("Freezing Rain", "cloud.sleet.fill")
        case 71, 73, 75, 77:
            return ("Snow", "cloud.snow.fill")
        case 80, 81, 82:
            return ("Showers", "cloud.heavyrain.fill")
        case 95, 96, 99:
            return ("Thunderstorm", "cloud.bolt.rain.fill")
        default:
            return ("Fair", isDay ? "sun.max.fill" : "moon.fill")
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
