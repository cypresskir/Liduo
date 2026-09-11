import Foundation
import IOKit.hid

struct LidReport {
    let result: IOReturn
    let bytes: [UInt8]

    var angle: Double? {
        guard result == kIOReturnSuccess, bytes.count >= 3, bytes[0] == 1 else { return nil }
        let value = Double(UInt16(bytes[1]) | UInt16(bytes[2]) << 8)
        return (0...180).contains(value) ? value : nil
    }
}

protocol LidReportDevice: AnyObject {
    func open() -> IOReturn
    func read() -> LidReport
    func close()
}

struct LidConnection {
    let device: (any LidReportDevice)?
    let angle: Double?
    let openedAnyDevice: Bool

    static func find(in candidates: [any LidReportDevice]) -> LidConnection {
        var openedAnyDevice = false
        for candidate in candidates {
            guard candidate.open() == kIOReturnSuccess else { continue }
            openedAnyDevice = true
            if let angle = candidate.read().angle {
                return LidConnection(device: candidate, angle: angle, openedAnyDevice: true)
            }
            candidate.close()
        }
        return LidConnection(device: nil, angle: nil, openedAnyDevice: openedAnyDevice)
    }
}

struct LidDeviceIdentity {
    let vendorID: Int?
    let productID: Int?
    let builtIn: Bool?
    let hasLidUsage: Bool

    var isAngleCandidate: Bool { vendorID == 0x05AC && builtIn != false && hasLidUsage }
    var isOtherSPUInterface: Bool { vendorID == 0x05AC && productID == 0x8104 && !hasLidUsage }
}

final class LidHIDDevice: LidReportDevice {
    let device: IOHIDDevice

    init(_ device: IOHIDDevice) { self.device = device }

    var identity: LidDeviceIdentity {
        func number(_ key: String) -> NSNumber? { IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber }
        return LidDeviceIdentity(vendorID: number(kIOHIDVendorIDKey)?.intValue,
            productID: number(kIOHIDProductIDKey)?.intValue,
            builtIn: number(kIOHIDBuiltInKey)?.boolValue,
            hasLidUsage: IOHIDDeviceConformsTo(device, 0x20, 0x8A)
                || (number(kIOHIDPrimaryUsagePageKey)?.intValue == 0x20
                    && number(kIOHIDPrimaryUsageKey)?.intValue == 0x8A))
    }

    func open() -> IOReturn { IOHIDDeviceOpen(device, 0) }
    func close() { IOHIDDeviceClose(device, 0) }

    func read() -> LidReport {
        var bytes = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(bytes.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &length)
        return LidReport(result: result, bytes: Array(bytes.prefix(max(0, length))))
    }
}

struct LidDeviceDiscovery {
    let devices: [LidHIDDevice]
    var candidates: [any LidReportDevice] { devices.filter { $0.identity.isAngleCandidate } }
    var hasOtherSPUInterfaces: Bool { devices.contains { $0.identity.isOtherSPUInterface } }

    static func scan() -> LidDeviceDiscovery {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatchingMultiple(manager, [
            [kIOHIDVendorIDKey: 0x05AC, kIOHIDDeviceUsagePageKey: 0x20, kIOHIDDeviceUsageKey: 0x8A],
            [kIOHIDVendorIDKey: 0x05AC, kIOHIDProductIDKey: 0x8104]
        ] as CFArray)
        var devices = Array(IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? [])
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDevice"), &iterator) == kIOReturnSuccess {
            defer { IOObjectRelease(iterator) }
            while case let service = IOIteratorNext(iterator), service != 0 {
                if let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) { devices.append(device) }
                IOObjectRelease(service)
            }
        }
        var unique: [UInt64: LidHIDDevice] = [:]
        for device in devices {
            var registryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &registryID) == kIOReturnSuccess else { continue }
            if unique[registryID] == nil { unique[registryID] = LidHIDDevice(device) }
        }
        return LidDeviceDiscovery(devices: unique.keys.sorted().compactMap { unique[$0] })
    }
}

enum LidHardware {
    static var modelIdentifier: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Неизвестная модель" }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 else { return "Неизвестная модель" }
        return String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
    }

    static func missingSensorDetail(model: String, hasOtherSPUInterfaces: Bool) -> String {
        let name: String?
        switch model {
        case "MacBookAir10,1": name = "MacBook Air M1"
        case "MacBookPro17,1": name = "MacBook Pro 13″ M1"
        case "Mac14,7": name = "MacBook Pro 13″ M2"
        default: name = nil
        }
        if let name {
            return "\(name) не имеет датчика угла крышки. Автоматический эффект на этой модели недоступен. Можно использовать ручной предпросмотр и кнопку «Показать эффект»."
        }
        if hasOtherSPUInterfaces {
            return "Обнаружены системные датчики Apple, но интерфейс угла крышки недоступен. Для проверки совместимости нужен отчет с этого Mac (\(model))."
        }
        return "Датчик угла крышки не найден (\(model)). Если в этой модели есть датчик, нажмите «Проверить снова» после пробуждения Mac."
    }
}
