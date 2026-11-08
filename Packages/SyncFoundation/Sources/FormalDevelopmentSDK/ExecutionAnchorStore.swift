import Foundation
import Security
import LocalAuthentication

@MainActor protocol ExecutionAnchorStore {
    func load() throws -> Data?
    func create(_ bytes: Data) throws
    func replace(expected: Data, with bytes: Data) throws
}

/// Fixed service/account, no delete/reset API. Never instantiated by synthetic tests.
/// Keychain is an independent anchor, not proof of Owner approval. Loss of either
/// anchor or journal is an error; enrollment is explicit and never recovery.
@MainActor final class KeychainExecutionAnchorStore: ExecutionAnchorStore {
    private let authenticationContext: LAContext = { let context = LAContext(); context.interactionNotAllowed = true; return context }()
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.yocruzer.PersonalGrowthOS.FormalSyncProbe.ExecutionGuard.v1",
         kSecAttrAccount as String: "local-execution-anchor",
         kSecAttrSynchronizable as String: false,
         kSecUseAuthenticationContext as String: authenticationContext]
    }
    func load() throws -> Data? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = result as? Data, bytes.count <= 16_384 else { throw LedgerFailure.anchorFailure }
        return bytes
    }
    func create(_ bytes: Data) throws {
        var q = query; q[kSecValueData as String] = bytes
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw LedgerFailure.anchorFailure }
    }
    func replace(expected: Data, with bytes: Data) throws {
        // The held fixed-root flock serializes cooperating clients. This read-check
        // is not a cross-device CAS and cannot defend a malicious Keychain writer.
        guard try load() == expected else { throw LedgerFailure.anchorFailure }
        guard SecItemUpdate(query as CFDictionary, [kSecValueData as String: bytes] as CFDictionary) == errSecSuccess else {
            throw LedgerFailure.anchorFailure
        }
    }
}
