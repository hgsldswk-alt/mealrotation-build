import Foundation

struct MenuItem: Codable, Equatable, Identifiable {
    var name: String
    var quick: Bool?
    var id: String { Rotation.nameKey(name) }
    init(name: String, quick: Bool = false) {
        self.name = name
        self.quick = quick ? true : nil
    }
}
