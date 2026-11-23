import Foundation
import CoreLocation
import Combine

@Observable
public final class LocationTracker: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let locationManager = CLLocationManager()
    
    // Live Telemetry
    public var currentSpeedKmh: Double = 0.0
    public var currentHeading: Double = 0.0
    public var currentAltitude: Double = 0.0
    public var currentLocation: CLLocationCoordinate2D?
    public var isAuthorized: Bool = false
    public var isRecordingRide: Bool = false
    
    // Ride Recording Metrics
    public var recordedDistanceMeters: Double = 0.0
    public var maxSpeedKmh: Double = 0.0
    public var rideDurationSeconds: Int = 0
    public var ridePoints: [CLLocationCoordinate2D] = []
    
    private var rideStartTime: Date?
    private var lastRecordedLocation: CLLocation?
    private var timer: Timer?
    
    // Filtering Constants (matched to OpenDash)
    private let accuracyGateMeters: Double = 25.0
    private let minMoveDistanceMeters: Double = 10.0
    private let stillSpeedMps: Double = 0.8 // ~2.8 km/h
    
    public override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5.0
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        #if os(iOS)
        locationManager.showsBackgroundLocationIndicator = true
        #endif
    }
    
    public func requestPermissions() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.requestAlwaysAuthorization()
    }
    
    public func startLiveTracking() {
        locationManager.startUpdatingLocation()
        #if os(iOS)
        locationManager.startUpdatingHeading()
        #endif
    }
    
    public func stopLiveTracking() {
        if !isRecordingRide {
            locationManager.stopUpdatingLocation()
            #if os(iOS)
            locationManager.stopUpdatingHeading()
            #endif
        }
    }
    
    // MARK: - Ride Session Controls
    
    public func startRide() {
        guard !isRecordingRide else { return }
        
        // Ensure background location is active
        #if os(iOS)
        locationManager.allowsBackgroundLocationUpdates = true
        #endif
        
        isRecordingRide = true
        BackgroundKeepAliveService.shared.startKeepAlive()
        recordedDistanceMeters = 0.0
        maxSpeedKmh = 0.0
        rideDurationSeconds = 0
        ridePoints.removeAll()
        lastRecordedLocation = nil
        rideStartTime = Date()
        
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecordingRide else { return }
            self.rideDurationSeconds += 1
        }
        
        locationManager.startUpdatingLocation()
    }
    
    public func stopRide() -> RideRecord? {
        guard isRecordingRide else { return nil }
        
        isRecordingRide = false
        timer?.invalidate()
        timer = nil
        
        #if os(iOS)
        locationManager.allowsBackgroundLocationUpdates = false
        #endif
        
        let endTime = Date()
        let startMs = Int64((rideStartTime ?? endTime).timeIntervalSince1970 * 1000)
        let endMs = Int64(endTime.timeIntervalSince1970 * 1000)
        
        let avgSpeedKmh = rideDurationSeconds > 0 ? (recordedDistanceMeters / Double(rideDurationSeconds)) * 3.6 : 0.0
        let polyline = PolylineEncoder.encode(coordinates: ridePoints)
        
        let record = RideRecord(
            startMs: startMs,
            endMs: endMs,
            distanceMeters: recordedDistanceMeters,
            durationSeconds: rideDurationSeconds,
            averageSpeedKmh: avgSpeedKmh,
            maxSpeedKmh: maxSpeedKmh,
            trackPolyline: polyline
        )
        
        return record
    }
    
    // MARK: - CLLocationManagerDelegate
    
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isAuthorized = true
            startLiveTracking()
        case .denied, .restricted:
            isAuthorized = false
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        
        currentLocation = location.coordinate
        currentAltitude = location.altitude
        WeatherService.shared.refresh(for: location.coordinate)
        
        // Filter out coarse readings for ride distance & speed tracking
        guard location.horizontalAccuracy <= accuracyGateMeters else { return }
        
        // Convert speed (m/s -> km/h)
        let speedMps = max(0.0, location.speed)
        let speedKmh = speedMps * 3.6
        currentSpeedKmh = speedKmh
        
        // Dynamically throttle GPS polling when stationary to conserve battery
        BatteryOptimizationService.shared.evaluatePowerState(currentSpeedKmh: speedKmh, locationManager: manager)
        
        // Handle ride recording accumulation
        if isRecordingRide {
            if let lastLoc = lastRecordedLocation {
                let stepDistance = location.distance(from: lastLoc)
                if stepDistance >= minMoveDistanceMeters {
                    if speedMps >= stillSpeedMps {
                        recordedDistanceMeters += stepDistance
                    }
                    if speedKmh > maxSpeedKmh {
                        maxSpeedKmh = speedKmh
                    }
                    ridePoints.append(location.coordinate)
                    lastRecordedLocation = location
                }
            } else {
                ridePoints.append(location.coordinate)
                lastRecordedLocation = location
            }
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        if newHeading.headingAccuracy >= 0 {
            currentHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }
}
