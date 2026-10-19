import Foundation
import WidgetKit

@MainActor
final class Monitor: ObservableObject {
    @Published private(set) var snapshot: Snapshot?

    /// `ps` is only run while the panel is open; the menu bar label and the
    /// widget don't need the process list.
    var panelVisible = false {
        didSet { if panelVisible { refresh() } }
    }

    private let sampler = Sampler()
    private let queue = DispatchQueue(label: "MacTemp.sampler", qos: .utility)
    private var timer: Timer?
    private var lastWidgetReload = Date.distantPast

    init() {
        refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        let includeProcesses = panelVisible
        queue.async { [weak self, sampler] in
            let snapshot = sampler.sample(includeProcesses: includeProcesses)
            DispatchQueue.main.async { self?.apply(snapshot) }
        }
    }

    private func apply(_ new: Snapshot) {
        var new = new
        if new.topProcesses.isEmpty, let old = snapshot {
            new.topProcesses = old.topProcesses
        }
        snapshot = new
        SharedStore.save(new)

        // WidgetKit throttles reloads anyway; once a minute is plenty.
        if Date().timeIntervalSince(lastWidgetReload) >= 60 {
            lastWidgetReload = Date()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
