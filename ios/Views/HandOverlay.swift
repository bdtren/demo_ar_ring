// Copyright 2023 The MediaPipe Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import UIKit
import MediaPipeTasksVision

/// A straight line.
struct Line {
  let from: CGPoint
  let to: CGPoint
}

/**
 This structure holds the display parameters for the overlay to be drawon on a hand landmarker object.
 */
struct HandOverlay {
  let dots: [CGPoint]
  let lines: [Line]
}

/// Custom view to visualize the face landmarks result on top of the input image.
class OverlayView: UIView {

  var handOverlays: [HandOverlay] = []
  private var glView: GLView?
  private var contentImageSize: CGSize = CGSizeZero
  var imageContentMode: UIView.ContentMode = .scaleAspectFit
  private var orientation = UIDeviceOrientation.portrait

  private var edgeOffset: CGFloat = 0.0

  override init(frame: CGRect) {
    super.init(frame: frame)
    setupGLView()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupGLView()
  }

  private func setupGLView() {
    glView = GLView(frame: bounds)
    if let glView = glView {
      addSubview(glView)
      glView.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        glView.topAnchor.constraint(equalTo: topAnchor),
        glView.leadingAnchor.constraint(equalTo: leadingAnchor),
        glView.trailingAnchor.constraint(equalTo: trailingAnchor),
        glView.bottomAnchor.constraint(equalTo: bottomAnchor)
      ])
    }
  }


  // MARK: Public Functions
  func draw(
    handOverlays: [HandOverlay],
    inBoundsOfContentImageOfSize imageSize: CGSize,
    edgeOffset: CGFloat = 0.0,
    imageContentMode: UIView.ContentMode) {

      self.clear()
      contentImageSize = imageSize
      self.edgeOffset = edgeOffset
      self.handOverlays = handOverlays
      self.imageContentMode = imageContentMode
      orientation = UIDevice.current.orientation
      self.setNeedsDisplay()
    }

  func redrawHandOverlays(forNewDeviceOrientation deviceOrientation:UIDeviceOrientation) {

    orientation = deviceOrientation

    switch orientation {
    case .portrait:
      fallthrough
    case .landscapeLeft:
      fallthrough
    case .landscapeRight:
      self.setNeedsDisplay()
    default:
      return
    }
  }

  func clear() {
    handOverlays = []
    contentImageSize = CGSize.zero
    imageContentMode = .scaleAspectFit
    orientation = UIDevice.current.orientation
    edgeOffset = 0.0
    setNeedsDisplay()
  }

  override func draw(_ rect: CGRect) {
    for handOverlay in handOverlays {
      drawLines(handOverlay.lines)
    }
  }

  // MARK: Private Functions
  private func rectAfterApplyingBoundsAdjustment(
    onOverlayBorderRect borderRect: CGRect) -> CGRect {

      var currentSize = self.bounds.size
      let minDimension = min(self.bounds.width, self.bounds.height)
      let maxDimension = max(self.bounds.width, self.bounds.height)

      switch orientation {
      case .portrait:
        currentSize = CGSizeMake(minDimension, maxDimension)
      case .landscapeLeft:
        fallthrough
      case .landscapeRight:
        currentSize = CGSizeMake(maxDimension, minDimension)
      default:
        break
      }

      let offsetsAndScaleFactor = OverlayView.offsetsAndScaleFactor(
        forImageOfSize: self.contentImageSize,
        tobeDrawnInViewOfSize: currentSize,
        withContentMode: imageContentMode)

      var newRect = borderRect
        .applying(
          CGAffineTransform(scaleX: offsetsAndScaleFactor.scaleFactor, y: offsetsAndScaleFactor.scaleFactor)
        )
        .applying(
          CGAffineTransform(translationX: offsetsAndScaleFactor.xOffset, y: offsetsAndScaleFactor.yOffset)
        )

      if newRect.origin.x < 0 &&
          newRect.origin.x + newRect.size.width > edgeOffset {
        newRect.size.width = newRect.maxX - edgeOffset
        newRect.origin.x = edgeOffset
      }

      if newRect.origin.y < 0 &&
          newRect.origin.y + newRect.size.height > edgeOffset {
        newRect.size.height += newRect.maxY - edgeOffset
        newRect.origin.y = edgeOffset
      }

      if newRect.maxY > currentSize.height {
        newRect.size.height = currentSize.height - newRect.origin.y  - edgeOffset
      }

      if newRect.maxX > currentSize.width {
        newRect.size.width = currentSize.width - newRect.origin.x - edgeOffset
      }

      return newRect
    }

  private func drawDots(_ dots: [CGPoint]) {
    for dot in dots {
      let dotRect = CGRect(
        x: CGFloat(dot.x) - DefaultConstants.pointRadius / 2,
        y: CGFloat(dot.y) - DefaultConstants.pointRadius / 2,
        width: DefaultConstants.pointRadius,
        height: DefaultConstants.pointRadius)
      let path = UIBezierPath(ovalIn: dotRect)
      DefaultConstants.pointFillColor.setFill()
      DefaultConstants.pointColor.setStroke()
      path.stroke()
      path.fill()
    }
  }

  private func drawLines(_ lines: [Line]) {
    // Find the line connecting landmarks 13 and 14 (ring finger MCP and PIP)
    var ringFingerLine: Line? = nil
    for line in lines {
      // Check if this line connects landmarks 13 and 14
      if (line.from == handOverlays[0].dots[13] && line.to == handOverlays[0].dots[14]) || 
         (line.from == handOverlays[0].dots[14] && line.to == handOverlays[0].dots[13]) {
        ringFingerLine = line
      }
    }
    
    // Draw perpendicular line if we found the ring finger line
    if let ringLine = ringFingerLine {
      // Calculate 60% point between MCP and PIP
      let x1 = ringLine.from.x
      let y1 = ringLine.from.y
      let x2 = ringLine.to.x
      let y2 = ringLine.to.y
      
      let x60 = x1 + (x2 - x1) * 0.6
      let y60 = y1 + (y2 - y1) * 0.6
      
      // Calculate perpendicular direction
      let dx = x2 - x1
      let dy = y2 - y1
      let length = sqrt(dx * dx + dy * dy)
      
      // Normalize and rotate 90 degrees
      let perpX = -dy / length
      let perpY = dx / length
      
      // Calculate line angle in degrees
      let lineAngleRad = atan2(perpY, perpX)
      let lineAngleDeg = lineAngleRad * 180 / .pi
      
      // Calculate hand width using distance between index and pinky MCP joints
      let indexMCP = handOverlays[0].dots[5]  // Index finger MCP
      let pinkyMCP = handOverlays[0].dots[17] // Pinky finger MCP
      
      let indexX = indexMCP.x
      let indexY = indexMCP.y
      let pinkyX = pinkyMCP.x
      let pinkyY = pinkyMCP.y
      
      // Calculate hand width
      let handWidth = sqrt(
        (pinkyX - indexX) * (pinkyX - indexX) +
        (pinkyY - indexY) * (pinkyY - indexY)
      ) * 0.9
      
      // Draw perpendicular line in yellow
//      let perpLength = length * 0.2  // 20% of the original line length
//      let perpPath = UIBezierPath()
//      perpPath.move(to: CGPoint(x: x60 - perpX * perpLength, y: y60 - perpY * perpLength))
//      perpPath.addLine(to: CGPoint(x: x60 + perpX * perpLength, y: y60 + perpY * perpLength))
//      DefaultConstants.ringFingerLineColor.setStroke()
//      perpPath.lineWidth = 3.0
//      perpPath.stroke()
      
      // Update ring pose
        glView?.updatePose(x: Float(x60), y: Float(y60), z: -3.0, angleDeg: -Float(lineAngleDeg), width: Float(handWidth), height: 0.0)
    }
  }

  // MARK: Helper Functions
  static func offsetsAndScaleFactor(
    forImageOfSize imageSize: CGSize,
    tobeDrawnInViewOfSize viewSize: CGSize,
    withContentMode contentMode: UIView.ContentMode)
  -> (xOffset: CGFloat, yOffset: CGFloat, scaleFactor: Double) {

    let widthScale = viewSize.width / imageSize.width;
    let heightScale = viewSize.height / imageSize.height;

    var scaleFactor = 0.0

    switch contentMode {
    case .scaleAspectFill:
      scaleFactor = max(widthScale, heightScale)
    case .scaleAspectFit:
      scaleFactor = min(widthScale, heightScale)
    default:
      scaleFactor = 1.0
    }

    let scaledSize = CGSize(
      width: imageSize.width * scaleFactor,
      height: imageSize.height * scaleFactor)
    let xOffset = (viewSize.width - scaledSize.width) / 2
    let yOffset = (viewSize.height - scaledSize.height) / 2

    return (xOffset, yOffset, scaleFactor)
  }

  // Helper to get object overlays from detections.
  static func handOverlays(
    fromMultipleHandLandmarks landmarks: [[NormalizedLandmark]],
    inferredOnImageOfSize originalImageSize: CGSize,
    ovelayViewSize: CGSize,
    imageContentMode: UIView.ContentMode,
    andOrientation orientation: UIImage.Orientation) -> [HandOverlay] {

      var handOverlays: [HandOverlay] = []

      guard !landmarks.isEmpty else {
        return []
      }

      let offsetsAndScaleFactor = OverlayView.offsetsAndScaleFactor(
        forImageOfSize: originalImageSize,
        tobeDrawnInViewOfSize: ovelayViewSize,
        withContentMode: imageContentMode)

      for handLandmarks in landmarks {
        var transformedHandLandmarks: [CGPoint]!

        switch orientation {
        case .left:
          transformedHandLandmarks = handLandmarks.map({CGPoint(x: CGFloat($0.y), y: 1 - CGFloat($0.x))})
        case .right:
          transformedHandLandmarks = handLandmarks.map({CGPoint(x: 1 - CGFloat($0.y), y: CGFloat($0.x))})
        default:
          transformedHandLandmarks = handLandmarks.map({CGPoint(x: CGFloat($0.x), y: CGFloat($0.y))})
        }

        let dots: [CGPoint] = transformedHandLandmarks.map({CGPoint(x: CGFloat($0.x) * originalImageSize.width * offsetsAndScaleFactor.scaleFactor + offsetsAndScaleFactor.xOffset, y: CGFloat($0.y) * originalImageSize.height * offsetsAndScaleFactor.scaleFactor + offsetsAndScaleFactor.yOffset)})
        let lines: [Line] = HandLandmarker.handConnections
            .map({ connection in
              let start = dots[Int(connection.start)]
              let end = dots[Int(connection.end)]
              return Line(from: start,
                          to: end)
            })

        handOverlays.append(HandOverlay(dots: dots, lines: lines))
      }

      return handOverlays
    }
}
