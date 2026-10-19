import SwiftUI

enum Format {
    private static let numberLocale = Locale(identifier: "en_US")

    static func temp(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))°" } ?? "—"
    }

    static func tempC(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))°C" } ?? "—"
    }

    static func rpm(_ value: Double) -> String {
        value < 1 ? "Off" : "\(Int(value.rounded()).formatted(.number.locale(numberLocale))) rpm"
    }

    static func shortRPM(_ value: Double) -> String {
        String(format: "%.1fk", value / 1000)
    }

    static func fans(_ snapshot: Snapshot) -> String {
        if snapshot.fans.isEmpty { return "No fans" }
        if snapshot.fansForced { return "Full speed" }
        return snapshot.fansIdle ? "Off" : rpm(snapshot.maxFanRPM)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    // Apple Silicon cores sit at 70–80° under normal load; 85+ is hot.
    static func tempColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value < 65 { return .green }
        if value < 85 { return .orange }
        return .red
    }

    static func loadColor(_ fraction: Double) -> Color {
        fraction < 0.5 ? .green : fraction < 0.8 ? .orange : .red
    }

    /// Text colour for values in the menu: plain unless something needs attention.
    static func tempWarning(_ value: Double?) -> Color? {
        guard let value, value >= 80 else { return nil }
        return value < 90 ? .orange : .red
    }

    static func loadWarning(_ fraction: Double) -> Color? {
        fraction >= 0.8 ? .orange : nil
    }

    static func thermalWarning(_ raw: Int) -> Color? {
        raw == 0 ? nil : raw < 3 ? .orange : .red
    }

    /// ProcessInfo.ThermalState raw values: nominal, fair, serious, critical.
    static func thermalState(_ raw: Int) -> String {
        switch raw {
        case 0: "Normal"
        case 1: "Fair"
        case 2: "Serious"
        default: "Critical"
        }
    }
}
