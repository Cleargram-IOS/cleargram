import CoreGraphics
import Display
import TelegramUIPreferences

public enum ClearCompactLayout {
    public static var compactChatList: Bool { ClearConfig.compactChatList }
    public static var compactMessagePreview: Bool { ClearConfig.compactMessagePreview }

    public static var avatarScaleDivisor: CGFloat {
        compactChatList ? 1.5 : (compactMessagePreview ? 1.1 : 1.0)
    }

    public static func badgeOffset(sizeFactor: CGFloat) -> CGFloat {
        guard compactMessagePreview && !compactChatList else {
            return 0.0
        }

        let sizeRange: CGFloat = 0.5
        let maxLift: CGFloat = 16.0
        let maxDownshift: CGFloat = 24.0
        let sizeDelta = sizeFactor - 1.0
        let lift: CGFloat
        if sizeDelta >= 0.0 {
            let sizeGrow = min(sizeRange, sizeDelta)
            let sizeGrowFactor = sizeGrow / sizeRange
            lift = maxLift * sizeGrowFactor * sizeGrowFactor * (3.0 - 2.0 * sizeGrowFactor)
        } else {
            let sizeShrink = min(sizeRange, -sizeDelta)
            let sizeShrinkFactor = sizeShrink / sizeRange
            let downshift = maxDownshift * sizeShrinkFactor * sizeShrinkFactor * (3.0 - 2.0 * sizeShrinkFactor)
            lift = -downshift
        }

        return floorToScreenPixels(lift)
    }

    public static func textVerticalOffset(sizeFactor: CGFloat, hasAuthorLine: Bool) -> CGFloat {
        guard compactMessagePreview && !compactChatList && !hasAuthorLine else {
            return 0.0
        }
        return floorToScreenPixels(6.0 * sizeFactor)
    }

    public static func titleTextSpacing(sizeFactor: CGFloat, hasAuthorLine: Bool) -> CGFloat {
        guard compactMessagePreview && !compactChatList && !hasAuthorLine else {
            return 0.0
        }
        return floorToScreenPixels(6.0 * sizeFactor)
    }

    public static func textBlockOffset(sizeFactor: CGFloat, hasAuthorLine: Bool) -> CGFloat {
        textVerticalOffset(sizeFactor: sizeFactor, hasAuthorLine: hasAuthorLine)
        + titleTextSpacing(sizeFactor: sizeFactor, hasAuthorLine: hasAuthorLine)
    }
}
