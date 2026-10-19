import Foundation

struct FanReading: Codable, Hashable, Sendable {
    var rpm: Double
    var min: Double
    var max: Double
    /// Forced by MacTempHelper instead of macOS's automatic control.
    var manual: Bool
}

struct ProcessReading: Codable, Hashable, Sendable {
    var pid: Int32
    var name: String
    /// Percent of the whole CPU (all cores), 0…100.
    var cpu: Double
}

struct Snapshot: Codable, Sendable {
    var date: Date
    var cpuTemp: Double?
    var cpuTempMax: Double?
    var gpuTemp: Double?
    var fans: [FanReading]
    var cpuLoad: Double
    var thermalState: Int
    var topProcesses: [ProcessReading]

    var maxFanRPM: Double { fans.map(\.rpm).max() ?? 0 }
    var fansIdle: Bool { maxFanRPM < 1 }
    var fansForced: Bool { fans.contains(where: \.manual) }
    var fanFraction: Double {
        let top = fans.map(\.max).max() ?? 0
        return top > 0 ? maxFanRPM / top : 0
    }
    var isStale: Bool { Date().timeIntervalSince(date) > 15 * 60 }

    static let preview = Snapshot(
        date: Date(),
        cpuTemp: 54,
        cpuTempMax: 68,
        gpuTemp: 47,
        fans: [FanReading(rpm: 0, min: 2317, max: 6800, manual: false), FanReading(rpm: 0, min: 2317, max: 6800, manual: false)],
        cpuLoad: 0.18,
        thermalState: 0,
        topProcesses: []
    )
}

/// The menu bar app writes the latest snapshot here; the sandboxed widget
/// can't touch the SMC itself, so it only reads this file.
enum SharedStore {
    // Matches $(TeamIdentifierPrefix)com.shamreliuk.MacTemp in Support/*.entitlements.
    static let appGroup = "\(CodeSigning.teamID).com.shamreliuk.MacTemp"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("snapshot.json")
    }

    static func save(_ snapshot: Snapshot) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> Snapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}
