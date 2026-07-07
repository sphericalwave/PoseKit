import XCTest
import CoreGraphics
@testable import PoseKit

final class PoseKitTests: XCTestCase {

    private func obs(_ pts: [BodyJoint: CGPoint]) -> PoseObservation {
        PoseObservation(points: pts.mapValues { .init(location: $0, confidence: 1) })
    }

    func testRightAngle() {
        // knee at origin, hip straight up, ankle straight right → 90°.
        let o = obs([
            .leftKnee: CGPoint(x: 0, y: 0),
            .leftHip: CGPoint(x: 0, y: 1),
            .leftAnkle: CGPoint(x: 1, y: 0),
        ])
        let a = o.angle(at: .leftKnee, .leftHip, .leftAnkle)
        XCTAssertNotNil(a)
        XCTAssertEqual(a!, 90, accuracy: 0.001)
    }

    func testStraightLegIs180() {
        let o = obs([
            .leftKnee: CGPoint(x: 0, y: 0),
            .leftHip: CGPoint(x: 0, y: 1),
            .leftAnkle: CGPoint(x: 0, y: -1),
        ])
        XCTAssertEqual(o.angle(at: .leftKnee, .leftHip, .leftAnkle)!, 180, accuracy: 0.001)
    }

    func testMissingJointYieldsNilScore() {
        let spec = JointAngleSpec(id: "knee", label: "Knee", vertex: .leftKnee,
                                  a: .leftHip, b: .leftAnkle, target: 90, tolerance: 10)
        let o = obs([.leftKnee: .zero, .leftHip: CGPoint(x: 0, y: 1)]) // no ankle
        XCTAssertNil(spec.score(o))
    }

    func testScoreWithinToleranceIsPerfect() {
        // 90° knee, target 90 ±10 → full credit.
        let o = obs([
            .leftKnee: CGPoint(x: 0, y: 0),
            .leftHip: CGPoint(x: 0, y: 1),
            .leftAnkle: CGPoint(x: 1, y: 0),
        ])
        let spec = JointAngleSpec(id: "knee", label: "Knee", vertex: .leftKnee,
                                  a: .leftHip, b: .leftAnkle, target: 90, tolerance: 10)
        XCTAssertEqual(spec.score(o)!, 1, accuracy: 0.0001)
    }

    func testScoreFallsOffOutsideTolerance() {
        // Actual 90°, target 70 ±10 → err 20, over 10, falloff 1 - 10/10 = 0.
        let o = obs([
            .leftKnee: CGPoint(x: 0, y: 0),
            .leftHip: CGPoint(x: 0, y: 1),
            .leftAnkle: CGPoint(x: 1, y: 0),
        ])
        let spec = JointAngleSpec(id: "knee", label: "Knee", vertex: .leftKnee,
                                  a: .leftHip, b: .leftAnkle, target: 70, tolerance: 10)
        XCTAssertEqual(spec.score(o)!, 0, accuracy: 0.0001)
    }

    func testTargetOverallAverages() {
        let o = obs([
            .leftKnee: CGPoint(x: 0, y: 0),
            .leftHip: CGPoint(x: 0, y: 1),
            .leftAnkle: CGPoint(x: 1, y: 0),
        ])
        let good = JointAngleSpec(id: "a", label: "A", vertex: .leftKnee, a: .leftHip, b: .leftAnkle, target: 90, tolerance: 10)
        let bad  = JointAngleSpec(id: "b", label: "B", vertex: .leftKnee, a: .leftHip, b: .leftAnkle, target: 70, tolerance: 10)
        let target = PoseTarget(name: "t", specs: [good, bad])
        let score = target.score(o)
        XCTAssertEqual(score.overall!, 50, accuracy: 0.0001)   // (1 + 0)/2 * 100
        XCTAssertEqual(score.metrics.count, 2)
        XCTAssertTrue(score.metrics[0].isMet)
        XCTAssertFalse(score.metrics[1].isMet)
    }
}
