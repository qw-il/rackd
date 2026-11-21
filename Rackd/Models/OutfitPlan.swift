import Foundation
import SwiftData

/// An outfit scheduled (or logged as worn) on a calendar day.
@Model
final class OutfitPlan {
    var id: UUID = UUID()
    /// Always the start of a day in the user's calendar.
    var date: Date = Date()
    var note: String = ""
    var outfit: Outfit?

    init(date: Date, outfit: Outfit) {
        self.id = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.outfit = outfit
    }
}
