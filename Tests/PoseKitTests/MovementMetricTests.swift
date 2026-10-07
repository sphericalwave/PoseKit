import XCTest
import CoreGraphics
@testable import PoseKit

final class MovementMetricTests: XCTestCase {

    private let metric = MovementMetric.shoulderFlexion

    /// A side-on figure facing right (nose ahead of the ear), left side
    /// toward the camera, with the upper arm at `armDegrees` measured
    /// counter-clockwise from straight down.
    private func figure(armDegrees: Double, facing: Facing = .right, aspect: Double = 1) -> PoseObservation {
        let shoulder = CGPoint(x: 0.5, y: 0.7)
        let sign = facing == .right ? 1.0 : -1.0
        let rad = (armDegrees - 90) * .pi / 180
        // Length 0.2 in true (aspect-corrected) units.
        let elbow = CGPoint(x: shoulder.x + CGFloat(sign * cos(rad) * 0.2 / aspect),
                            y: shoulder.y + CGFloat(sin(rad) * 0.2))
        let pts: [BodyJoint: CGPoint] = [
            .leftShoulder: shoulder,
            .leftElbow: elbow,
            .leftHip: CGPoint(x: 0.5, y: 0.4),
            .leftEar: CGPoint(x: 0.5, y: 0.8),
            .nose: CGPoint(x: 0.5 + sign * 0.03, y: 0.79),
        ]
        return PoseObservation(points: pts.mapValues { .init(location: $0, confidence: 0.9) },
                               aspectRatio: aspect)
    }

    func testArmsDownIsZero() {
        XCTAssertEqual(metric.measure(figure(armDegrees: 0), side: .left, facing: .right)!, 0, accuracy: 0.01)
    }

    func testArmForwardIs90() {
        XCTAssertEqual(metric.measure(figure(armDegrees: 90), side: .left, facing: .right)!, 90, accuracy: 0.01)
    }

    func testHyperflexionReadsPast180() {
        XCTAssertEqual(metric.measure(figure(armDegrees: 200), side: .left, facing: .right)!, 200, accuracy: 0.01)
    }

    func testExtensionIsNegative() {
        XCTAssertEqual(metric.measure(figure(armDegrees: -30), side: .left, facing: .right)!, -30, accuracy: 0.01)
    }

    func testFacingLeftMirrors() {
        let o = figure(armDegrees: 200, facing: .left)
        XCTAssertEqual(o.facing(), .left)
        XCTAssertEqual(metric.measure(o, side: .left, facing: .left)!, 200, accuracy: 0.01)
    }

    func testAspectRatioCorrected() {
        // Portrait 9:16 frame: without correction 45° would read wrong.
        let o = figure(armDegrees: 45, aspect: 9.0 / 16.0)
        XCTAssertEqual(metric.measure(o, side: .left, facing: .right)!, 45, accuracy: 0.01)
    }

    func testRightSideMirrorsJoints() {
        let left = figure(armDegrees: 170)
        let right = PoseObservation(points: Dictionary(uniqueKeysWithValues:
            left.points.map { ($0.key.mirrored, $0.value) }))
        XCTAssertEqual(metric.visibleSide(in: right), .right)
        XCTAssertEqual(metric.measure(right, side: .right, facing: .right)!, 170, accuracy: 0.01)
    }

    func testMissingElbowIsNil() {
        var o = figure(armDegrees: 90)
        o.points[.leftElbow] = nil
        XCTAssertNil(metric.visibleSide(in: o))
    }

    // MARK: - Tracker

    func testTrackerFindsHoldAndPeak() {
        var tracker = MetricTracker(metric: metric)
        var t = 0.0
        // 2 s raising the arm, 10 s holding ~195 ± 2, a one-frame 230 spike, 1 s lowering.
        for i in 0..<20 { tracker.add(time: t, observation: figure(armDegrees: Double(i) * 9.5)); t += 0.1 }
        for i in 0..<100 {
            let wobble = i.isMultiple(of: 2) ? 2.0 : -2.0
            tracker.add(time: t, observation: figure(armDegrees: 195 + wobble)); t += 0.1
        }
        tracker.add(time: t, observation: figure(armDegrees: 230)); t += 0.1
        for i in 0..<10 { tracker.add(time: t, observation: figure(armDegrees: 190 - Double(i) * 19)); t += 0.1 }

        let r = tracker.result()!
        XCTAssertEqual(r.metricID, "shoulder.flexion")
        XCTAssertNotNil(r.hold)
        XCTAssertEqual(r.hold!.degrees, 195, accuracy: 2.5)
        XCTAssertGreaterThanOrEqual(r.hold!.duration, 9)
        XCTAssertEqual(r.value, r.hold!.degrees)
        // The single-frame spike is filtered out of the peak.
        XCTAssertLessThan(r.peak, 210)
        XCTAssertEqual(r.facing, .right)
        XCTAssertEqual(r.side, .left)
        XCTAssertLessThanOrEqual(r.trace.count, MovementMeasurement.traceLimit)
    }

    func testNoSteadyHoldFallsBackToPeak() {
        var tracker = MetricTracker(metric: metric)
        for i in 0..<40 { tracker.add(time: Double(i) * 0.1, observation: figure(armDegrees: Double(i) * 5)) }
        let r = tracker.result()!
        XCTAssertNil(r.hold)
        XCTAssertEqual(r.value, r.peak)
    }

    func testNothingMeasurableIsNil() {
        var tracker = MetricTracker(metric: metric)
        tracker.add(time: 0, observation: PoseObservation(points: [:]))
        XCTAssertNil(tracker.result())
    }

    func testMeasurementRoundTripsThroughJSON() throws {
        var tracker = MetricTracker(metric: metric)
        for i in 0..<80 { tracker.add(time: Double(i) * 0.1, observation: figure(armDegrees: 190)) }
        let r = tracker.result()!
        let decoded = try JSONDecoder().decode(MovementMeasurement.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(decoded, r)
    }
}
