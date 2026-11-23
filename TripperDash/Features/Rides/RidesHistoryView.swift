import SwiftUI
import MapKit

public struct RidesHistoryView: View {
    @Bindable var db: DatabaseService
    public var embedded: Bool = false
    
    public init(db: DatabaseService, embedded: Bool = false) {
        self.db = db
        self.embedded = embedded
    }
    
    private var totalRidesDistanceKm: Double {
        db.rides.reduce(0) { $0 + $1.distanceKm }
    }
    
    public var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .navigationTitle("Rides")
            }
        }
    }
    
    private var content: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    GlassCard {
                        HStack(spacing: 0) {
                            StatTile(title: "Total Rides", value: "\(db.rides.count)")
                            Rectangle()
                                .fill(AppTheme.border)
                                .frame(width: 0.6, height: 34)
                                .padding(.horizontal, 12)
                            StatTile(
                                title: "Distance",
                                value: String(format: "%.1f", totalRidesDistanceKm),
                                unit: "km",
                                accentColor: AppTheme.accent
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    if db.rides.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "road.lanes")
                                .font(.system(size: 34, weight: .light))
                                .foregroundColor(AppTheme.textTertiary)
                            Text("No rides recorded yet")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppTheme.textPrimary)
                            Text("Tap Start Ride on Cockpit to log your first journey.")
                                .font(.system(size: 13))
                                .foregroundColor(AppTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                        .padding(.horizontal, 32)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(db.rides) { ride in
                                NavigationLink(destination: RideDetailView(ride: ride)) {
                                    GlassCard(cornerRadius: 16, padding: 15) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(ride.startDate.formatted(date: .abbreviated, time: .shortened))
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundColor(AppTheme.textPrimary)
                                                
                                                Text("\(ride.formattedDuration) · Max \(String(format: "%.0f", ride.maxSpeedKmh)) km/h")
                                                    .font(.system(size: 12, design: .rounded))
                                                    .monospacedDigit()
                                                    .foregroundColor(AppTheme.textSecondary)
                                            }
                                            
                                            Spacer()
                                            
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text(String(format: "%.1f km", ride.distanceKm))
                                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                                    .monospacedDigit()
                                                    .foregroundColor(AppTheme.accent)
                                                
                                                Text("Avg \(String(format: "%.0f", ride.averageSpeedKmh)) km/h")
                                                    .font(.system(size: 11, design: .rounded))
                                                    .monospacedDigit()
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
                    
                    Spacer(minLength: 32)
                }
            }
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
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(AppTheme.borderSpecular, lineWidth: 0.6)
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }
                    
                    GlassCard {
                        VStack(spacing: 16) {
                            HStack {
                                StatTile(title: "Distance", value: String(format: "%.2f", ride.distanceKm), unit: "km", accentColor: AppTheme.accent)
                                Rectangle().fill(AppTheme.border).frame(width: 0.6, height: 34).padding(.horizontal, 12)
                                StatTile(title: "Duration", value: ride.formattedDuration)
                            }
                            Divider().background(AppTheme.border)
                            HStack {
                                StatTile(title: "Average", value: String(format: "%.1f", ride.averageSpeedKmh), unit: "km/h")
                                Rectangle().fill(AppTheme.border).frame(width: 0.6, height: 34).padding(.horizontal, 12)
                                StatTile(title: "Top Speed", value: String(format: "%.1f", ride.maxSpeedKmh), unit: "km/h", accentColor: AppTheme.emerald)
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
