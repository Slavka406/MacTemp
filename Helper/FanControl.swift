import Foundation

/// Runs as root. On Apple Silicon, `Ftst = 1` unlocks manual fan control and
/// thermalmonitord may need a few seconds before `F<n>Md` accepts manual mode.
final class FanControl {
    private let queue = DispatchQueue(label: "com.shamreliuk.MacTemp.Helper.fans")
    private var watchdog: DispatchSourceTimer?

    func setFullSpeed(_ enabled: Bool) -> String? {
        queue.sync {
            guard let smc = SMC() else { return "Can't open the SMC" }
            if enabled {
                let error = Self.forceMax(smc)
                if error == nil { startWatchdog() }
                return error
            } else {
                stopWatchdog()
                Self.restoreAuto(smc)
                return nil
            }
        }
    }

    private static func fanCount(_ smc: SMC) -> Int {
        Int(smc.double("FNum") ?? 0)
    }

    private static func forceMax(_ smc: SMC) -> String? {
        if smc.keyInfo("Ftst") != nil, !smc.write("Ftst", [1]) {
            return "Can't unlock fan control"
        }
        for fan in 0 ..< fanCount(smc) {
            guard let maxRPM = smc.double("F\(fan)Mx") else { continue }
            var manual = false
            for _ in 0 ..< 50 { // up to ~5 s
                if smc.write("F\(fan)Md", [1]) {
                    manual = true
                    break
                }
                usleep(100_000)
            }
            guard manual else { return "Fan \(fan + 1) didn't switch to manual mode" }
            let target = withUnsafeBytes(of: Float32(maxRPM)) { Array($0) }
            guard smc.write("F\(fan)Tg", target) else { return "Can't set the speed of fan \(fan + 1)" }
        }
        return nil
    }

    private static func restoreAuto(_ smc: SMC) {
        for fan in 0 ..< fanCount(smc) {
            smc.write("F\(fan)Md", [0])
        }
        if smc.keyInfo("Ftst") != nil {
            smc.write("Ftst", [0])
        }
    }

    // macOS can take fan control back; re-apply while full speed is wanted.
    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler {
            guard let smc = SMC() else { return }
            let allManual = (0 ..< Self.fanCount(smc)).allSatisfy { smc.double("F\($0)Md") == 1 }
            if !allManual { _ = Self.forceMax(smc) }
        }
        timer.resume()
        watchdog = timer
    }

    private func stopWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }
}
