import Foundation

/// Collects one Snapshot from the SMC, the kernel CPU counters and `ps`.
/// Not thread-safe: Monitor only calls it from its serial queue.
final class Sampler: @unchecked Sendable {
    private let sensors = Sensors()
    private var cpuLoad = CPULoadSampler()

    func sample(includeProcesses: Bool) -> Snapshot {
        let temps = sensors.temperatures()
        return Snapshot(
            date: Date(),
            cpuTemp: temps.cpu.average,
            cpuTempMax: temps.cpu.max(),
            gpuTemp: temps.gpu.average,
            fans: sensors.fans(),
            cpuLoad: cpuLoad.sample(),
            thermalState: ProcessInfo.processInfo.thermalState.rawValue,
            topProcesses: includeProcesses ? TopProcesses.sample() : []
        )
    }
}

/// Apple Silicon sensor keys: Tp* / Te* are performance / efficiency core
/// dies, Tg* are GPU dies. Discovered once at start because the exact set
/// differs between M1…M4 chips.
final class Sensors {
    private let smc: SMC?
    private let cpuKeys: [SMC.Key]
    private let gpuKeys: [SMC.Key]
    private let fanCount: Int
    private var lastCPU: [Double] = []
    private var lastGPU: [Double] = []

    init() {
        let smc = SMC()
        let names = smc?.keyNames() ?? []
        func floatKeys(_ prefixes: [String]) -> [SMC.Key] {
            names
                .filter { name in prefixes.contains { name.hasPrefix($0) } }
                .compactMap { smc?.keyInfo($0) }
                .filter { $0.type == "flt " }
        }
        self.smc = smc
        cpuKeys = floatKeys(["Tp", "Te"])
        gpuKeys = floatKeys(["Tg"])
        fanCount = Int(smc?.double("FNum") ?? 0)
    }

    func temperatures() -> (cpu: [Double], gpu: [Double]) {
        // A power-gated GPU reads 0 or below; keep its last real temperature.
        let cpu = values(cpuKeys), gpu = values(gpuKeys)
        if !cpu.isEmpty { lastCPU = cpu }
        if !gpu.isEmpty { lastGPU = gpu }
        return (lastCPU, lastGPU)
    }

    func fans() -> [FanReading] {
        (0 ..< fanCount).map { i in
            FanReading(
                rpm: smc?.double("F\(i)Ac") ?? 0,
                min: smc?.double("F\(i)Mn") ?? 0,
                max: smc?.double("F\(i)Mx") ?? 0,
                manual: smc?.double("F\(i)Md") == 1
            )
        }
    }

    // Some sensors report 0 or garbage when their block is powered down.
    private func values(_ keys: [SMC.Key]) -> [Double] {
        keys.compactMap { smc?.double($0) }.filter { (10 ... 130).contains($0) }
    }
}

/// Whole-machine CPU usage from the delta of kernel tick counters.
struct CPULoadSampler {
    private let host = mach_host_self()
    private var previous: host_cpu_load_info?

    mutating func sample() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        defer { previous = info }
        guard let old = previous else { return 0 }

        let new = info.cpu_ticks
        let prev = old.cpu_ticks
        let user = Double(new.0 &- prev.0)
        let system = Double(new.1 &- prev.1)
        let idle = Double(new.2 &- prev.2)
        let nice = Double(new.3 &- prev.3)
        let total = user + system + idle + nice
        return total > 0 ? (user + system + nice) / total : 0
    }
}

/// Top CPU consumers. Uses /bin/ps because it can see processes owned by
/// root and other users (WindowServer, mds_stores), which libproc cannot.
enum TopProcesses {
    private static let cores = Double(ProcessInfo.processInfo.activeProcessorCount)

    static func sample(limit: Int = 5) -> [ProcessReading] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aceo", "pid=,pcpu=,comm=", "-r"]
        process.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line -> ProcessReading? in
                let parts = line.split(separator: " ", maxSplits: 2)
                guard parts.count == 3, let pid = Int32(parts[0]), let cpu = Double(parts[1]) else { return nil }
                // ps reports % of one core; convert to a share of the whole CPU
                // so the list adds up to the total load shown above it.
                return ProcessReading(pid: pid, name: String(parts[2]), cpu: cpu / cores)
            }
            .prefix(limit)
            .map { $0 }
    }
}

private extension Array where Element == Double {
    var average: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }
}
