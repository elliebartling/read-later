import Foundation
import SwiftData

// CloudKit rules apply: attributes optional or defaulted, relationships optional.
@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#8E8E93"
    var articles: [Article]?

    init(id: UUID = UUID(), name: String, colorHex: String = "#8E8E93") {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}
