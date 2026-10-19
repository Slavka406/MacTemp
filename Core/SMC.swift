import IOKit

/// Minimal reader for the System Management Controller (temperatures, fans).
/// Talks to the AppleSMC kernel service with the same 80-byte SMCKeyData_t
/// struct the C tools use; the offsets below match its C layout.
final class SMC {
    struct Key {
        let code: UInt32
        let size: UInt32
        let type: String
    }

    private enum Offset {
        static let key = 0, dataSize = 28, dataType = 32, result = 40, command = 42, index = 44, bytes = 48
    }

    private enum Command: UInt8 {
        case readBytes = 5, writeBytes = 6, keyAtIndex = 8, keyInfo = 9
    }

    private static let structSize = 80
    private static let selector: UInt32 = 2 // kSMCHandleYPCEvent

    private var connection: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit {
        IOServiceClose(connection)
    }

    func keyNames() -> [String] {
        guard let count = keyInfo("#KEY").flatMap(read).map(Self.bigEndian) else { return [] }
        return (0 ..< count).compactMap { index in
            var input = Self.emptyStruct()
            input[Offset.command] = Command.keyAtIndex.rawValue
            Self.put(index, at: Offset.index, in: &input)
            return call(input).map { Self.fourCC(Self.get(at: Offset.key, in: $0)) }
        }
    }

    func keyInfo(_ name: String) -> Key? {
        let code = Self.code(name)
        var input = Self.emptyStruct()
        Self.put(code, at: Offset.key, in: &input)
        input[Offset.command] = Command.keyInfo.rawValue
        guard let output = call(input) else { return nil }
        return Key(
            code: code,
            size: Self.get(at: Offset.dataSize, in: output),
            type: Self.fourCC(Self.get(at: Offset.dataType, in: output))
        )
    }

    func read(_ key: Key) -> [UInt8]? {
        var input = Self.emptyStruct()
        Self.put(key.code, at: Offset.key, in: &input)
        Self.put(key.size, at: Offset.dataSize, in: &input)
        input[Offset.command] = Command.readBytes.rawValue
        guard let output = call(input) else { return nil }
        return Array(output[Offset.bytes ..< Offset.bytes + Int(min(key.size, 32))])
    }

    func double(_ key: Key) -> Double? {
        guard let bytes = read(key), !bytes.isEmpty else { return nil }
        switch key.type {
        case "flt " where bytes.count >= 4:
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float32.self) })
        case "ui8 ":
            return Double(bytes[0])
        case "ui16" where bytes.count >= 2:
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "sp78" where bytes.count >= 2:
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default:
            return nil
        }
    }

    func double(_ name: String) -> Double? {
        keyInfo(name).flatMap(double)
    }

    /// Writing requires root (kIOReturnNotPrivileged otherwise).
    @discardableResult
    func write(_ name: String, _ bytes: [UInt8]) -> Bool {
        guard let key = keyInfo(name), bytes.count == Int(key.size), bytes.count <= 32 else { return false }
        var input = Self.emptyStruct()
        Self.put(key.code, at: Offset.key, in: &input)
        Self.put(key.size, at: Offset.dataSize, in: &input)
        input[Offset.command] = Command.writeBytes.rawValue
        input.replaceSubrange(Offset.bytes ..< Offset.bytes + bytes.count, with: bytes)
        return call(input) != nil
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var output = Self.emptyStruct()
        var outputSize = Self.structSize
        let result = input.withUnsafeBytes { inBuffer in
            output.withUnsafeMutableBytes { outBuffer in
                IOConnectCallStructMethod(
                    connection, Self.selector,
                    inBuffer.baseAddress, Self.structSize,
                    outBuffer.baseAddress, &outputSize
                )
            }
        }
        guard result == kIOReturnSuccess, output[Offset.result] == 0 else { return nil }
        return output
    }

    private static func emptyStruct() -> [UInt8] {
        [UInt8](repeating: 0, count: structSize)
    }

    private static func put(_ value: UInt32, at offset: Int, in buffer: inout [UInt8]) {
        withUnsafeBytes(of: value) { buffer.replaceSubrange(offset ..< offset + 4, with: $0) }
    }

    private static func get(at offset: Int, in buffer: [UInt8]) -> UInt32 {
        buffer[offset ..< offset + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }

    private static func code(_ name: String) -> UInt32 {
        name.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func fourCC(_ code: UInt32) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, as: UTF8.self)
    }

    private static func bigEndian(_ bytes: [UInt8]) -> UInt32 {
        bytes.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }
}
