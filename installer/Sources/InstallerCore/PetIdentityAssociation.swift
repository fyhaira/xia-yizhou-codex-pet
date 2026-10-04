import Foundation

public struct PetIdentityAssociationResolver: Sendable {
    public init() {}

    public func resolve(stablePetID: String, effectivePetID: String, globalStateURL: URL) throws -> VerifiedPetIdentityAlias? {
        if effectivePetID == stablePetID || effectivePetID == "custom:\(stablePetID)" { return nil }
        guard effectivePetID.hasPrefix("pet_"), effectivePetID.range(of: #"^pet_[A-Za-z0-9]+$"#, options: .regularExpression) != nil else {
            throw InstallerError.message("Effective pet identity is not the installer-owned local pet or a supported cloud identity")
        }
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: globalStateURL)) as? [String: Any],
              let persisted = root["electron-persisted-atom-state"] as? [String: Any],
              let migrations = persisted["migrated-cloud-pet-ids-v1"] as? [String: Any],
              let cache = persisted["cloud-pet-artwork-cache"] as? [String: Any],
              let pets = cache["pets"] as? [[String: Any]] else {
            throw InstallerError.message("Verified cloud-pet association metadata is unavailable")
        }

        let localKey = "custom:\(stablePetID)"
        var stableMappings: [String] = []
        var reverseMappings: [String] = []
        for value in migrations.values {
            guard let scope = value as? [String: Any] else { continue }
            if let mapped = scope[localKey] as? String { stableMappings.append(mapped) }
            for (source, destination) in scope where destination as? String == effectivePetID { reverseMappings.append(source) }
        }
        let uniqueStableMappings = Set(stableMappings)
        guard uniqueStableMappings.count == 1, uniqueStableMappings.first == effectivePetID else {
            throw InstallerError.message("Cloud pet prefix is present but no unique installer-owned migration mapping proves the association")
        }
        guard Set(reverseMappings) == Set([localKey]) else {
            throw InstallerError.message("Cloud pet identity is ambiguously associated with another local pet")
        }

        let matchingPets = pets.filter { $0["id"] as? String == effectivePetID }
        guard matchingPets.count == 1,
              let fingerprint = matchingPets[0]["spritesheetFingerprint"] as? String,
              fingerprint.count <= 512,
              validFingerprint(fingerprint) else {
            throw InstallerError.message("Cloud pet fingerprint evidence is absent, corrupt, or ambiguous")
        }
        return VerifiedPetIdentityAlias(stableLocalPetID: stablePetID, effectiveRuntimePetID: effectivePetID, spritesheetFingerprint: fingerprint)
    }

    private func validFingerprint(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              array.count == 3,
              let width = array[0] as? Int, let height = array[1] as? Int,
              width > 0, height > 0,
              let digest = array[2] as? [Int], digest.count == 32 else { return false }
        return digest.allSatisfy { (0...255).contains($0) }
    }
}
