import Foundation
import LocalAuth
import SwiftSignalKit

public enum ClearBiometricHelper {
    public static func gate(reason: String, enabled: Bool, onSuccess: @escaping () -> Void) {
        if !enabled || LocalAuth.biometricAuthentication == nil {
            onSuccess()
            return
        }
        let _ = (LocalAuth.auth(reason: reason) |> deliverOnMainQueue).start(next: { result, _ in
            if result {
                onSuccess()
            }
        })
    }
}
