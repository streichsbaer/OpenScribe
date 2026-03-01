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
    let environmentVariableNameUsed: String?
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
        let environmentVariableName = entry.environmentVariableNames.first(where: {
            normalized(environment[$0]) != nil
        })
        let environmentValue = environmentVariableName.flatMap { normalized(environment[$0]) }

        if let keychainValue {
            return APIKeyResolution(
                value: keychainValue,
                source: .keychain,
                keychainPresent: true,
                environmentPresent: environmentValue != nil,
                environmentVariableNameUsed: environmentVariableName
            )
        }

        if let environmentValue {
            return APIKeyResolution(
                value: environmentValue,
                source: .environment,
                keychainPresent: false,
                environmentPresent: true,
                environmentVariableNameUsed: environmentVariableName
            )
        }

        return APIKeyResolution(
            value: nil,
            source: .missing,
            keychainPresent: false,
            environmentPresent: false,
            environmentVariableNameUsed: nil
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
