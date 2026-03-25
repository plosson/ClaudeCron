import Foundation
import SwiftData

@Model
final class ClaudeTask {
    var id: UUID = UUID()
    var name: String = ""

    init() {}
}
