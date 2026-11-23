import SwiftUI

// MARK: - Minimal Theme Palette
public enum AppTheme {
    // Pure OLED & Surface tones
    public static let background = Color(red: 0.02, green: 0.02, blue: 0.03)      // #050508
    public static let surface = Color(red: 0.07, green: 0.07, blue: 0.09)         // #121217
    public static let surfaceElevated = Color(red: 0.11, green: 0.11, blue: 0.14) // #1C1C24
    public static let border = Color.white.opacity(0.08)
    public static let borderActive = Color(red: 0.95, green: 0.65, blue: 0.22).opacity(0.35)

    // Rally Accent Colors
    public static let accent = Color(red: 0.95, green: 0.65, blue: 0.22)         // Amber Gold (#F2A638)
    public static let accentMuted = Color(red: 0.95, green: 0.65, blue: 0.22).opacity(0.15)
    public static let emerald = Color(red: 0.16, green: 0.75, blue: 0.52)        // Smooth Emerald
    public static let coral = Color(red: 0.95, green: 0.35, blue: 0.35)          // Soft Warning Red
    
    // Typography Grayscale
    public static let textPrimary = Color.white
    public static let textSecondary = Color(red: 0.62, green: 0.63, blue: 0.68)
    public static let textTertiary = Color(red: 0.40, green: 0.41, blue: 0.46)
}

// MARK: - Minimalist Reusable UI Components

public struct GlassCard<Content: View>: View {
    public let content: Content
    public var cornerRadius: CGFloat = 16
    public var padding: CGFloat = 16
    
    public init(cornerRadius: CGFloat = 16, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }
    
    public var body: some View {
        content
            .padding(padding)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
    }
}

public struct StatTile: View {
    public let title: String
    public let value: String
    public let unit: String?
    public var accentColor: Color = AppTheme.textPrimary
    
    public init(title: String, value: String, unit: String? = nil, accentColor: Color = AppTheme.textPrimary) {
        self.title = title
        self.value = value
        self.unit = unit
        self.accentColor = accentColor
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
                .tracking(0.8)
            
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)
                
                if let unit = unit {
                    Text(unit)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct PillBadge: View {
    public let text: String
    public var icon: String? = nil
    public var isSelected: Bool = false
    public var action: (() -> Void)? = nil
    
    public init(text: String, icon: String? = nil, isSelected: Bool = false, action: (() -> Void)? = nil) {
        self.text = text
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            action?()
        }) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(text)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundColor(isSelected ? AppTheme.accent : AppTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? AppTheme.accentMuted : AppTheme.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? AppTheme.accent.opacity(0.5) : AppTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

public struct MinimalButton: View {
    public let title: String
    public var icon: String? = nil
    public var isProminent: Bool = true
    public var action: () -> Void
    
    public init(title: String, icon: String? = nil, isProminent: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isProminent = isProminent
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            #endif
            action()
        }) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isProminent ? .black : AppTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isProminent ? AppTheme.accent : AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isProminent ? Color.clear : AppTheme.border, lineWidth: 1)
            )
        }
    }
}

// MARK: - Cross-Platform Compatibility Shims for macOS Preview / Building
#if !os(iOS)
public enum UIKeyboardType {
    case decimalPad
    case numberPad
    case `default`
    case emailAddress
}

public struct NavigationBarItemTitleDisplayModeShim {
    public static let inline = NavigationBarItemTitleDisplayModeShim()
    public static let large = NavigationBarItemTitleDisplayModeShim()
    public static let automatic = NavigationBarItemTitleDisplayModeShim()
}

public final class UINotificationFeedbackGenerator {
    public enum FeedbackType { case success, warning, error }
    public init() {}
    public func notificationOccurred(_ notificationType: FeedbackType) {}
}

public final class UIImpactFeedbackGenerator {
    public enum FeedbackStyle { case light, medium, heavy, soft, rigid }
    public init(style: FeedbackStyle) {}
    public func impactOccurred() {}
}

extension View {
    public func keyboardType(_ type: UIKeyboardType) -> some View {
        self
    }
    
    public func navigationBarTitleDisplayMode(_ mode: NavigationBarItemTitleDisplayModeShim) -> some View {
        self
    }
    
    public func navigationBarHidden(_ hidden: Bool) -> some View {
        self
    }
}
#endif
