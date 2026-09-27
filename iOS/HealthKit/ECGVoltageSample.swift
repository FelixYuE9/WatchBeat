import Foundation
import HealthKit

/// One voltage measurement between the HealthKit query and the mapper.
///
/// This still carries an `HKQuantity` because unit conversion belongs to the mapper boundary, not to
/// the query. No sample is dropped here: an absent or incompatible quantity stays `nil`.
public struct ECGVoltageSample {
    public let timeSinceSampleStart: TimeInterval
    public let quantity: HKQuantity?

    public init(timeSinceSampleStart: TimeInterval, quantity: HKQuantity?) {
        self.timeSinceSampleStart = timeSinceSampleStart
        self.quantity = quantity
    }
}
