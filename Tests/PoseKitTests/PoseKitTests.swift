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

    // MARK: - Eye/ear joints

    func testEyeEarJointsAreAddressable() {
        let o = obs([
            .leftEye: CGPoint(x: 0.4, y: 0.9),
            .rightEye: CGPoint(x: 0.6, y: 0.9),
            .leftEar: CGPoint(x: 0.35, y: 0.88),
            .rightEar: CGPoint(x: 0.65, y: 0.88),
        ])
        XCTAssertEqual(o.location(.leftEye), CGPoint(x: 0.4, y: 0.9))
        XCTAssertEqual(o.location(.rightEye), CGPoint(x: 0.6, y: 0.9))
        XCTAssertEqual(o.location(.leftEar), CGPoint(x: 0.35, y: 0.88))
        XCTAssertEqual(o.location(.rightEar), CGPoint(x: 0.65, y: 0.88))
    }

    // MARK: - TiltSpec

    func testVerticalTiltIsZeroWhenPerfectlyVertical() {
        let o = obs([.neck: CGPoint(x: 0, y: 1), .root: CGPoint(x: 0, y: 0)])
        let spec = TiltSpec(id: "spine", label: "Spine", from: .root, to: .neck, axis: .vertical, tolerance: 5)
        XCTAssertEqual(spec.measure(o)!, 0, accuracy: 0.001)
        XCTAssertEqual(spec.score(o)!, 1, accuracy: 0.0001)
    }

    func testVerticalTiltSignMatchesLeanDirection() {
        // neck right of root → positive lean.
        let o = obs([.neck: CGPoint(x: 1, y: 1), .root: CGPoint(x: 0, y: 0)])
        let spec = TiltSpec(id: "spine", label: "Spine", from: .root, to: .neck, axis: .vertical, tolerance: 5)
        XCTAssertEqual(spec.measure(o)!, 45, accuracy: 0.001)
    }

    func testHorizontalTiltIsZeroWhenLevel() {
        let o = obs([.leftHip: CGPoint(x: 0, y: 0), .rightHip: CGPoint(x: 1, y: 0)])
        let spec = TiltSpec(id: "hips", label: "Hips", from: .leftHip, to: .rightHip, axis: .horizontal, tolerance: 2)
        XCTAssertEqual(spec.measure(o)!, 0, accuracy: 0.001)
    }

    func testHorizontalTiltSignMatchesHigherSide() {
        // right hip higher than left → positive.
        let o = obs([.leftHip: CGPoint(x: 0, y: 0), .rightHip: CGPoint(x: 1, y: 1)])
        let spec = TiltSpec(id: "hips", label: "Hips", from: .leftHip, to: .rightHip, axis: .horizontal, tolerance: 2)
        XCTAssertEqual(spec.measure(o)!, 45, accuracy: 0.001)
    }

    func testTiltSpecMissingJointYieldsNilScore() {
        let o = obs([.leftHip: .zero])
        let spec = TiltSpec(id: "hips", label: "Hips", from: .leftHip, to: .rightHip, axis: .horizontal, tolerance: 2)
        XCTAssertNil(spec.score(o))
    }

    func testTiltSpecScoreFallsOffOutsideTolerance() {
        let o = obs([.leftHip: CGPoint(x: 0, y: 0), .rightHip: CGPoint(x: 1, y: 1)]) // 45°
        let spec = TiltSpec(id: "hips", label: "Hips", from: .leftHip, to: .rightHip, axis: .horizontal,
                            target: 0, tolerance: 5)
        // err = 45, over tolerance 5 by 40, falloff 1 - 40/5 clamped to 0.
        XCTAssertEqual(spec.score(o)!, 0, accuracy: 0.0001)
    }

    func testPoseTargetCombinesAngleAndTiltSpecs() {
        let o = obs([
            .leftKnee: CGPoint(x: 0, y: 0),
            .leftHip: CGPoint(x: 0, y: 1),
            .leftAnkle: CGPoint(x: 1, y: 0),
        ])
        let angleSpec = JointAngleSpec(id: "knee", label: "Knee", vertex: .leftKnee, a: .leftHip, b: .leftAnkle,
                                       target: 90, tolerance: 10)
        let tiltSpec = TiltSpec(id: "spine", label: "Spine", from: .leftKnee, to: .leftHip, axis: .vertical,
                                tolerance: 5)
        let target = PoseTarget(name: "t", specs: [angleSpec], tiltSpecs: [tiltSpec])
        let score = target.score(o)
        XCTAssertEqual(score.metrics.count, 2)
        XCTAssertEqual(score.overall!, 100, accuracy: 0.0001) // both perfect
    }

    // MARK: - PoseScore Codable

    func testPoseScoreRoundTripsThroughJSON() throws {
        let score = PoseScore(overall: 87.5, metrics: [
            .init(id: "a", label: "A", measured: 91, target: 90, tolerance: 10, score: 1),
        ])
        let data = try JSONEncoder().encode(score)
        let decoded = try JSONDecoder().decode(PoseScore.self, from: data)
        XCTAssertEqual(decoded.overall, score.overall)
        XCTAssertEqual(decoded.metrics.first?.id, "a")
        XCTAssertTrue(decoded.metrics.first!.isMet)
    }
}
