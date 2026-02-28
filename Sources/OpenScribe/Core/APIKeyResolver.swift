import Foundation

enum APIKeySource {
    case keychain
    case environment
    case missing
}

struct APIKeyResolution {
    let value: String?
    let source: APIKeySource
    let keychainPresent: Bool
    let environmentPresent: Bool
}

struct APIKeyResolver {
    private let keychain: KeychainStore
    private let environment: [String: String]

    init(
        keychain: KeychainStore,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.keychain = keychain
        self.environment = environment
    }

    func resolve(_ entry: KeychainEntry) -> APIKeyResolution {
        let keychainValue = normalized(keychain.load(entry))
        let environmentValue = normalized(environment[entry.environmentVariableName])

        if let keychainValue {
            return APIKeyResolution(
                value: keychainValue,
                source: .keychain,
                keychainPresent: true,
                environmentPresent: environmentValue != nil
            )
        }

        if let environmentValue {
            return APIKeyResolution(
                value: environmentValue,
                source: .environment,
                keychainPresent: false,
                environmentPresent: true
            )
        }

        return APIKeyResolution(
            value: nil,
            source: .missing,
            keychainPresent: false,
            environmentPresent: false
        )
    }

    private func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
