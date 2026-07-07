//
//  BodyPoseDetector.swift
//  PoseKit
//
//  Apple Vision adapter: turns a camera frame into a PoseObservation. Kept
//  behind `canImport(Vision)` so the pure scoring core stays portable.
//

#if canImport(Vision)
import Vision
import CoreVideo
import CoreGraphics

public enum BodyPoseDetector {

    private static let jointMap: [(BodyJoint, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .nose), (.neck, .neck),
        (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow),
        (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
        (.root, .root),
    ]

    /// Detect the most prominent body pose in a frame. Returns nil if no body
    /// is found.
    public static func detect(in pixelBuffer: CVPixelBuffer,
                              orientation: CGImagePropertyOrientation = .up) -> PoseObservation? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let observation = request.results?.first else { return nil }
        return map(observation)
    }

    public static func map(_ o: VNHumanBodyPoseObservation) -> PoseObservation {
        var points: [BodyJoint: PoseObservation.Point] = [:]
        for (joint, name) in jointMap {
            guard let p = try? o.recognizedPoint(name), p.confidence > 0 else { continue }
            points[joint] = PoseObservation.Point(
                location: CGPoint(x: p.location.x, y: p.location.y),
                confidence: Double(p.confidence)
            )
        }
        return PoseObservation(points: points)
    }
}
#endif
