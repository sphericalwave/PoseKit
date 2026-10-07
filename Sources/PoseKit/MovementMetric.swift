//
//  MovementMetric.swift
//  PoseKit
//
//  Range-of-motion measurement: one metric per movement, declared as "the
//  angle of this body segment against that reference line", e.g. shoulder
//  flexion = the humerus (shoulder→elbow) against the torso line
//  (shoulder→hip). Filmed side-on, so the angle lives in the image plane.
//
//  Angles are signed and run past 180° — 0 is the segment lying along the
//  reference, positive is toward the way the person faces (or away, per
//  metric). A hyperflexed shoulder reads 200°, not the 160° an interior
//  angle would give back.
//
//  Metric IDs are stored by apps next to each result, so they are API: add
//  metrics, never rename or remove one.
//

import Foundation
import CoreGraphics

public enum BodySide: String, Sendable, Codable {
    case left, right
}

/// Which way the person faces in the image: toward its left or right edge.
public enum Facing: String, Sendable, Codable {
    case left, right
}

extension BodyJoint {
    /// The same joint on the other side; midline joints map to themselves.
    public var mirrored: BodyJoint {
        switch self {
        case .leftEye: .rightEye
        case .rightEye: .leftEye
        case .leftEar: .rightEar
        case .rightEar: .leftEar
        case .leftShoulder: .rightShoulder
        case .rightShoulder: .leftShoulder
        case .leftElbow: .rightElbow
        case .rightElbow: .leftElbow
        case .leftWrist: .rightWrist
        case .rightWrist: .leftWrist
        case .leftHip: .rightHip
        case .rightHip: .leftHip
        case .leftKnee: .rightKnee
        case .rightKnee: .leftKnee
        case .leftAnkle: .rightAnkle
        case .rightAnkle: .leftAnkle
        case .nose, .neck, .root: self
        }
    }
}

/// A direction on the body from one joint to another, e.g. shoulder→elbow.
public struct Segment: Sendable, Equatable {
    public let from: BodyJoint
    public let to: BodyJoint

    public init(_ from: BodyJoint, _ to: BodyJoint) {
        self.from = from
        self.to = to
    }

    var joints: [BodyJoint] { [from, to] }

    func mirrored(_ side: BodySide) -> Segment {
        side == .left ? self : Segment(from.mirrored, to.mirrored)
    }
}

public struct MovementMetric: Sendable, Identifiable {
    public enum Reference: Sendable {
        /// Another body segment, e.g. the torso line.
        case segment(Segment)
        /// Straight down in the image (gravity, with a level camera).
        case verticalDown
    }

    /// What a clip's single number is.
    public enum Mode: Sendable {
        /// The furthest point reached.
        case peak
        /// The angle held longest without drifting more than ±`tolerance`
        /// degrees, if held at least `minimumSeconds`; otherwise the peak.
        case hold(tolerance: Double, minimumSeconds: Double)
    }

    public let id: String
    public let label: String
    /// Short instruction for filming it, e.g. "Film side-on…".
    public let filmingTip: String
    /// Joints named on the left side; the right side is the mirror.
    public let reference: Reference
    public let segment: Segment
    /// True when the movement swings the segment toward the way the person
    /// faces (shoulder or hip flexion); false when away (knee flexion).
    public let positiveTowardFacing: Bool
    /// Low end of the reported range; angles wrap into
    /// `wrapStart ..< wrapStart + 360`.
    public let wrapStart: Double
    public let mode: Mode
    public let minConfidence: Double

    public init(id: String, label: String, filmingTip: String,
                reference: Reference, segment: Segment,
                positiveTowardFacing: Bool = true, wrapStart: Double = -90,
                mode: Mode = .peak, minConfidence: Double = 0.3) {
        self.id = id
        self.label = label
        self.filmingTip = filmingTip
        self.reference = reference
        self.segment = segment
        self.positiveTowardFacing = positiveTowardFacing
        self.wrapStart = wrapStart
        self.mode = mode
        self.minConfidence = minConfidence
    }

    // MARK: - Catalog

    /// Shoulder flexion: the humerus against the torso line. Arms by the
    /// sides read 0°, straight overhead 180°, past overhead (hyperflexion)
    /// beyond 180°.
    public static let shoulderFlexion = MovementMetric(
        id: "shoulder.flexion",
        label: "Shoulder Flexion",
        filmingTip: "Film side-on from shoulder height, phone still, whole body in frame.",
        reference: .segment(Segment(.leftShoulder, .leftHip)),
        segment: Segment(.leftShoulder, .leftElbow),
        mode: .hold(tolerance: 4, minimumSeconds: 5)
    )

    public static let all: [MovementMetric] = [shoulderFlexion]

    public static func named(_ id: String) -> MovementMetric? {
        all.first { $0.id == id }
    }

    // MARK: - Measuring

    var joints: [BodyJoint] {
        var joints = segment.joints
        if case .segment(let r) = reference { joints += r.joints }
        return joints
    }

    /// The angle on one side for a known facing, or nil if any joint it
    /// needs isn't confidently visible.
    public func measure(_ obs: PoseObservation, side: BodySide, facing: Facing) -> Double? {
        let seg = segment.mirrored(side)
        guard let s = vector(seg, in: obs) else { return nil }
        let r: CGVector
        switch reference {
        case .verticalDown:
            r = CGVector(dx: 0, dy: -1)
        case .segment(let ref):
            guard let v = vector(ref.mirrored(side), in: obs) else { return nil }
            r = v
        }
        // Counter-clockwise from reference to segment (y up, like Vision).
        let cross = Double(r.dx * s.dy - r.dy * s.dx)
        let dot = Double(r.dx * s.dx + r.dy * s.dy)
        var degrees = atan2(cross, dot) * 180 / .pi
        // Counter-clockwise turns toward +x from straight down, so it points
        // the way someone facing right faces.
        if facing == .left { degrees = -degrees }
        if !positiveTowardFacing { degrees = -degrees }
        while degrees < wrapStart { degrees += 360 }
        while degrees >= wrapStart + 360 { degrees -= 360 }
        return degrees
    }

    /// The side the camera sees best: the one whose joints for this metric
    /// have the higher worst-case confidence.
    public func visibleSide(in obs: PoseObservation) -> BodySide? {
        func worst(_ side: BodySide) -> Double? {
            let js = side == .left ? joints : joints.map(\.mirrored)
            let cs = js.map { obs.points[$0]?.confidence ?? 0 }
            guard let m = cs.min(), m >= minConfidence else { return nil }
            return m
        }
        switch (worst(.left), worst(.right)) {
        case let (l?, r?): return l >= r ? .left : .right
        case (_?, nil): return .left
        case (nil, _?): return .right
        case (nil, nil): return nil
        }
    }

    private func vector(_ seg: Segment, in obs: PoseObservation) -> CGVector? {
        guard let a = obs.location(seg.from, minConfidence: minConfidence),
              let b = obs.location(seg.to, minConfidence: minConfidence) else { return nil }
        let v = CGVector(dx: (b.x - a.x) * CGFloat(obs.aspectRatio), dy: b.y - a.y)
        guard v.dx != 0 || v.dy != 0 else { return nil }
        return v
    }
}

extension PoseObservation {
    /// Which way the person faces, from the nose's offset past the ear (or
    /// the neck when no ear is visible). Side-on views only; nil when the
    /// head isn't visible or is seen straight on.
    public func facing(minConfidence: Double = 0.3) -> Facing? {
        guard let nose = location(.nose, minConfidence: minConfidence) else { return nil }
        let ears = [BodyJoint.leftEar, .rightEar]
            .compactMap { j in points[j].flatMap { $0.confidence >= minConfidence ? $0 : nil } }
        let back = ears.max { $0.confidence < $1.confidence }?.location
            ?? location(.neck, minConfidence: minConfidence)
        guard let back else { return nil }
        let dx = Double(nose.x - back.x) * aspectRatio
        guard abs(dx) > 0.005 else { return nil }
        return dx > 0 ? .right : .left
    }
}
