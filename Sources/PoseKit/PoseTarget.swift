//
//  PoseTarget.swift
//  PoseKit
//
//  Declarative target for a pose: a set of joint-angle specs (e.g. "front knee
//  ~90°", "torso-thigh tuck ~120°"). Scoring an observation against it yields a
//  0–100 overall plus per-metric detail for a live HUD.
//

import Foundation

/// One measured joint angle and its acceptable band.
public struct JointAngleSpec: Sendable, Identifiable {
    public let id: String
    public let label: String
    public let vertex: BodyJoint
    public let a: BodyJoint
    public let b: BodyJoint
    /// Desired interior angle in degrees.
    public let target: Double
    /// Full credit within ±tolerance; linear falloff to 0 over the next
    /// `tolerance` degrees beyond the band.
    public let tolerance: Double

    public init(id: String, label: String, vertex: BodyJoint, a: BodyJoint, b: BodyJoint,
                target: Double, tolerance: Double) {
        self.id = id
        self.label = label
        self.vertex = vertex
        self.a = a
        self.b = b
        self.target = target
        self.tolerance = tolerance
    }

    public func measure(_ obs: PoseObservation) -> Double? {
        obs.angle(at: vertex, a, b)
    }

    /// 0…1, or nil if the joints aren't visible enough to measure.
    public func score(_ obs: PoseObservation) -> Double? {
        guard let m = measure(obs) else { return nil }
        let err = abs(m - target)
        if err <= tolerance { return 1 }
        return Swift.max(0, 1 - (err - tolerance) / max(tolerance, 0.001))
    }
}

public struct PoseTarget: Sendable {
    public let name: String
    public let specs: [JointAngleSpec]

    public init(name: String, specs: [JointAngleSpec]) {
        self.name = name
        self.specs = specs
    }

    public func score(_ obs: PoseObservation) -> PoseScore {
        let metrics = specs.map { spec in
            PoseScore.MetricResult(
                id: spec.id,
                label: spec.label,
                measured: spec.measure(obs),
                target: spec.target,
                tolerance: spec.tolerance,
                score: spec.score(obs)
            )
        }
        let scored = metrics.compactMap(\.score)
        let overall = scored.isEmpty ? nil : (scored.reduce(0, +) / Double(scored.count)) * 100
        return PoseScore(overall: overall, metrics: metrics)
    }
}

public struct PoseScore: Sendable {
    public struct MetricResult: Sendable, Identifiable {
        public let id: String
        public let label: String
        public let measured: Double?
        public let target: Double
        public let tolerance: Double
        public let score: Double?     // 0…1

        public var isMet: Bool { (score ?? 0) >= 0.999 }
    }

    /// 0…100, or nil when nothing could be measured.
    public let overall: Double?
    public let metrics: [MetricResult]
}
