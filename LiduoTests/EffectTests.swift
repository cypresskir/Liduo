import XCTest
@testable import Liduo

final class EffectTests: XCTestCase {
    @MainActor func testCaptureSkipsUnassignedAndOutOfRangeWindowNumbers() {
        XCTAssertEqual(DesktopCapture.windowIDs(for: [-1, 0, 42, Int.max, 42, 73]), [42, 73])
    }

    func testSlowQuantizedLidMotionStaysContinuousAt60And120FPS() {
        for fps in [60.0, 120.0] {
            for speed in [0.5, 1.0, 2.0, 4.0, 6.0, 10.0] {
                for reportRate in [speed, 10.0] {
                    var lid = LidMotion(), fold = FoldMotion()
                    var sampleIndex = 0, previous = 0.0
                    var steps: [Double] = []
                    for tick in 0...Int(fps * 8) {
                        let time = Double(tick) / fps
                        while Double(sampleIndex) / reportRate <= time + 1e-9 {
                            let sampleTime = Double(sampleIndex) / reportRate
                            lid.update(LidSample(degrees: (100 - sampleTime * speed).rounded(), timestamp: sampleTime))
                            sampleIndex += 1
                        }
                        let value = fold.update(target: FoldMath.progress(angle: lid.angle(at: time)!, clearAngle: 110), at: time)
                        let renderedAngle = 110 - value * 95
                        if time >= 3 { steps.append(previous - renderedAngle) }
                        previous = renderedAngle
                    }
                    let context = "\(speed) degrees/s at \(fps) fps, reporting at \(reportRate) Hz"
                    XCTAssertLessThanOrEqual(steps.max()!, speed / fps * 3, "A one-degree report creates a jump: \(context)")
                    XCTAssertGreaterThanOrEqual(steps.min()!, -0.001, "Closing must not recoil: \(context)")
                    XCTAssertLessThan(Double(steps.filter { abs($0) < 0.001 }.count) / Double(steps.count), 0.05,
                        "Slow motion must not freeze between reports: \(context)")
                }
            }
        }
    }

    func testSlowLidInterpolationStopsAtTheMeasuredAngle() {
        for interval in [0.25, 0.5, 1.0, 2.0] {
            var lid = LidMotion()
            for index in 0...6 {
                lid.update(LidSample(degrees: 100 - Double(index), timestamp: Double(index) * interval))
            }
            var previous = lid.angle(at: 6 * interval)!
            for tick in 1...Int(120 * (interval + 1)) {
                let angle = lid.angle(at: 6 * interval + Double(tick) / 120)!
                XCTAssertGreaterThanOrEqual(angle, 94, "Predicting past the last report creates a recoil when the lid stops")
                XCTAssertLessThanOrEqual(angle, previous + 0.00001)
                previous = angle
            }
            XCTAssertEqual(previous, 94, accuracy: 0.00001)
        }
    }

    func testStyleSelectionPreservesBehaviorAndDetectsCustomAppearance() {
        var current = Preferences()
        current.enabled = false
        current.sound = true
        current.clearAngle = 80
        for style in FoldStyle.allCases {
            var selected = current.applying(style)
            XCTAssertEqual(selected.style, style)
            XCTAssertFalse(selected.enabled)
            XCTAssertTrue(selected.sound)
            XCTAssertEqual(selected.clearAngle, 80)
            XCTAssertFalse(selected.hasCustomStyle)
            selected.blur += 0.05
            XCTAssertTrue(selected.hasCustomStyle)
            XCTAssertFalse(selected.applying(style).hasCustomStyle)
        }
    }

    func testLidPredictionBridgesTenHertzReadingsAndSettlesWhenStopped() {
        var motion = LidMotion()
        motion.update(LidSample(degrees: 120, timestamp: 0))
        motion.update(LidSample(degrees: 117, timestamp: 0.1))
        motion.update(LidSample(degrees: 114, timestamp: 0.2))
        XCTAssertEqual(motion.angle(at: 0.25)!, 112.5, accuracy: 0.01)
        XCTAssertEqual(motion.angle(at: 0.29)!, 111.3, accuracy: 0.01)
        XCTAssertEqual(motion.angle(at: 0.7)!, 114, accuracy: 0.01)
        motion.update(LidSample(degrees: 117, timestamp: 0.3))
        XCTAssertGreaterThan(motion.angle(at: 0.35)!, 117, "Reversal must change direction immediately")
        motion.update(LidSample(degrees: 100, timestamp: 2))
        XCTAssertEqual(motion.angle(at: 2.05)!, 100, "Do not reuse velocity after a pause")
    }

    func testLidPredictionCannotRunAwayFromSensor() {
        var motion = LidMotion()
        motion.update(LidSample(degrees: 90, timestamp: 0))
        motion.update(LidSample(degrees: 20, timestamp: 0.1))
        for tick in 10...100 {
            XCTAssertTrue((16...20).contains(motion.angle(at: Double(tick) / 100)!))
        }
    }

    func testLidPredictionDoesNotReverseDuringNormalSensorJitter() {
        var motion = LidMotion()
        motion.update(LidSample(degrees: 120, timestamp: 0))
        motion.update(LidSample(degrees: 117, timestamp: 0.1))
        var previous = 117.0
        for tick in 1...14 {
            let angle = motion.angle(at: 0.1 + Double(tick) / 100)!
            XCTAssertLessThanOrEqual(angle, previous, "A late sensor report must not reverse a closing lid")
            previous = angle
        }
    }

    func testRecordedLidSweepDoesNotRecoilBetweenMeasurements() {
        let samples: [(Double, Double)] = [
            (0, 109), (57.012, 107), (57.109, 105), (57.221, 103), (57.317, 102),
            (57.412, 99), (57.525, 95), (57.620, 92), (57.716, 88), (57.812, 84),
            (57.925, 80), (58.020, 76), (58.116, 73), (58.229, 70), (58.324, 68),
            (58.420, 66), (58.533, 63), (58.629, 60), (58.724, 58), (58.820, 56),
            (58.933, 54), (59.029, 53), (59.124, 52), (59.235, 50), (59.333, 48),
            (59.429, 47), (59.538, 46), (59.828, 45), (59.939, 44), (60.643, 43),
            (60.738, 44), (61.043, 45), (61.137, 48), (61.252, 53), (61.349, 58),
            (61.443, 64), (61.554, 69), (61.652, 75), (61.746, 81), (61.843, 86),
            (61.956, 91), (62.052, 96), (62.146, 99), (62.260, 102), (62.354, 105),
            (62.452, 107), (62.563, 108), (62.660, 109)
        ]
        for fps in [60.0, 120.0] {
            var lid = LidMotion(), fold = FoldMotion()
            var index = 0, previous = 0.0
            for tick in Int(56.9 * fps)...Int(62.8 * fps) {
                let time = Double(tick) / fps
                while index < samples.count, samples[index].0 <= time {
                    lid.update(LidSample(degrees: samples[index].1, timestamp: samples[index].0))
                    index += 1
                }
                let angle = lid.angle(at: time)!
                XCTAssertLessThanOrEqual(abs(angle - samples[index - 1].1), 4.00001)
                let value = fold.update(target: FoldMath.progress(angle: angle, clearAngle: 110), at: time)
                if time > 57.42, time < 59.55 {
                    XCTAssertGreaterThanOrEqual(value + 0.00001, previous, "Closing recoiled at \(time)")
                }
                if time > 61.14, time < 62.55 {
                    XCTAssertLessThanOrEqual(value - 0.00001, previous, "Opening recoiled at \(time)")
                }
                previous = value
            }
        }
    }

    func testMotionFollowsLidWithinFiftyMillisecondsWithoutOvershooting() {
        for fps in [60.0, 120.0] {
            var motion = FoldMotion()
            _ = motion.update(target: 0, at: 0)
            for frame in 1...Int(fps / 20) {
                let value = motion.update(target: 0.8, at: Double(frame) / fps)
                XCTAssertTrue((0...0.8).contains(value))
            }
            XCTAssertGreaterThanOrEqual(motion.value, 0.76)
            for frame in 1...Int(fps / 20) {
                let value = motion.update(target: 0, at: 0.05 + Double(frame) / fps)
                XCTAssertGreaterThanOrEqual(value, 0)
            }
            XCTAssertLessThanOrEqual(motion.value, 0.04)
        }
    }

    func testAngleMappingAndLimits() {
        XCTAssertEqual(FoldMath.progress(angle: 123, clearAngle: 110), 0)
        XCTAssertEqual(FoldMath.progress(angle: 110, clearAngle: 110), 0)
        XCTAssertEqual(FoldMath.progress(angle: 62.5, clearAngle: 110), 0.5, accuracy: 0.001)
        XCTAssertEqual(FoldMath.progress(angle: 15, clearAngle: 110), 1)
        XCTAssertEqual(FoldMath.progress(angle: 0, clearAngle: 110), 1)
        XCTAssertEqual(FoldMath.progress(angle: .nan, clearAngle: 110), 0)
    }

    func testCaptureSafetyGatesOverrideDemo() {
        XCTAssertTrue(FoldMath.shouldCapture(angle: 80, clearAngle: 110, enabled: true, permitted: true, suspended: false, demo: false))
        XCTAssertFalse(FoldMath.shouldCapture(angle: 123, clearAngle: 110, enabled: true, permitted: true, suspended: false, demo: false))
        XCTAssertFalse(FoldMath.shouldCapture(angle: 0, clearAngle: 110, enabled: true, permitted: true, suspended: false, demo: false))
        XCTAssertFalse(FoldMath.shouldCapture(angle: 80, clearAngle: 110, enabled: false, permitted: true, suspended: false, demo: true))
        XCTAssertFalse(FoldMath.shouldCapture(angle: 80, clearAngle: 110, enabled: true, permitted: false, suspended: false, demo: true))
        XCTAssertFalse(FoldMath.shouldCapture(angle: 80, clearAngle: 110, enabled: true, permitted: true, suspended: true, demo: true))
        XCTAssertTrue(FoldMath.shouldCapture(angle: nil, clearAngle: 110, enabled: true, permitted: true, suspended: false, demo: true))
    }

    func testOpenSoundOnlyOncePerSignificantFold() {
        var cycle = OpenCycle()
        XCTAssertFalse(cycle.update(progress: 0))
        XCTAssertFalse(cycle.update(progress: 0.02))
        XCTAssertFalse(cycle.update(progress: 0))
        XCTAssertFalse(cycle.update(progress: 0.4))
        XCTAssertFalse(cycle.update(progress: 0.1))
        XCTAssertTrue(cycle.update(progress: 0))
        XCTAssertFalse(cycle.update(progress: 0))
        XCTAssertFalse(cycle.update(progress: 0.5))
        cycle.reset()
        XCTAssertFalse(cycle.update(progress: 0))
    }

    func testStoredPreferencesAreClamped() {
        var prefs = Preferences()
        prefs.clearAngle = 0; prefs.perspective = 4; prefs.blur = -3; prefs.shadow = .nan
        let restored = prefs.validated()
        XCTAssertEqual(restored.clearAngle, 60)
        XCTAssertEqual(restored.perspective, 1)
        XCTAssertEqual(restored.blur, 0)
        XCTAssertEqual(restored.shadow, 0.35)
    }
}
