import Foundation
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

@Observable
public final class BatteryOptimizationService: @unchecked Sendable {
    public static let shared = BatteryOptimizationService()
    
    public var isScreenOff: Bool = false
    public var isPowerSavingActive: Bool = false
    public var batteryLevelPercent: Int = 100
    public var isCharging: Bool = false
    
    private var stationaryCounter: Int = 0
    private let stationaryThresholdSeconds = 20
    
    private init() {
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        batteryLevelPercent = level >= 0 ? Int(level * 100) : 100
        let state = UIDevice.current.batteryState
        isCharging = (state == .charging || state == .full)
        #endif
        
        setupLifecycleObservers()
    }
    
    private func setupLifecycleObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isScreenOff = true
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isScreenOff = false
            self?.restoreFullPerformance()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let level = UIDevice.current.batteryLevel
            self?.batteryLevelPercent = level >= 0 ? Int(level * 100) : 100
        }
        
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let state = UIDevice.current.batteryState
            self?.isCharging = (state == .charging || state == .full)
        }
        #endif
    }
    
    // MARK: - Adaptive GPS Power Management
    
    /// Called with each speed fix from LocationTracker
    public func evaluatePowerState(currentSpeedKmh: Double, locationManager: CLLocationManager) {
        // If moving less than 3 km/h (stopped at light or parked)
        if currentSpeedKmh < 3.0 {
            stationaryCounter += 1
            if stationaryCounter >= stationaryThresholdSeconds && !isPowerSavingActive {
                // Engage Low Power GPS mode: reduce baseband polling
                isPowerSavingActive = true
                locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
                locationManager.distanceFilter = 15.0
            }
        } else {
            // Actively riding
            stationaryCounter = 0
            if isPowerSavingActive {
                restoreFullPerformance(locationManager: locationManager)
            }
        }
    }
    
    private func restoreFullPerformance(locationManager: CLLocationManager? = nil) {
        isPowerSavingActive = false
        stationaryCounter = 0
        locationManager?.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager?.distanceFilter = 5.0
    }
}
