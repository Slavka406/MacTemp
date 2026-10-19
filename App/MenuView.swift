import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Laid out like the system's Control Center modules (Wi-Fi, Battery):
/// bold section titles, 26 pt circular icons, mini switches, hover rows.
struct MenuView: View {
    @EnvironmentObject private var monitor: Monitor
    @EnvironmentObject private var fans: FanController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snapshot = monitor.snapshot {
                temperatureSection(snapshot)
                separator
                fanSection(snapshot)
                separator
                cpuSection(snapshot)
            } else {
                Text("Reading sensors…")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
            }

            separator

            HStack {
                Text("Launch at Login")
                Spacer()
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            HoverRow(action: { NSApplication.shared.terminate(nil) }) {
                Text("Quit MacTemp")
                Spacer()
                Text("⌘Q").foregroundStyle(.secondary)
            }
            .keyboardShortcut("q")
        }
        .padding(6)
        .frame(width: 300)
        .onAppear {
            monitor.panelVisible = true
            fans.refreshStatus()
        }
        .onDisappear { monitor.panelVisible = false }
        .onReceive(monitor.$snapshot) { snapshot in
            if let snapshot { fans.reconcile(with: snapshot) }
            if fans.status == .requiresApproval { fans.refreshStatus() }
        }
    }

    // MARK: Sections

    private func temperatureSection(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Temperature")
            InfoRow(icon: "cpu", title: "CPU", subtitle: "Peak \(Format.tempC(s.cpuTempMax))") {
                Value(Format.tempC(s.cpuTemp), color: Format.tempWarning(s.cpuTemp))
            }
            InfoRow(icon: "square.stack.3d.up.fill", title: "GPU") {
                Value(s.gpuTemp == nil ? "Idle" : Format.tempC(s.gpuTemp), color: Format.tempWarning(s.gpuTemp))
            }
            InfoRow(icon: "thermometer.medium", title: "Thermal Pressure") {
                Value(Format.thermalState(s.thermalState), color: Format.thermalWarning(s.thermalState))
            }
        }
    }

    private func fanSection(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("Fans") {
                Text("Full Speed").foregroundStyle(.secondary)
                Toggle("Full Speed", isOn: Binding(
                    get: { fans.pending ?? s.fansForced },
                    set: { fans.setFullSpeed($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(s.fans.isEmpty)
            }

            if let pending = fans.pending {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(pending ? "Switching to full speed…" : "Returning to automatic…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }

            if fans.status == .requiresApproval {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Allow MacTemp in Login Items to control the fans.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items…") { fans.openLoginItems() }
                        .controlSize(.small)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }

            if let error = fans.error {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    if fans.helperUnreachable {
                        Button("Open Login Items…") { fans.openLoginItems() }
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }

            if s.fans.isEmpty {
                Text("This Mac has no fans").foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            ForEach(Array(s.fans.enumerated()), id: \.offset) { index, fan in
                InfoRow(icon: "fan.fill", active: fan.rpm >= 1, title: "Fan \(index + 1)") {
                    Value(Format.rpm(fan.rpm))
                }
            }
        }
    }

    private func cpuSection(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle("CPU Usage") {
                Value(Format.percent(s.cpuLoad), color: Format.loadWarning(s.cpuLoad))
            }
            if s.topProcesses.isEmpty {
                Text("…").foregroundStyle(.secondary).padding(.horizontal, 8)
            }
            ForEach(Array(s.topProcesses.enumerated()), id: \.offset) { _, process in
                HStack(spacing: 8) {
                    Image(nsImage: ProcessIcons.icon(for: process.pid))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(process.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(process.cpu < 1 ? "<1%" : "\(Int(process.cpu.rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            }
        }
    }

    private var separator: some View {
        Divider()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }

    // MARK: Helpers

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct SectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 13, weight: .bold))
            Spacer()
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }
}

private struct Value: View {
    let text: String
    var color: Color?

    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
    }
}

/// Control Center style row: circular icon, title (+ subtitle), trailing value.
private struct InfoRow<Trailing: View>: View {
    let icon: String
    var active = false
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            IconCircle(systemName: icon, active: active)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}

/// Accent-filled when active, gray otherwise — like the Wi-Fi and Bluetooth
/// device icons in Control Center.
private struct IconCircle: View {
    let systemName: String
    var active: Bool

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(active ? Color.white : Color.primary)
            .frame(width: 26, height: 26)
            .background(Circle().fill(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary)))
    }
}

/// Menu-like row that highlights under the pointer.
private struct HoverRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack { content }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        )
        .onHover { hovering = $0 }
    }
}

/// Icon of the app a process belongs to (helpers inside Foo.app get Foo's
/// icon); system daemons, or processes we can't inspect, get the generic one.
@MainActor
private enum ProcessIcons {
    private static var cache: [String: NSImage] = [:]
    private static let generic = NSWorkspace.shared.icon(for: .unixExecutable)

    static func icon(for pid: Int32) -> NSImage {
        guard let app = appPath(for: pid) else { return generic }
        if let cached = cache[app] { return cached }
        let image = NSWorkspace.shared.icon(forFile: app)
        cache[app] = image
        return image
    }

    private static func appPath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
}
