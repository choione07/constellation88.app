import SwiftUI
import UIKit

struct ResponsiveLayoutMetrics {
    let width: CGFloat
    let horizontalSizeClass: UserInterfaceSizeClass?

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var hasRegularWidthClass: Bool {
        horizontalSizeClass == .regular
    }

    var isTablet: Bool {
        if isPad {
            return hasRegularWidthClass || width >= 560
        }
        return width >= 700
    }

    var isWideTablet: Bool {
        if isPad {
            return (hasRegularWidthClass && width >= 680) || width >= 834
        }
        return width >= 820
    }

    var hidesTopLevelNavigationBar: Bool {
        true
    }

    var horizontalPadding: CGFloat {
        if isWideTablet { return (width * 0.038).rounded() }
        if isTablet { return 24 }
        return 16
    }

    var cardSpacing: CGFloat {
        isTablet ? 20 : 16
    }

    var sectionSpacing: CGFloat {
        isTablet ? 28 : 24
    }

    var contentMaxWidth: CGFloat {
        if isWideTablet { return 1180 }
        if isTablet { return 920 }
        return width
    }

    var contentWidth: CGFloat {
        max(0, min(width - (horizontalPadding * 2), contentMaxWidth))
    }

    func splitPaneWidth(fraction: CGFloat, minWidth: CGFloat, maxWidth: CGFloat) -> CGFloat {
        min(maxWidth, max(minWidth, contentWidth * fraction))
    }

    func columns(minItemWidth: CGFloat, maxCount: Int? = nil) -> [GridItem] {
        let availableWidth = max(minItemWidth, contentWidth)
        let rawCount = Int((availableWidth + cardSpacing) / (minItemWidth + cardSpacing))
        let resolvedCount = max(1, rawCount)
        let finalCount = maxCount.map { min(resolvedCount, $0) } ?? resolvedCount

        return Array(
            repeating: GridItem(.flexible(), spacing: cardSpacing, alignment: .top),
            count: finalCount
        )
    }
}
