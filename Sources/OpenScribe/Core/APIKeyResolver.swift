import Foundation

enum APIKeySource: Equatable {
    case keychain
    case missing
}

struct APIKeyResolution {
    let value: String?
    let source: APIKeySource
    let keychainPresent: Bool
}

struct APIKeyResolver {
    private let keychain: KeychainStore

    init(keychain: KeychainStore) {
        self.keychain = keychain
    }

    func resolve(_ entry: KeychainEntry) -> APIKeyResolution {
        let keychainValue = normalized(keychain.load(entry))

        if let keychainValue {
            return APIKeyResolution(
                value: keychainValue,
                source: .keychain,
                keychainPresent: true
            )
        }

        return APIKeyResolution(
            value: nil,
            source: .missing,
            keychainPresent: false
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
