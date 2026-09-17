import Testing
import Foundation
@testable import WindowBarCore

// Swift Testing (not XCTest): Command Line Tools without Xcode ship Testing.framework but no XCTest.
// Test names and assertions are kept identical to the original XCTest suite (34 cases).

@Suite struct GeometryTests {
    let screen = Rect(x: 0, y: 25, width: 1440, height: 850)
    @Test func testExternalHeaderDoesNotOverlapNativeWindow() throws {
        let window = Rect(x: 100, y: 100, width: 700, height: 500)
        let header = try #require(Geometry.externalHeader(for: window, in: screen))
        #expect(header.maxY == window.y)
        #expect(header.intersection(window) == nil)
        #expect(header.height == 30)
    }
    @Test func testNoSpaceMeansNoOverlayAndNoMutation() {
        let window = Rect(x: 0, y: 25, width: 700, height: 500)
        #expect(Geometry.externalHeader(for: window, in: screen) == nil)
        #expect(window.y == 25)
        // Partly above the usable area (under the menu bar): still no header, never a clamped one.
        #expect(Geometry.externalHeader(for: Rect(x: 0, y: 40, width: 700, height: 500), in: screen) == nil)
    }
    @Test func testHeaderFollowsWindowOverflowingScreenEdges() throws {
        // Off the left edge, off the right edge, and below the bottom: the header keeps the window's x
        // and width (cut off at the edge like the window), never a clamped or shrunk one.
        for window in [Rect(x: -300, y: 100, width: 700, height: 500),
                       Rect(x: 1200, y: 100, width: 700, height: 500),
                       Rect(x: 100, y: 800, width: 700, height: 500),
                       Rect(x: -300, y: 800, width: 700, height: 500)] {
            let header = try #require(Geometry.externalHeader(for: window, in: screen))
            #expect(header.x == window.x && header.width == window.width)
            #expect(header.maxY == window.y && header.height == 30)
        }
        // Entirely beside the screen: nothing to show here.
        #expect(Geometry.externalHeader(for: Rect(x: 1500, y: 100, width: 700, height: 500), in: screen) == nil)
    }
    @Test func testReserveOnlyChangesRequestedWindow() throws {
        let input = Rect(x: 0, y: 25, width: 700, height: 850)
        let output = try #require(Geometry.reserveSpace(for: input, in: screen))
        #expect(output.y == 55)
        #expect(output.height == 820)
        #expect(Geometry.externalHeader(for: output, in: screen) != nil)
        #expect(input.y == 25)
    }
    @Test func testReserveIsIdempotent() throws {
        let input = Rect(x: 10, y: 25, width: 700, height: 850)
        let first = try #require(Geometry.reserveSpace(for: input, in: screen))
        #expect(Geometry.reserveSpace(for: first, in: screen) == first)
    }
    @Test func testMaximizedFrameLeavesHeaderSpaceOnly() throws {
        let frame = try #require(Geometry.maximizedFrame(in: screen))
        #expect(frame.x == screen.x && frame.width == screen.width)
        #expect(frame.y == screen.y + Geometry.headerHeight && frame.maxY == screen.maxY)
        #expect(Geometry.externalHeader(for: frame, in: screen) != nil)
        #expect(Geometry.maximizedFrame(in: Rect(x: 0, y: 0, width: 500, height: 120)) == nil)
    }
    @Test func testReserveRejectsImpossibleScreen() {
        #expect(Geometry.reserveSpace(for: Rect(x: 0, y: 0, width: 600, height: 500),
                                      in: Rect(x: 0, y: 0, width: 500, height: 120)) == nil)
    }
    @Test func testNegativeCoordinateSecondaryDisplay() {
        let secondary = Rect(x: -1920, y: -300, width: 1920, height: 1000)
        let window = Rect(x: -1800, y: -200, width: 700, height: 500)
        #expect(Geometry.externalHeader(for: window, in: secondary)?.y == -230)
    }
    @Test func testCoordinateConversionRoundTrip() {
        for x in [-2560.0, 0, 1800] {
            for y in [-1600.0, -200, 0, 700, 2000] {
                let input = Rect(x: x, y: y, width: 731, height: 422)
                #expect(Geometry.flip(Geometry.flip(input, primaryHeight: 900), primaryHeight: 900) == input)
            }
        }
    }
    @Test func testPointerConversionRoundTrip() {
        let input = Point(x: -300, y: 1500)
        #expect(Geometry.flip(Geometry.flip(input, primaryHeight: 900), primaryHeight: 900) == input)
    }
    @Test func testBestScreenUsesLargestIntersection() {
        let left = Rect(x: -1000, y: 0, width: 1000, height: 800)
        let right = Rect(x: 0, y: 0, width: 1400, height: 900)
        #expect(Geometry.bestScreen(for: Rect(x: -100, y: 100, width: 700, height: 500),
                                    visibleFrames: [left, right]) == right)
    }
    @Test func testPanelFrameOnlyExtendsDownwardOverCornerBand() throws {
        let window = Rect(x: 100, y: 100, width: 700, height: 500)
        let header = try #require(Geometry.externalHeader(for: window, in: screen))
        let panel = Geometry.panelFrame(forHeader: header)
        #expect(panel.x == header.x && panel.y == header.y && panel.width == header.width)
        #expect(panel.height == header.height + Geometry.cornerFillExtent)
        // The band covers the corner curve's full run along the edge (about 1.53 x radius) and no more
        // than the corner region itself; the header keeps clear of the native window entirely.
        #expect(Geometry.cornerFillExtent >= Geometry.windowCornerRadius * 1.53)
        #expect(Geometry.cornerFillExtent <= Geometry.windowCornerRadius * 2)
        #expect(header.intersection(window) == nil)
        #expect(Geometry.panelFrame(forHeader: header, cornerExtent: 0) == header)
        #expect(Geometry.panelFrame(forHeader: header, cornerExtent: .nan) == header)
    }
    @Test func testInvalidRectRejected() {
        #expect(Geometry.externalHeader(for: Rect(x: .nan, y: 50, width: 200, height: 200), in: screen) == nil)
        #expect(Geometry.externalHeader(for: Rect(x: 0, y: 50, width: -20, height: 200), in: screen) == nil)
    }
}

@Suite struct LayoutTests {
    @Test func testWideHeaderShowsAllMenus() {
        let layout = HeaderLayout.make(width: 1200, appWidth: 130, menuWidths: [50, 50, 70, 80])
        #expect(layout.visibleMenuCount == 4)
        #expect(layout.overflow == nil)
        #expect(layout.title.width > 100)
    }
    @Test func testNarrowHeaderProvidesOverflow() {
        let layout = HeaderLayout.make(width: 320, appWidth: 140, menuWidths: [50, 50, 70, 80])
        #expect(layout.overflow != nil)
        #expect(layout.visibleMenuCount < 4)
    }
    @Test func testNoOverlappingOrOutOfBoundsControls() {
        for width in stride(from: 280.0, through: 1800.0, by: 13) {
            let layout = HeaderLayout.make(width: width, appWidth: 185, menuWidths: [55, 65, 75, 90, 58, 100])
            let rects = [layout.app] + layout.menus + (layout.overflow.map { [$0] } ?? []) + [layout.title] + layout.controls
            for rect in rects {
                #expect(rect.width >= 0)
                #expect(rect.maxX <= width + 0.01)
            }
            for pair in zip(rects, rects.dropFirst()) { #expect(pair.0.maxX <= pair.1.x + 0.01) }
        }
    }
    @Test func testMenusAreLeftAlignedAfterAppButton() throws {
        let layout = HeaderLayout.make(width: 1200, appWidth: 130, menuWidths: [50, 50, 70, 80])
        let first = try #require(layout.menus.first)
        #expect(first.x == layout.app.maxX + 4)
        for pair in zip(layout.menus, layout.menus.dropFirst()) { #expect(pair.1.x == pair.0.maxX) }
        #expect(layout.title.x >= layout.menus.last!.maxX)
        #expect(layout.title.maxX == 1200 - 5 - HeaderLayout.controlWidth * 3)
        let narrow = HeaderLayout.make(width: 320, appWidth: 140, menuWidths: [50, 50, 70, 80])
        let overflow = try #require(narrow.overflow)
        #expect(narrow.title.x >= overflow.maxX)
    }
    @Test func testWindowControlsSitFlushAtRightEdge() {
        for width in [280.0, 600, 1800] {
            let layout = HeaderLayout.make(width: width, appWidth: 130, menuWidths: [50, 50, 70, 80])
            #expect(layout.controls.count == 3)
            #expect(layout.controls.last?.maxX == width)
            for pair in zip(layout.controls, layout.controls.dropFirst()) { #expect(pair.1.x == pair.0.maxX) }
            #expect(layout.controls.allSatisfy { $0.width == HeaderLayout.controlWidth && $0.height == 30 })
            #expect(layout.title.maxX <= layout.controls[0].x)
            #expect((layout.overflow?.maxX ?? layout.menus.last?.maxX ?? layout.app.maxX) <= layout.controls[0].x)
        }
    }
    @Test func testNoMenusStillShowsTitle() {
        let layout = HeaderLayout.make(width: 600, appWidth: 130, menuWidths: [])
        #expect(layout.overflow == nil)
        #expect(layout.visibleMenuCount == 0)
        #expect(layout.title.width > 300) // 600 minus app, insets and the three 40pt window controls
    }
}

@Suite struct IdentityAndFocusTests {
    let instance = UUID()
    func token(_ id: UInt32 = 5, incarnation: UInt64 = 1) -> WindowToken {
        WindowToken(processInstance: instance, pid: 123, windowID: id, incarnation: incarnation)
    }
    @Test func testReusedWindowIDIsNotSameIdentity() { #expect(token() != token(incarnation: 2)) }
    @Test func testRestartedProcessIsNotSameIdentity() {
        #expect(token() != WindowToken(processInstance: UUID(), pid: 123, windowID: 5, incarnation: 1))
    }
    @Test func testSameTitleDifferentWindowsRejected() {
        let a = ContextStamp(token: token(5), title: "same.txt", document: nil)
        let b = ContextStamp(token: token(6), title: "same.txt", document: nil)
        #expect(!FocusPolicy.permits(expected: a, current: b, frontmostPID: 123, isModal: false, isMinimized: false))
    }
    @Test func testSameWindowDifferentTabDocumentRejected() {
        let a = ContextStamp(token: token(), title: "same.txt", document: "file:///A/same.txt")
        let b = ContextStamp(token: token(), title: "same.txt", document: "file:///B/same.txt")
        #expect(!FocusPolicy.permits(expected: a, current: b, frontmostPID: 123, isModal: false, isMinimized: false))
    }
    @Test func testInactiveAppRejected() {
        let a = ContextStamp(token: token(), title: "x", document: nil)
        #expect(!FocusPolicy.permits(expected: a, current: a, frontmostPID: 999, isModal: false, isMinimized: false))
        #expect(!FocusPolicy.permits(expected: a, current: a, frontmostPID: nil, isModal: false, isMinimized: false))
    }
    @Test func testModalAndMinimizedRejected() {
        let a = ContextStamp(token: token(), title: "x", document: nil)
        #expect(!FocusPolicy.permits(expected: a, current: a, frontmostPID: 123, isModal: true, isMinimized: false))
        #expect(!FocusPolicy.permits(expected: a, current: a, frontmostPID: 123, isModal: false, isMinimized: true))
    }
    @Test func testExactContextAllowed() {
        let a = ContextStamp(token: token(), title: "x", document: nil)
        #expect(FocusPolicy.permits(expected: a, current: a, frontmostPID: 123, isModal: false, isMinimized: false))
    }
}

@Suite struct PermitTests {
    @Test func testAtMostOnceAfterSuccessOrUnknownOutcome() {
        let permit = OperationPermit(lifetime: 10, now: 100)
        #expect(permit.commitOnce(now: 101))
        #expect(!permit.commitOnce(now: 102))
        #expect(!permit.isValid(now: 102))
    }
    @Test func testCancelledOperationCannotCommit() {
        let permit = OperationPermit(lifetime: 10, now: 100)
        permit.cancel()
        #expect(!permit.commitOnce(now: 101))
    }
    @Test func testExpiredOperationCannotCommit() {
        let permit = OperationPermit(lifetime: 1, now: 100)
        #expect(!permit.commitOnce(now: 102))
    }
    @Test func testConcurrentDoubleClickHasOnlyOneCommit() {
        let permit = OperationPermit(lifetime: 10)
        let lock = NSLock()
        nonisolated(unsafe) var accepted = 0
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            if permit.commitOnce() { lock.lock(); accepted += 1; lock.unlock() }
        }
        #expect(accepted == 1)
    }
}

@Suite struct PresenceTests {
    let token = WindowToken(processInstance: UUID(), pid: 123, windowID: 1, incarnation: 1)
    @Test func testTransientFailureDoesNotMeanClosed() {
        var tracker = PresenceTracker()
        for _ in 0..<10 {
            let delta = tracker.reconcile(known: [token], observed: nil)
            #expect(delta.hidden == [token])
            #expect(delta.removed.isEmpty)
        }
    }
    @Test func testTwoConfirmedAbsencesRemoveWindow() {
        var tracker = PresenceTracker()
        #expect(tracker.reconcile(known: [token], observed: []).removed.isEmpty)
        #expect(tracker.reconcile(known: [token], observed: []).removed == [token])
    }
    @Test func testReappearanceResetsCounter() {
        var tracker = PresenceTracker()
        _ = tracker.reconcile(known: [token], observed: [])
        _ = tracker.reconcile(known: [token], observed: [token])
        #expect(tracker.reconcile(known: [token], observed: []).removed.isEmpty)
    }
}

@Suite struct OrderingTests {
    let header = Rect(x: 100, y: 100, width: 500, height: 30)
    func window(_ id: UInt32, _ pid: Int32, _ frame: Rect? = nil) -> OrderedWindow {
        OrderedWindow(id: id, pid: pid, frame: frame ?? header)
    }
    @Test func testAdjacentHeaderAndTargetAllowed() {
        #expect(OrderingPolicy.isSafe(headerID: 10, targetID: 1, ownPID: 99, headerFrame: header,
                                      frontToBack: [window(10, 99), window(1, 2)]))
    }
    @Test func testIncorrectlyFloatingHeaderRejected() {
        #expect(!OrderingPolicy.isSafe(headerID: 10, targetID: 1, ownPID: 99, headerFrame: header,
                                       frontToBack: [window(10, 99), window(2, 3), window(1, 2)]))
    }
    @Test func testForeignWindowInFrontOfBothIsCorrect() {
        #expect(OrderingPolicy.isSafe(headerID: 10, targetID: 1, ownPID: 99, headerFrame: header,
                                      frontToBack: [window(2, 3), window(10, 99), window(1, 2)]))
    }
    @Test func testNonIntersectingIntermediateWindowAllowed() {
        #expect(OrderingPolicy.isSafe(headerID: 10, targetID: 1, ownPID: 99, headerFrame: header,
            frontToBack: [window(10, 99), window(2, 3, Rect(x: 1000, y: 0, width: 100, height: 100)), window(1, 2)]))
    }
    @Test func testHeaderBehindTargetRejected() {
        #expect(!OrderingPolicy.isSafe(headerID: 10, targetID: 1, ownPID: 99, headerFrame: header,
                                       frontToBack: [window(1, 2), window(10, 99)]))
    }
    @Test func testMissingIDsRejected() {
        #expect(!OrderingPolicy.isSafe(headerID: 10, targetID: 1, ownPID: 99, headerFrame: header,
                                       frontToBack: [window(1, 2)]))
        #expect(!OrderingPolicy.isSafe(headerID: 10, targetID: 1, ownPID: 99, headerFrame: header,
                                       frontToBack: [window(10, 99)]))
    }
}
