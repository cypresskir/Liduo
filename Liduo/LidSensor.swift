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
    let modelIdentifier = LidHardware.modelIdentifier
    var onSample: ((LidSample) -> Void)?
    var onStatus: ((Bool, String) -> Void)?
    private var reader: LidReportReader?
    private var generation = 0

    func start() {
        guard reader == nil else { return }
        generation += 1
        let token = generation
        let reader = LidReportReader(modelIdentifier: modelIdentifier, sample: { [weak self] sample in
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
    private let modelIdentifier: String
    private var device: (any LidReportDevice)?
    private var timer: DispatchSourceTimer?
    private var lastAngle: Double?
    private var lastMovement = 0.0
    private var interval = 1.0 / 30
    private var failures = 0

    init(modelIdentifier: String, sample: @escaping @MainActor @Sendable (LidSample) -> Void,
         status: @escaping @MainActor @Sendable (Bool, String) -> Void) {
        self.modelIdentifier = modelIdentifier
        self.sample = sample; self.status = status
    }

    func start() {
        queue.async { [self] in
            let discovery = LidDeviceDiscovery.scan()
            let candidates = discovery.candidates
            guard !candidates.isEmpty else {
                fail(LidHardware.missingSensorDetail(model: modelIdentifier,
                    hasOtherSPUInterfaces: discovery.hasOtherSPUInterfaces))
                return
            }
            let connection = LidConnection.find(in: candidates)
            guard let candidate = connection.device, let angle = connection.angle else {
                fail(connection.openedAnyDevice
                    ? "Датчик найден, но не передает корректный угол крышки. Нажмите «Проверить снова»."
                    : "Не удалось подключить датчик крышки. Закройте другие приложения для чтения угла и нажмите «Проверить снова».")
                return
            }
            device = candidate
            let firstSample = LidSample(degrees: angle, timestamp: CACurrentMediaTime())
            lastAngle = angle
            Task { @MainActor [status, sample] in
                status(true, "HID · фоновое чтение 30–120 Гц")
                sample(firstSample)
            }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in self?.readReport() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() { queue.async { [self] in close() } }

    private func close() {
        timer?.cancel(); timer = nil
        device?.close()
        device = nil
    }

    private func fail(_ message: String) {
        close()
        Task { @MainActor [status] in status(false, message) }
    }

    private func readReport() {
        guard let device else { return }
        guard let angle = device.read().angle else {
            failures += 1
            if failures >= 10 { fail("Не удалось прочитать угол крышки. Нажмите «Проверить снова».") }
            return
        }
        failures = 0
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
