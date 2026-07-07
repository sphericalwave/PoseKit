//
//  PoseObservation.swift
//  PoseKit
//
//  A platform-agnostic snapshot of a detected body pose: normalized joint
//  locations (0…1, origin bottom-left like Vision) + confidences, plus the
//  angle math the scorer runs on. No Vision dependency here so it's testable
//  anywhere.
//

import Foundation
import CoreGraphics

public enum BodyJoint: String, Sendable, CaseIterable {
    case nose, neck
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
    case root
}

public struct PoseObservation: Sendable {
    public struct Point: Sendable {
        public let location: CGPoint
        public let confidence: Double
        public init(location: CGPoint, confidence: Double) {
            self.location = location
            self.confidence = confidence
        }
    }

    public var points: [BodyJoint: Point]

    public init(points: [BodyJoint: Point]) {
        self.points = points
    }

    public func location(_ joint: BodyJoint, minConfidence: Double = 0.1) -> CGPoint? {
        guard let p = points[joint], p.confidence >= minConfidence else { return nil }
        return p.location
    }

    /// Interior angle (degrees, 0…180) at `vertex` between the `a` and `b` rays.
    public func angle(at vertex: BodyJoint, _ a: BodyJoint, _ b: BodyJoint,
                      minConfidence: Double = 0.1) -> Double? {
        guard let v = location(vertex, minConfidence: minConfidence),
              let pa = location(a, minConfidence: minConfidence),
              let pb = location(b, minConfidence: minConfidence) else { return nil }
        return Self.angle(atVertex: v, pa, pb)
    }

    public static func angle(atVertex v: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double? {
        let ax = Double(a.x - v.x), ay = Double(a.y - v.y)
        let bx = Double(b.x - v.x), by = Double(b.y - v.y)
        let ma = (ax * ax + ay * ay).squareRoot()
        let mb = (bx * bx + by * by).squareRoot()
        guard ma > 0, mb > 0 else { return nil }
        let cosine = Swift.max(-1.0, Swift.min(1.0, (ax * bx + ay * by) / (ma * mb)))
        return acos(cosine) * 180.0 / Double.pi
    }
}
