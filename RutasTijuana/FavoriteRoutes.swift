import Foundation

enum FavoriteRoutes {
    static func decode(_ data: Data) -> [String] {
        (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    static func toggle(_ id: String, in data: Data) -> Data {
        var ids = decode(data)
        if ids.contains(id) { ids.removeAll { $0 == id } }
        else { ids.append(id) }
        return (try? JSONEncoder().encode(ids)) ?? data
    }
}
