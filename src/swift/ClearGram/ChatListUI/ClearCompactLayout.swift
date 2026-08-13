import CoreGraphics
import Display
import TelegramUIPreferences

public enum ClearCompactLayout {
    public static var compactChatList: Bool { ClearConfig.compactChatList }
    public static var compactMessagePreview: Bool { ClearConfig.compactMessagePreview }

    public static var avatarScaleDivisor: CGFloat {
        compactChatList ? 1.5 : (compactMessagePreview ? 1.1 : 1.0)
    }

    /// Delta added to the stock avatar origin `floor((itemHeight - avatarDiameter) / 2.0)`.
    ///
    /// Stock centres the avatar in the *row*, which at the default font size happens to coincide
    /// with the top of the title/text block (both land on 8.0 for a 76pt row with a 60pt avatar).
    /// `compactChatList` divides the row height and the avatar by 1.5 but leaves `rawContentRect`'s
    /// top inset — `floor(itemListBaseFontSize * 8.0 / 17.0)` — unscaled, so the text block hangs
    /// low while the avatar stays row-centred and visibly floats above it. Re-centre the avatar on
    /// the block instead.
    ///
    /// Returns 0.0 unless `compactChatList` is on, so stock geometry is bit-identical when off.
    public static func avatarVerticalOffset(
        itemHeight: CGFloat,
        avatarDiameter: CGFloat,
        contentTopInset: CGFloat,
        titleHeight: CGFloat,
        authorHeight: CGFloat,
        textHeight: CGFloat
    ) -> CGFloat {
        guard compactChatList else {
            return 0.0
        }
        guard titleHeight > 0.0, avatarDiameter > 0.0 else {
            return 0.0
        }
        // Degenerate rows (no preview line at all) keep the stock row-centred avatar.
        guard !textHeight.isZero || !authorHeight.isZero else {
            return 0.0
        }

        // Mirrors ChatListItemNode's title / author / text frames:
        //   title  y = contentTop
        //   author y = contentTop + titleHeight - 2
        //   text   y = contentTop + titleHeight - 2 + (authorHeight.isZero ? 0 : authorHeight - 3)
        var contentBlockHeight = titleHeight
        if !authorHeight.isZero {
            contentBlockHeight += authorHeight - 3.0
        }
        if !textHeight.isZero {
            contentBlockHeight += textHeight - 2.0
        }
        guard contentBlockHeight > 0.0 else {
            return 0.0
        }

        let stockOriginY = floor((itemHeight - avatarDiameter) / 2.0)
        let centeredOriginY = floorToScreenPixels(contentTopInset + (contentBlockHeight - avatarDiameter) / 2.0)
        let clampedOriginY = max(0.0, min(centeredOriginY, max(0.0, itemHeight - avatarDiameter)))
        return clampedOriginY - stockOriginY
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
