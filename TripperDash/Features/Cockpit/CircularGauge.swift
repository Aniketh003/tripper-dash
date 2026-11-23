import SwiftUI

public struct CircularGauge: View {
    public let speed: Double
    public let maxScale: Double
    public let heading: Double
    public let isRecording: Bool
    
    public init(speed: Double, maxScale: Double = 180.0, heading: Double = 0.0, isRecording: Bool = false) {
        self.speed = speed
        self.maxScale = maxScale
        self.heading = heading
        self.isRecording = isRecording
    }
    
    private var progress: Double {
        min(max(speed / maxScale, 0.0), 1.0)
    }
    
    public var body: some View {
        ZStack {
            // Background Track
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(
                    AppTheme.surfaceElevated,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
            
            // Active Speed Arc
            Circle()
                .trim(from: 0.15, to: 0.15 + (progress * 0.70))
                .stroke(
                    isRecording ? AppTheme.emerald : AppTheme.accent,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.8), value: progress)
            
            // Speed Readout
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isRecording ? AppTheme.emerald : Color.clear)
                        .frame(width: 6, height: 6)
                    
                    Text(headingToCompass(heading))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.textSecondary)
                }
                
                Text(String(format: "%.0f", speed))
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary)
                    .contentTransition(.numericText())
                
                Text("KM/H")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                    .tracking(2)
            }
        }
        .frame(width: 240, height: 240)
    }
    
    private func headingToCompass(_ degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5) / 45.0) & 7
        return directions[index]
    }
}
