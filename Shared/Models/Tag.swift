import Foundation
import SwiftData

@Model
final class Tag {
    var id: UUID
    var name: String
    var colorHex: String
    var articles: [Article] = []

    init(id: UUID = UUID(), name: String, colorHex: String = "#8E8E93") {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}
