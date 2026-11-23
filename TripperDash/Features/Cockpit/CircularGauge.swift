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
    
    private var activeColor: Color {
        isRecording ? AppTheme.emerald : AppTheme.accent
    }
    
    public var body: some View {
        ZStack {
            // Subtle precision watch-style tick ring
            ForEach(0..<37, id: \.self) { index in
                let isMajor = index % 6 == 0
                Rectangle()
                    .fill(isMajor ? Color.white.opacity(0.28) : Color.white.opacity(0.10))
                    .frame(width: isMajor ? 1.5 : 1, height: isMajor ? 8 : 4)
                    .offset(y: -102)
                    .rotationEffect(.degrees(-126 + Double(index) * 7.0))
            }
            
            // Recessed Background Track
            Circle()
                .trim(from: 0.15, to: 0.85)
                .stroke(
                    Color.white.opacity(0.08),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .padding(16)
            
            // Precision Active Speed Arc
            Circle()
                .trim(from: 0.15, to: 0.15 + (progress * 0.70))
                .stroke(
                    LinearGradient(
                        colors: [activeColor.opacity(0.75), activeColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .padding(16)
                .shadow(color: activeColor.opacity(0.35), radius: 10)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: progress)
            
            // Crisp Apple Watch Ultra-style Center Readout
            VStack(spacing: 4) {
                HStack(spacing: 5) {
                    if isRecording {
                        Circle()
                            .fill(AppTheme.emerald)
                            .frame(width: 6, height: 6)
                    }
                    Text(headingToCompass(heading))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
                
                Text(String(format: "%.0f", speed))
                    .font(.system(size: 74, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(AppTheme.textPrimary)
                    .contentTransition(.numericText())
                
                Text("km/h")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.textTertiary)
            }
        }
        .frame(width: 264, height: 264)
    }
    
    private func headingToCompass(_ degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5) / 45.0) & 7
        return "\(directions[index]) · \(Int(degrees))°"
    }
}
