import Foundation
import TelegramCore

// Filters the server-provided suggestion list that feeds the chat-list notice banner
// (GlobalControlPanelsContext.suggestedChatListNoticeSignal).
//
// Security- and money-critical suggestions are NEVER removed: `setupPassword` and
// `starsSubscriptionLowBalance` are excluded from every bucket here, and the notices that don't
// come from `suggestions` at all — new-login review, bot-connection review, account freeze — never
// pass through this function in the first place. Only marketing and nag items are dropped, and
// only while the matching toggle is on.
//
// `gracePremium` is deliberately left visible too: it fires only for someone who already pays and
// whose renewal failed, so hiding it silently costs them the subscription.
public enum ClearNoticeFilter {
    private static func isPromotional(_ suggestion: ServerProvidedSuggestion) -> Bool {
        switch suggestion {
        case .upgradePremium, .annualPremium, .restorePremium, .xmasPremiumGift, .setupPhoto, .setupBirthday, .link:
            // `.setupBirthday` is a nag to fill in your OWN birthday, not a contact's — it belongs
            // with the promos, not with the birthday notices.
            return true
        default:
            return false
        }
    }

    private static func isContactBirthday(_ suggestion: ServerProvidedSuggestion) -> Bool {
        if case .todayBirthdays = suggestion {
            return true
        }
        return false
    }

    public static func filterChatListSuggestions(_ suggestions: [ServerProvidedSuggestion]) -> [ServerProvidedSuggestion] {
        let hidePromo = ClearConfig.hideChatListPromoNotices
        let hideBirthdays = ClearConfig.hideChatListBirthdayNotices
        if !hidePromo && !hideBirthdays {
            return suggestions
        }
        return suggestions.filter { suggestion in
            if hidePromo && isPromotional(suggestion) {
                return false
            }
            if hideBirthdays && isContactBirthday(suggestion) {
                return false
            }
            return true
        }
    }
}
