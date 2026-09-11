import XCTest
import IOKit.hid
@testable import Liduo

final class LidSensorTests: XCTestCase {
    func testTriesAnotherDeviceWhenFirstCannotOpen() {
        let blocked = TestLidDevice(openResult: kIOReturnExclusiveAccess)
        let working = TestLidDevice()
        let connection = LidConnection.find(in: [blocked, working])
        XCTAssertTrue(connection.device === working)
        XCTAssertEqual(connection.angle, 120)
        XCTAssertEqual(blocked.readCount, 0)
        XCTAssertEqual(blocked.closeCount, 0)
    }

    func testRejectsUnreadableAndMalformedDevicesBeforeSelectingOne() {
        let reports = [
            LidReport(result: kIOReturnError, bytes: [1, 120, 0]),
            LidReport(result: kIOReturnSuccess, bytes: [1, 120]),
            LidReport(result: kIOReturnSuccess, bytes: [2, 120, 0]),
            LidReport(result: kIOReturnSuccess, bytes: [1, 255, 255])
        ]
        for report in reports {
            let invalid = TestLidDevice(report: report)
            let working = TestLidDevice()
            let connection = LidConnection.find(in: [invalid, working])
            XCTAssertTrue(connection.device === working)
            XCTAssertEqual(connection.angle, 120)
            XCTAssertEqual(invalid.closeCount, 1)
            XCTAssertEqual(working.closeCount, 0)
        }
    }

    func testNoReadableSensorDoesNotProduceAnAngleOrLeaveDeviceOpen() {
        let invalid = TestLidDevice(report: LidReport(result: kIOReturnSuccess, bytes: [1]))
        let connection = LidConnection.find(in: [invalid])
        XCTAssertNil(connection.device)
        XCTAssertNil(connection.angle)
        XCTAssertTrue(connection.openedAnyDevice)
        XCTAssertEqual(invalid.closeCount, 1)
        XCTAssertNil(LidConnection.find(in: []).device)
    }

    func testAcceptsClosedAndFullyOpenLidWithoutInventingAUnitConversion() {
        for angle in [0, 90, 120, 180] {
            let report = LidReport(result: kIOReturnSuccess, bytes: [1, UInt8(angle), 0])
            XCTAssertEqual(report.angle, Double(angle))
        }
        XCTAssertNil(LidReport(result: kIOReturnSuccess, bytes: [1, 0xE0, 0x2E]).angle)
    }

    func testProductIDAloneCannotTurnOtherSPUSensorsIntoLidAngles() {
        let vendorInterface = LidDeviceIdentity(vendorID: 0x05AC, productID: 0x8104, builtIn: true, hasLidUsage: false)
        XCTAssertFalse(vendorInterface.isAngleCandidate)
        XCTAssertTrue(vendorInterface.isOtherSPUInterface)
        let external = LidDeviceIdentity(vendorID: 0x05AC, productID: 0x8104, builtIn: false, hasLidUsage: true)
        XCTAssertFalse(external.isAngleCandidate)
        let future = LidDeviceIdentity(vendorID: 0x05AC, productID: 0x9999, builtIn: true, hasLidUsage: true)
        XCTAssertTrue(future.isAngleCandidate)
        let unknownBuiltIn = LidDeviceIdentity(vendorID: 0x05AC, productID: nil, builtIn: nil, hasLidUsage: true)
        XCTAssertTrue(unknownBuiltIn.isAngleCandidate)
    }

    func testMissingSensorExplainsKnownHardwareLimitWithoutBlockingUnknownModels() {
        for model in ["MacBookAir10,1", "MacBookPro17,1", "Mac14,7"] {
            XCTAssertTrue(LidHardware.missingSensorDetail(model: model, hasOtherSPUInterfaces: false).contains("не имеет датчика"))
        }
        XCTAssertFalse(LidHardware.missingSensorDetail(model: "Mac99,1", hasOtherSPUInterfaces: false).contains("не имеет датчика"))
        XCTAssertTrue(LidHardware.missingSensorDetail(model: "Mac14,2", hasOtherSPUInterfaces: true).contains("интерфейс угла крышки недоступен"))
    }
}

private final class TestLidDevice: LidReportDevice {
    let openResult: IOReturn
    let report: LidReport
    var readCount = 0
    var closeCount = 0

    init(openResult: IOReturn = kIOReturnSuccess,
         report: LidReport = LidReport(result: kIOReturnSuccess, bytes: [1, 120, 0])) {
        self.openResult = openResult
        self.report = report
    }

    func open() -> IOReturn { openResult }
    func read() -> LidReport { readCount += 1; return report }
    func close() { closeCount += 1 }
}
