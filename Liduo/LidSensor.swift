import Foundation
import IOKit.hid
import QuartzCore

struct LidSample: Sendable {
    let degrees: Double
    let timestamp: Double
}

@MainActor protocol LidAngleSource: AnyObject {
    var onSample: ((LidSample) -> Void)? { get set }
    var onStatus: ((Bool, String) -> Void)? { get set }
    func start()
    func stop()
}

@MainActor final class LidSensor: LidAngleSource {
    var onSample: ((LidSample) -> Void)?
    var onStatus: ((Bool, String) -> Void)?
    private var reader: LidReportReader?
    private var generation = 0

    func start() {
        guard reader == nil else { return }
        generation += 1
        let token = generation
        let reader = LidReportReader(sample: { [weak self] sample in
            guard let self, self.generation == token else { return }
            self.onSample?(sample)
        }, status: { [weak self] available, detail in
            guard let self, self.generation == token else { return }
            self.onStatus?(available, detail)
        })
        self.reader = reader
        reader.start()
    }

    func stop() {
        generation += 1
        reader?.stop()
        reader = nil
    }
}

private final class LidReportReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.laplapaw.Liduo.sensor", qos: .userInteractive)
    private let sample: @MainActor @Sendable (LidSample) -> Void
    private let status: @MainActor @Sendable (Bool, String) -> Void
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private var lastAngle: Double?
    private var lastMovement = 0.0
    private var interval = 1.0 / 30
    private var failures = 0

    init(sample: @escaping @MainActor @Sendable (LidSample) -> Void,
         status: @escaping @MainActor @Sendable (Bool, String) -> Void) {
        self.sample = sample; self.status = status
    }

    func start() {
        queue.async { [self] in
            let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
            self.manager = manager
            IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x05AC,
                kIOHIDDeviceUsagePageKey: 0x20, kIOHIDDeviceUsageKey: 0x8A] as CFDictionary)
            guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
                  let candidate = devices.first else {
                fail("На этом Mac не найден датчик угла крышки")
                return
            }
            let result = IOHIDDeviceOpen(candidate, 0)
            guard result == kIOReturnSuccess else {
                fail("Не удалось подключить датчик крышки. Нажмите «Проверить снова». Если ошибка повторится, перезапустите Liduo.")
                return
            }
            device = candidate
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in self?.readReport() }
            self.timer = timer
            timer.resume()
            Task { @MainActor [status] in status(true, "HID · фоновое чтение 30–120 Гц") }
        }
    }

    func stop() { queue.async { [self] in close() } }

    private func close() {
        timer?.cancel(); timer = nil
        if let device { IOHIDDeviceClose(device, 0) }
        device = nil; manager = nil
    }

    private func fail(_ message: String) {
        close()
        Task { @MainActor [status] in status(false, message) }
    }

    private func readReport() {
        guard let device else { return }
        var report = [UInt8](repeating: 0, count: 8)
        var length = CFIndex(report.count)
        let result = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        guard result == kIOReturnSuccess, length >= 3 else {
            failures += 1
            if failures >= 10 { fail("Не удалось прочитать угол крышки. Нажмите «Проверить снова».") }
            return
        }
        failures = 0
        let angle = Double(UInt16(report[1]) | UInt16(report[2]) << 8)
        guard (0...180).contains(angle) else { return }
        let now = CACurrentMediaTime()
        if angle != lastAngle {
            lastMovement = now; lastAngle = angle
            let value = LidSample(degrees: angle, timestamp: now)
            Task { @MainActor [sample] in sample(value) }
        }
        let nextInterval = now - lastMovement < 0.5 ? 1.0 / 120 : 1.0 / 30
        if nextInterval != interval {
            interval = nextInterval
            timer?.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(1))
        }
    }
}
