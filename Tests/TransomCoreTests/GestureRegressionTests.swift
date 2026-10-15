import Testing
import TransomCore

@Suite struct GestureRegressionTests {
    @Test func testThirdClickIsARegularDragAfterOneDoubleClick() {
        var gesture = TitleBarGesture()

        #expect(gesture.mouseDown(clickCount: 1) == [.beginDrag])
        #expect(gesture.mouseUp() == [.endDrag])

        #expect(gesture.mouseDown(clickCount: 2).isEmpty)
        #expect(gesture.mouseUp() == [.doubleClick])

        #expect(gesture.mouseDown(clickCount: 3) == [.beginDrag])
        #expect(gesture.mouseDragged(distance: 3) == [.moveDrag])
        #expect(gesture.mouseUp() == [.endDrag])
    }

    @Test func testMenuBarPointerUsesItsPhysicalScreensVisibleTop() {
        let full = Rect(x: 0, y: 0, width: 1440, height: 900)
        let visible = Rect(x: 0, y: 25, width: 1440, height: 850)
        let result = Geometry.dragPoint(Point(x: 100, y: 10), mouse: Point(x: 500, y: 10),
                                        fullFrames: [full], visibleFrames: [visible], headerHeight: 30)
        #expect(result == Point(x: 100, y: 55))
    }

    @Test func testNegativeCoordinateScreenUsesCorrespondingVisibleFrame() {
        let primaryFull = Rect(x: 0, y: 0, width: 1440, height: 900)
        let secondaryFull = Rect(x: -1920, y: -300, width: 1920, height: 1000)
        let primaryVisible = Rect(x: 0, y: 25, width: 1440, height: 850)
        let secondaryVisible = Rect(x: -1920, y: -275, width: 1920, height: 950)
        let result = Geometry.dragPoint(Point(x: -1800, y: -400), mouse: Point(x: -1700, y: -280),
                                        fullFrames: [primaryFull, secondaryFull],
                                        visibleFrames: [primaryVisible, secondaryVisible], headerHeight: 30)
        #expect(result == Point(x: -1800, y: -245))
    }

    @Test func testPointerOutsideAllScreensDoesNotFallbackOrClamp() {
        let full = Rect(x: 0, y: 0, width: 1440, height: 900)
        let visible = Rect(x: 0, y: 25, width: 1440, height: 850)
        let desired = Point(x: 1600, y: -100)
        #expect(Geometry.dragPoint(desired, mouse: Point(x: 1600, y: 950), fullFrames: [full],
                                   visibleFrames: [visible], headerHeight: 30) == desired)
    }
}
