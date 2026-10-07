# PoseKit

Pose detection and scoring for exercise-form apps. Wraps Apple Vision to turn a camera
frame into a `PoseObservation`, then scores it against a declarative `PoseTarget` (a
set of joint-angle specs) for a live 0-100 score plus per-metric detail.

## Requirements

- iOS 17+ / macOS 14+
- Swift 5.9+

## Installation

```swift
.package(url: "https://github.com/sphericalwave/PoseKit.git", branch: "main")
```

## Overview

- `BodyPoseDetector` — Apple Vision adapter turning a camera frame into a `PoseObservation`; kept behind `canImport(Vision)` so the scoring core stays portable
- `BodyJoint` / `PoseObservation` — detected joints and their positions
- `JointAngleSpec` — one measured joint angle and its acceptable band
- `PoseTarget` — a declarative target: a set of `JointAngleSpec`s (e.g. "front knee ~90°", "torso-thigh tuck ~120°")
- `PoseScore` — result of scoring an observation against a target
- `MovementMetric` — a range-of-motion metric: one body segment's signed angle against a reference line, filmed side-on (e.g. `.shoulderFlexion`, humerus vs torso, reads past 180° for hyperflexion)
- `MetricTracker` — feeds a clip or live session through a metric, finds the peak and the longest steady hold, and returns a Codable `MovementMeasurement`
- `VideoPoseReader` — samples a video file through Vision and measures a metric across it; behind `canImport(Vision)`

## Dependencies

None.
