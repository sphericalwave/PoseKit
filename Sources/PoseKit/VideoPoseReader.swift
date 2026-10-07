//
//  VideoPoseReader.swift
//  PoseKit
//
//  Reads a video file at a fixed sample rate and runs Vision's 2D body pose
//  over each frame, and measures a MovementMetric across a whole clip. Kept
//  behind `canImport(Vision)` like BodyPoseDetector, so the metric core
//  stays portable. Works the same on iOS and macOS.
//

#if canImport(Vision) && canImport(AVFoundation)
import Foundation
import AVFoundation
import Vision
import ImageIO

public struct TimedPose: Sendable {
    /// Seconds from the start of the range read.
    public let time: Double
    public let observation: PoseObservation
}

public enum VideoPoseReader {
    public enum ReadError: LocalizedError {
        case noVideoTrack
        case noBodyFound

        public var errorDescription: String? {
            switch self {
            case .noVideoTrack: "That file has no video."
            case .noBodyFound: "No person was found in the video. Film the whole body side-on, in good light."
            }
        }
    }

    /// - Parameters:
    ///   - range: seconds into the video; nil reads the whole file.
    ///   - progress: 0…1, called off the main actor.
    public static func read(
        url: URL,
        range: ClosedRange<Double>? = nil,
        fps: Double = 10,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> [TimedPose] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ReadError.noVideoTrack
        }
        let duration = try await asset.load(.duration).seconds
        let transform = try await track.load(.preferredTransform)
        let size = try await track.load(.naturalSize)
        let orientation = Self.orientation(for: transform)
        let sideways = orientation == .left || orientation == .right
        let aspect = sideways ? Double(size.height / size.width) : Double(size.width / size.height)

        let start = max(0, range?.lowerBound ?? 0)
        let end = min(duration, range?.upperBound ?? duration)
        guard end > start else { throw ReadError.noBodyFound }

        let poses = try await Task.detached(priority: .userInitiated) {
            try decode(asset: asset, track: track, start: start, end: end, fps: fps,
                       orientation: orientation, aspect: aspect, progress: progress)
        }.value
        guard !poses.isEmpty else { throw ReadError.noBodyFound }
        return poses
    }

    /// Reads a clip and measures `metric` across it.
    public static func measure(
        _ metric: MovementMetric,
        url: URL,
        range: ClosedRange<Double>? = nil,
        fps: Double = 10,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> MovementMeasurement {
        let poses = try await read(url: url, range: range, fps: fps, progress: progress)
        var tracker = MetricTracker(metric: metric)
        for pose in poses { tracker.add(time: pose.time, observation: pose.observation) }
        guard let result = tracker.result() else { throw ReadError.noBodyFound }
        return result
    }

    private static func decode(
        asset: AVURLAsset,
        track: AVAssetTrack,
        start: Double,
        end: Double,
        fps: Double,
        orientation: CGImagePropertyOrientation,
        aspect: Double,
        progress: @Sendable (Double) -> Void
    ) throws -> [TimedPose] {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                       end: CMTime(seconds: end, preferredTimescale: 600))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ReadError.noVideoTrack }

        let step = 1 / max(fps, 1)
        var nextTime = start
        var poses: [TimedPose] = []
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            guard time + 0.0001 >= nextTime, let pixels = CMSampleBufferGetImageBuffer(buffer) else { continue }
            nextTime += step
            progress(min(1, (time - start) / (end - start)))

            guard var observation = BodyPoseDetector.detect(in: pixels, orientation: orientation) else { continue }
            observation.aspectRatio = aspect
            poses.append(TimedPose(time: time - start, observation: observation))
        }
        progress(1)
        return poses
    }

    private static func orientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0): .right
        case (0, -1, 1, 0): .left
        case (-1, 0, 0, -1): .down
        default: .up
        }
    }
}
#endif
