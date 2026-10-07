//
//  MetricTracker.swift
//  PoseKit
//
//  Runs one MovementMetric over a stream of poses — a recorded clip or a
//  live camera feed — and sums it up as a MovementMeasurement: the peak,
//  the longest steady hold, and the number to chart.
//

import Foundation

/// One measured frame.
public struct MetricSample: Sendable, Codable, Equatable {
    /// Seconds from the start of the clip or session.
    public let t: Double
    public let degrees: Double
    public let side: BodySide
    public let facing: Facing

    public init(t: Double, degrees: Double, side: BodySide, facing: Facing) {
        self.t = t
        self.degrees = degrees
        self.side = side
        self.facing = facing
    }
}

/// The result of measuring one clip or session. Codable so apps can store it
/// whole next to the headline number.
public struct MovementMeasurement: Sendable, Codable, Equatable {
    public struct Hold: Sendable, Codable, Equatable {
        /// Median angle across the hold.
        public let degrees: Double
        public let start: Double
        public let duration: Double
    }

    /// Bumped when how measurements are computed changes, so old and new
    /// results can be told apart.
    public static let currentVersion = 1

    public let version: Int
    public let metricID: String
    /// The number to chart: the hold angle for a hold metric that found one,
    /// otherwise the peak.
    public let value: Double
    public let peak: Double
    public let hold: Hold?
    public let side: BodySide
    public let facing: Facing
    /// Seconds of poses seen, measured or not.
    public let duration: Double
    public let framesSeen: Int
    public let framesMeasured: Int
    /// The smoothed angle over time, thinned to at most `traceLimit` points.
    public let trace: [MetricSample]

    public static let traceLimit = 120

    /// Fraction of frames the metric could be read in.
    public var coverage: Double {
        framesSeen == 0 ? 0 : Double(framesMeasured) / Double(framesSeen)
    }
}

public struct MetricTracker: Sendable {
    public let metric: MovementMetric

    private var samples: [MetricSample] = []
    private var firstTime: Double?
    private var lastTime: Double?
    private var framesSeen = 0
    private var lastFacing: Facing?

    public init(metric: MovementMetric) {
        self.metric = metric
    }

    /// Adds one frame. Returns its sample for a live readout, or nil when
    /// the metric couldn't be read in it.
    @discardableResult
    public mutating func add(time: Double, observation: PoseObservation) -> MetricSample? {
        framesSeen += 1
        if firstTime == nil { firstTime = time }
        lastTime = time
        // The head can drop out of a frame or two; keep the last facing.
        if let f = observation.facing(minConfidence: metric.minConfidence) { lastFacing = f }
        guard let facing = lastFacing,
              let side = metric.visibleSide(in: observation),
              let degrees = metric.measure(observation, side: side, facing: facing) else { return nil }
        let sample = MetricSample(t: time - (firstTime ?? time), degrees: degrees, side: side, facing: facing)
        samples.append(sample)
        return sample
    }

    /// Sums up everything added so far. nil when nothing was measurable.
    public func result() -> MovementMeasurement? {
        // A frame or two read with the wrong facing comes out mirrored —
        // drop whatever disagrees with the majority.
        let facing = Self.majority(samples.map(\.facing))
        let kept = samples.filter { $0.facing == facing }
        guard let facing, !kept.isEmpty else { return nil }
        let side = Self.majority(kept.map(\.side)) ?? kept[0].side

        let smoothed = Self.medianFiltered(kept.map(\.degrees), radius: 2)
        let series = zip(kept, smoothed).map { MetricSample(t: $0.t, degrees: $1, side: $0.side, facing: $0.facing) }
        let peak = smoothed.max() ?? 0

        var hold: MovementMeasurement.Hold?
        if case .hold(let tolerance, let minimumSeconds) = metric.mode {
            hold = Self.longestHold(series, band: tolerance * 2, minimumSeconds: minimumSeconds)
        }

        return MovementMeasurement(
            version: MovementMeasurement.currentVersion,
            metricID: metric.id,
            value: hold?.degrees ?? peak,
            peak: peak,
            hold: hold,
            side: side,
            facing: facing,
            duration: (lastTime ?? 0) - (firstTime ?? 0),
            framesSeen: framesSeen,
            framesMeasured: kept.count,
            trace: Self.thinned(series, to: MovementMeasurement.traceLimit)
        )
    }

    // MARK: - Helpers

    static func majority<T: Hashable>(_ values: [T]) -> T? {
        var counts: [T: Int] = [:]
        for v in values { counts[v, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }

    /// Each value replaced by the median of itself and `radius` neighbours
    /// either side — knocks out single-frame glitches without blurring a
    /// plateau.
    static func medianFiltered(_ values: [Double], radius: Int) -> [Double] {
        values.indices.map { i in
            let window = values[max(0, i - radius)...min(values.count - 1, i + radius)].sorted()
            return window[window.count / 2]
        }
    }

    /// The longest stretch whose angles all fit inside `band` degrees,
    /// lasting at least `minimumSeconds`. Ties go to the higher angle.
    static func longestHold(_ series: [MetricSample], band: Double,
                            minimumSeconds: Double) -> MovementMeasurement.Hold? {
        var best: (start: Int, end: Int, duration: Double, median: Double)?
        for i in series.indices {
            var lo = series[i].degrees, hi = lo
            var j = i
            while j + 1 < series.count {
                let next = series[j + 1].degrees
                let nlo = min(lo, next), nhi = max(hi, next)
                guard nhi - nlo <= band else { break }
                lo = nlo; hi = nhi; j += 1
            }
            let duration = series[j].t - series[i].t
            guard duration >= minimumSeconds else { continue }
            let window = series[i...j].map(\.degrees).sorted()
            let median = window[window.count / 2]
            if let b = best, duration < b.duration || (duration == b.duration && median <= b.median) { continue }
            best = (i, j, duration, median)
        }
        guard let best else { return nil }
        return .init(degrees: best.median, start: series[best.start].t, duration: best.duration)
    }

    static func thinned(_ series: [MetricSample], to limit: Int) -> [MetricSample] {
        guard series.count > limit, limit > 1 else { return series }
        let step = Double(series.count - 1) / Double(limit - 1)
        return (0..<limit).map { series[Int((Double($0) * step).rounded())] }
    }
}
