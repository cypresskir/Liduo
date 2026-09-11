import AppKit
import XCTest
@testable import Liduo

final class CursorTests: XCTestCase {
    @MainActor func testRepeatedAnimationUpdatesBalanceOneHideAndOneShow() {
        var hides = 0
        var shows = 0
        let cursor = CursorVisibility(hide: { hides += 1; return true }, show: { shows += 1; return true })
        let frame = NSRect(x: 0, y: 0, width: 1800, height: 1169)
        for _ in 0..<600 { cursor.update(effectFrame: frame, mouseLocation: NSPoint(x: 400, y: 300)) }
        XCTAssertEqual(hides, 1)
        XCTAssertTrue(cursor.hiddenByLiduo)
        for _ in 0..<10 { cursor.restore() }
        XCTAssertEqual(shows, 1)
        XCTAssertFalse(cursor.hiddenByLiduo)
    }

    @MainActor func testCursorStaysVisibleOnExternalDisplayAndReturnsWhenLeavingEffect() {
        var actions: [String] = []
        let cursor = CursorVisibility(hide: { actions.append("hide"); return true }, show: { actions.append("show"); return true })
        let frame = NSRect(x: 0, y: -1169, width: 1800, height: 1169)
        cursor.update(effectFrame: frame, mouseLocation: NSPoint(x: 100, y: 100))
        XCTAssertTrue(actions.isEmpty)
        cursor.update(effectFrame: frame, mouseLocation: NSPoint(x: 100, y: -100))
        cursor.update(effectFrame: frame, mouseLocation: NSPoint(x: 1900, y: -100))
        cursor.update(effectFrame: frame, mouseLocation: NSPoint(x: 100, y: -100))
        cursor.update(effectFrame: nil, mouseLocation: NSPoint(x: 100, y: -100))
        XCTAssertEqual(actions, ["hide", "show", "hide", "show"])
        XCTAssertFalse(cursor.hiddenByLiduo)
    }

    @MainActor func testFailedHideDoesNotUnhideAnotherApplicationsCursor() {
        var mayHide = false
        var shows = 0
        let cursor = CursorVisibility(hide: { mayHide }, show: { shows += 1; return true })
        let frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        cursor.update(effectFrame: frame, mouseLocation: NSPoint(x: 50, y: 50))
        cursor.restore()
        XCTAssertFalse(cursor.hiddenByLiduo)
        XCTAssertEqual(shows, 0)
        mayHide = true
        cursor.update(effectFrame: frame, mouseLocation: NSPoint(x: 50, y: 50))
        cursor.restore()
        XCTAssertEqual(shows, 1)
    }

    @MainActor func testFailedRestoreRetainsOwnershipForRetry() {
        var mayShow = false
        var hides = 0
        let cursor = CursorVisibility(hide: { hides += 1; return true }, show: { mayShow })
        let frame = NSRect(x: 0, y: 0, width: 100, height: 100)
        cursor.update(effectFrame: frame, mouseLocation: NSPoint(x: 50, y: 50))
        cursor.restore()
        XCTAssertTrue(cursor.hiddenByLiduo)
        cursor.update(effectFrame: frame, mouseLocation: NSPoint(x: 50, y: 50))
        XCTAssertEqual(hides, 1)
        mayShow = true
        cursor.restore()
        XCTAssertFalse(cursor.hiddenByLiduo)
    }

    @MainActor func testRepeatedEffectCyclesLeaveCursorBalanced() {
        var balance = 0
        let cursor = CursorVisibility(hide: { balance += 1; return true }, show: { balance -= 1; return true })
        for _ in 0..<100 {
            cursor.update(effectFrame: NSRect(x: 0, y: 0, width: 100, height: 100), mouseLocation: NSPoint(x: 1, y: 1))
            XCTAssertEqual(balance, 1)
            cursor.restore()
            XCTAssertEqual(balance, 0)
        }
    }
}
