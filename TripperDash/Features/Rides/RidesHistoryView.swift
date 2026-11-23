import SwiftUI
import MapKit

public struct RidesHistoryView: View {
    @Bindable var db: DatabaseService
    
    public init(db: DatabaseService) {
        self.db = db
    }
    
    private var totalRidesDistanceKm: Double {
        db.rides.reduce(0) { $0 + $1.distanceKm }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Rides Summary Card
                        GlassCard {
                            HStack(spacing: 0) {
                                StatTile(
                                    title: "Total Rides",
                                    value: "\(db.rides.count)"
                                )
                                
                                Divider()
                                    .background(AppTheme.border)
                                    .frame(height: 36)
                                    .padding(.horizontal, 12)
                                
                                StatTile(
                                    title: "Logged Distance",
                                    value: String(format: "%.1f", totalRidesDistanceKm),
                                    unit: "km",
                                    accentColor: AppTheme.accent
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        
                        // Rides List
                        if db.rides.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "road.lanes")
                                    .font(.system(size: 32))
                                    .foregroundColor(AppTheme.textTertiary)
                                Text("No recorded rides yet")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundColor(AppTheme.textSecondary)
                                Text("Hit 'Start Ride' on the Cockpit tab to track a trip")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundColor(AppTheme.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(db.rides) { ride in
                                    NavigationLink(destination: RideDetailView(ride: ride)) {
                                        GlassCard(padding: 14) {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(ride.startDate.formatted(date: .abbreviated, time: .shortened))
                                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                        .foregroundColor(AppTheme.textPrimary)
                                                    
                                                    Text("\(ride.formattedDuration) • Max \(String(format: "%.0f", ride.maxSpeedKmh)) km/h")
                                                        .font(.system(size: 12, design: .monospaced))
                                                        .foregroundColor(AppTheme.textSecondary)
                                                }
                                                
                                                Spacer()
                                                
                                                VStack(alignment: .trailing, spacing: 2) {
                                                    Text(String(format: "%.1f km", ride.distanceKm))
                                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                                        .foregroundColor(AppTheme.accent)
                                                    
                                                    Text("Avg \(String(format: "%.0f", ride.averageSpeedKmh)) km/h")
                                                        .font(.system(size: 11, design: .monospaced))
                                                        .foregroundColor(AppTheme.textTertiary)
                                                }
                                                
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(AppTheme.textTertiary)
                                                    .padding(.leading, 6)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer(minLength: 30)
                    }
                }
            }
            .navigationTitle("Ride History")
        }
    }
}

public struct RideDetailView: View {
    public let ride: RideRecord
    
    private var coordinates: [CLLocationCoordinate2D] {
        PolylineEncoder.decode(polyline: ride.trackPolyline)
    }
    
    public var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Route Map
                    if !coordinates.isEmpty {
                        Map {
                            MapPolyline(coordinates: coordinates)
                                .stroke(AppTheme.emerald, lineWidth: 5)
                            if let start = coordinates.first {
                                Marker("Start", coordinate: start).tint(.green)
                            }
                            if let end = coordinates.last {
                                Marker("Finish", coordinate: end).tint(.red)
                            }
                        }
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }
                    
                    // Stats Grid
                    GlassCard {
                        VStack(spacing: 16) {
                            HStack {
                                StatTile(title: "Distance", value: String(format: "%.2f", ride.distanceKm), unit: "km", accentColor: AppTheme.accent)
                                Divider().background(AppTheme.border).frame(height: 36)
                                StatTile(title: "Duration", value: ride.formattedDuration)
                            }
                            Divider().background(AppTheme.border)
                            HStack {
                                StatTile(title: "Average Speed", value: String(format: "%.1f", ride.averageSpeedKmh), unit: "km/h")
                                Divider().background(AppTheme.border).frame(height: 36)
                                StatTile(title: "Max Speed", value: String(format: "%.1f", ride.maxSpeedKmh), unit: "km/h", accentColor: AppTheme.emerald)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .navigationTitle(ride.startDate.formatted(date: .abbreviated, time: .omitted))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
