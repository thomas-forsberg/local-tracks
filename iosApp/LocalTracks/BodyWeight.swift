import Foundation
import Shared

// The user's weight, for calories; kept only on this phone. 0 means not set.
enum BodyWeight {
    static let key = "bodyWeightKilograms"

    // Nil when the weight isn't set or the activity has no energy yet.
    static func kcal(perKg: Double?, weightKilograms: Double) -> Int? {
        guard let perKg, weightKilograms > 0 else { return nil }
        return Int(EnergyKt.activeKcal(kcalPerKg: perKg, weightKilograms: weightKilograms))
    }
}
