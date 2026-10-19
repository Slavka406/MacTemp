import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: SharedStore.load() ?? .preview))
    }

    // The menu bar app asks WidgetKit to reload; this is only a fallback.
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: Date(), snapshot: SharedStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(5 * 60))))
    }
}

@main
struct MacTempWidgetBundle: WidgetBundle {
    var body: some Widget {
        MacTempWidget()
    }
}

struct MacTempWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MacTempWidget", provider: Provider()) { entry in
            // macOS draws its own platter behind third-party widgets: plain in
            // the Default style, Liquid Glass in the Clear and Tinted styles.
            WidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Mac Temperature")
        .description("CPU and GPU temperature, fans and load.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.isStale {
            switch family {
            case .systemMedium: MediumView(s: snapshot)
            default: SmallView(s: snapshot)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "thermometer.medium.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Open MacTemp").font(.headline)
                Text("The widget shows data from the MacTemp menu bar app.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct SmallView: View {
    let s: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Ring(fraction: (s.cpuTemp ?? 0) / 100, color: Format.tempColor(s.cpuTemp), lineWidth: 8) {
                Text(Format.temp(s.cpuTemp))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 78, height: 78)

            Spacer(minLength: 0)

            Text("CPU").font(.headline)
            Text("Fans: \(Format.fans(s)) · Load \(Format.percent(s.cpuLoad))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct MediumView: View {
    let s: Snapshot

    var body: some View {
        HStack(spacing: 0) {
            cell(icon: "cpu", value: Format.temp(s.cpuTemp), label: "CPU",
                 fraction: (s.cpuTemp ?? 0) / 100, color: Format.tempColor(s.cpuTemp))
            cell(icon: "square.stack.3d.up.fill", value: s.gpuTemp == nil ? "Idle" : Format.temp(s.gpuTemp), label: "GPU",
                 fraction: (s.gpuTemp ?? 0) / 100, color: Format.tempColor(s.gpuTemp))
            cell(icon: "fan.fill", value: s.fansIdle ? "Off" : Format.shortRPM(s.maxFanRPM),
                 label: s.fansForced ? "Fans · Max" : "Fans", fraction: s.fanFraction, color: .blue)
            cell(icon: "gauge.with.dots.needle.33percent", value: Format.percent(s.cpuLoad), label: "Load",
                 fraction: s.cpuLoad, color: Format.loadColor(s.cpuLoad))
        }
    }

    private func cell(icon: String, value: String, label: String, fraction: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            Ring(fraction: fraction, color: color, lineWidth: 6) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 58, height: 58)
            VStack(spacing: 0) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Activity-ring style gauge, as in Apple's Batteries widget. The arc is
/// accentable so it keeps a colour in the Clear and Tinted widget styles.
private struct Ring<Content: View>: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat = 6
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            content
        }
        .padding(lineWidth / 2)
    }
}
