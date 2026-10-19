import SwiftUI

@main
struct MacTempApp: App {
    @StateObject private var monitor = Monitor()
    @StateObject private var fans = FanController()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(monitor)
                .environmentObject(fans)
        } label: {
            MenuBarLabel(snapshot: monitor.snapshot)
        }
        .menuBarExtraStyle(.window)
    }
}

/// MenuBarExtra drops SF Symbols interpolated into Text, so the whole label
/// is drawn into a template image (the menu bar tints it for light/dark).
struct MenuBarLabel: View {
    let snapshot: Snapshot?

    var body: some View {
        Image(nsImage: rendered)
    }

    // The snapshot changes every 2 s but the visible text rarely does.
    private static var cache: (key: String, image: NSImage)?

    private var rendered: NSImage {
        let key = snapshot.map { "\(Format.temp($0.cpuTemp))|\($0.fansIdle ? "" : Format.shortRPM($0.maxFanRPM))" } ?? ""
        if let cache = Self.cache, cache.key == key { return cache.image }

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        Self.cache = (key, image)
        return image
    }

    private var content: some View {
        HStack(spacing: 3) {
            Image(systemName: "thermometer.medium")
            if let snapshot {
                Text(Format.temp(snapshot.cpuTemp))
                if !snapshot.fansIdle {
                    Image(systemName: "fan.fill").padding(.leading, 5)
                    Text(Format.shortRPM(snapshot.maxFanRPM))
                }
            }
        }
        .font(.system(size: 13))
        .monospacedDigit()
        .foregroundStyle(.black)
    }
}
