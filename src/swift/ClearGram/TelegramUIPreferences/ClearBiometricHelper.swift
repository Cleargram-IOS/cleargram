import Foundation
import LocalAuthentication
import SwiftSignalKit

// Second-factor gate for destructive actions (delete chat / clear history / logout).
//
// Fail-CLOSED by design: once `enabled` is true, `onSuccess` runs only after a successful
// evaluation. The policy is `.deviceOwnerAuthentication` (not `...WithBiometrics`) so that
// biometry lockout, a denied Face ID permission or missing enrollment fall back to the device
// passcode instead of silently disabling the gate. Only a device with no passcode at all
// cannot evaluate — and there the gate reports failure rather than waving the action through.
//
// A fresh LAContext is created per call: a reused context caches a previous success and would
// let the second destructive action through without a prompt.
public enum ClearBiometricHelper {
    // `onSuccess` MUST stay the last parameter: every call site passes it as an unlabeled
    // trailing closure, and Swift's trailing-closure matching scans the parameter list backwards.
    // Putting `onFailure` last would silently bind the destructive action to the failure handler.
    public static func gate(
        reason: String,
        enabled: Bool,
        onFailure: (() -> Void)? = nil,
        onSuccess: @escaping () -> Void
    ) {
        if !enabled {
            onSuccess()
            return
        }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            print("ClearBiometricHelper: cannot evaluate policy — \(error?.localizedDescription ?? "unknown"); blocking action")
            Queue.mainQueue().async { onFailure?() }
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason, reply: { result, error in
            Queue.mainQueue().async {
                if result {
                    onSuccess()
                } else {
                    print("ClearBiometricHelper: authentication failed — \(error?.localizedDescription ?? "cancelled")")
                    onFailure?()
                }
            }
        })
    }
}
