import Foundation

struct TransitRideProgress {
    let remaining: Double
    let offRoute: Bool
    let notifyAlighting: Bool
    let passedStop: Bool
}

struct TransitProgressEngine {
    let path: [GeoPoint]
    let destination: GeoPoint
    private var traveled = 0.0
    private var previous: WalkingFix?
    private var nearSince: Date?
    private var nearCount = 0
    private var notified = false

    mutating func update(_ fix: WalkingFix, now: Date) -> TransitRideProgress? {
        guard fix.isReliable(at: now), path.count > 1 else {
            nearSince = nil
            nearCount = 0
            return nil
        }
        if let previous {
            let interval = fix.timestamp.timeIntervalSince(previous.timestamp)
            guard interval > 0, fix.point.distance(to: previous.point) <= interval * 55 + fix.accuracy + previous.accuracy else {
                nearSince = nil
                nearCount = 0
                return nil
            }
        }
        let advance = previous.map { max(100, fix.timestamp.timeIntervalSince($0.timestamp) * 55 + fix.accuracy) } ?? 500
        let scale = cos(fix.point.latitude * .pi / 180)
        var cumulative = 0.0
        var nearest = Double.infinity
        var chosen: (distance: Double, along: Double)?
        for (a, b) in zip(path, path.dropFirst()) {
            let x = (b.longitude - a.longitude) * scale * 111195
            let y = (b.latitude - a.latitude) * 111195
            let px = (fix.point.longitude - a.longitude) * scale * 111195
            let py = (fix.point.latitude - a.latitude) * 111195
            let squared = x*x + y*y
            let t = squared > 0 ? min(1, max(0, (px*x + py*y) / squared)) : 0
            let length = a.distance(to: b)
            let distance = hypot(px - t*x, py - t*y)
            let along = cumulative + t*length
            nearest = min(nearest, distance)
            if along >= traveled - 30 && along <= traveled + advance && distance < (chosen?.distance ?? .infinity) {
                chosen = (distance, along)
            }
            cumulative += length
        }
        previous = fix
        guard nearest <= max(60, fix.accuracy * 2), let chosen,
              chosen.distance <= max(60, nearest + 10) else {
            nearSince = nil
            nearCount = 0
            return .init(remaining: max(0, cumulative - traveled), offRoute: true, notifyAlighting: false,
                passedStop: traveled >= cumulative - 40 && fix.point.distance(to: destination) > 150)
        }
        traveled = max(traveled, chosen.along)
        let remaining = max(0, cumulative - traveled)
        var notify = false
        if remaining <= 350 && path.last!.distance(to: destination) <= 25 {
            nearCount += 1
            if nearSince == nil { nearSince = fix.timestamp }
            if nearCount >= 3, fix.timestamp.timeIntervalSince(nearSince!) >= 5, !notified {
                notified = true
                notify = true
            }
        } else { nearSince = nil; nearCount = 0 }
        return .init(remaining: remaining, offRoute: false, notifyAlighting: notify,
            passedStop: traveled >= cumulative - 40 && fix.point.distance(to: destination) > 150)
    }
}
