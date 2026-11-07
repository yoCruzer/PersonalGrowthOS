import Foundation

// A per-run opt-in, never decoded from a command/document or stored in defaults.
public struct DevelopmentAuthorization: Sendable {
    private let approved: Bool
    public var isEnabled: Bool {
        #if DEBUG
        approved
        #else
        false
        #endif
    }
    public static func fromEnvironment() -> Self {
        Self(approved: ProcessInfo.processInfo.environment["SYNCLAB_ENABLE_DEVELOPMENT"] == "YES")
    }
    #if DEBUG
    // Called only by the explicit manual-test button after validating the plan.
    public static func afterExplicitManualConsent() -> Self { Self(approved: true) }
    #endif
}
