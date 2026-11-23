import SwiftUI

// MARK: - Apple-Grade Minimal OLED Design System
public enum AppTheme {
    // True OLED & Apple Dark Mode Grouped Surfaces
    public static let background = Color.black                                   // #000000 Pure OLED
    public static let surface = Color(red: 0.085, green: 0.085, blue: 0.095)     // #161618
    public static let surfaceElevated = Color(red: 0.14, green: 0.14, blue: 0.155) // #242427
    public static let border = Color.white.opacity(0.08)
    public static let borderSpecular = LinearGradient(
        colors: [Color.white.opacity(0.14), Color.white.opacity(0.03)],
        startPoint: .top,
        endPoint: .bottom
    )
    public static let borderActive = Color(red: 1.0, green: 0.62, blue: 0.04).opacity(0.45)

    // Refined Apple Dark Mode Accents
    public static let accent = Color(red: 1.0, green: 0.62, blue: 0.04)          // System Amber (#FF9F0A)
    public static let accentMuted = Color(red: 1.0, green: 0.62, blue: 0.04).opacity(0.16)
    public static let emerald = Color(red: 0.19, green: 0.82, blue: 0.35)        // System Green (#30D158)
    public static let coral = Color(red: 1.0, green: 0.27, blue: 0.23)           // System Red (#FF453A)
    public static let sky = Color(red: 0.04, green: 0.52, blue: 1.0)             // System Blue (#0A84FF)
    
    // Apple Label Grayscale
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.60)
    public static let textTertiary = Color.white.opacity(0.36)
}

// MARK: - Apple-Grade Reusable Surfaces & Controls

public struct GlassCard<Content: View>: View {
    public let content: Content
    public var cornerRadius: CGFloat = 20
    public var padding: CGFloat = 18
    
    public init(cornerRadius: CGFloat = 20, padding: CGFloat = 18, @ViewBuilder content: () -> Content) {
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
                    .stroke(AppTheme.borderSpecular, lineWidth: 0.6)
            )
    }
}

public struct SectionLabel: View {
    public let text: String
    
    public init(_ text: String) {
        self.text = text
    }
    
    public var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(AppTheme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppTheme.textSecondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(accentColor)
                    .contentTransition(.numericText())
                
                if let unit = unit {
                    Text(unit)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.textTertiary)
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
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action?()
        }) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(text)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isSelected ? .black : AppTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? AppTheme.textPrimary : AppTheme.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : AppTheme.border, lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
    }
}

public struct MinimalButton: View {
    public let title: String
    public var icon: String? = nil
    public var isProminent: Bool = true
    public var tint: Color = AppTheme.accent
    public var action: () -> Void
    
    public init(title: String, icon: String? = nil, isProminent: Bool = true, tint: Color = AppTheme.accent, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isProminent = isProminent
        self.tint = tint
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            action()
        }) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(isProminent ? .black : AppTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isProminent ? tint : AppTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
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
