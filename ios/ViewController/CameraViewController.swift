//
//  CameraViewController.swift
//  demo_ring
//
//  Created by Macos on 29/5/25.
//

import AVFoundation
import MediaPipeTasksVision
import UIKit

/**
 * The view controller is responsible for performing detection on incoming frames from the live camera and presenting the frames with the
 * landmark of the landmarked hands to the user.
 */
class CameraViewController: UIViewController {
  private struct Constants {
    static let edgeOffset: CGFloat = 2.0
    static let dismissThreshold: CGFloat = 100.0 // Distance needed to trigger dismiss
  }
  
  weak var inferenceResultDeliveryDelegate: InferenceResultDeliveryDelegate?
  weak var interfaceUpdatesDelegate: InterfaceUpdatesDelegate?
  
  // Create views programmatically
  private lazy var previewView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()
  
  // Add gesture recognizer
  private lazy var panGestureRecognizer: UIPanGestureRecognizer = {
    let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
    gesture.delegate = self
    return gesture
  }()
  
  private var initialTouchPoint: CGPoint = .zero
  
  private lazy var cameraUnavailableLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = "Camera Unavailable"
    label.textColor = .white
    label.textAlignment = .center
    label.isHidden = true
    return label
  }()
  
  private lazy var resumeButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle("Resume", for: .normal)
    button.addTarget(self, action: #selector(onClickResume), for: .touchUpInside)
    button.isHidden = true
    return button
  }()
  
  private lazy var overlayView: OverlayView = {
    let view = OverlayView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()
  
  private var isSessionRunning = false
  private var isObserving = false
  private let backgroundQueue = DispatchQueue(label: "com.demo.bdtest.cameraController.backgroundQueue")
  
  // MARK: Controllers that manage functionality
  // Handles all the camera related functionality
  private var cameraFeedService: CameraFeedService?
  
  private let handLandmarkerServiceQueue = DispatchQueue(
    label: "com.demo.bdtest.cameraController.handLandmarkerServiceQueue",
    attributes: .concurrent)
  
  // Queuing reads and writes to handLandmarkerService using the Apple recommended way
  // as they can be read and written from multiple threads and can result in race conditions.
  private var _handLandmarkerService: HandLandmarkerService?
  private var handLandmarkerService: HandLandmarkerService? {
    get {
      handLandmarkerServiceQueue.sync {
        return self._handLandmarkerService
      }
    }
    set {
      handLandmarkerServiceQueue.async(flags: .barrier) {
        self._handLandmarkerService = newValue
      }
    }
  }

#if !targetEnvironment(simulator)
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    initializeHandLandmarkerServiceOnSessionResumption()
    cameraFeedService?.startLiveCameraSession {[weak self] cameraConfiguration in
      DispatchQueue.main.async {
        switch cameraConfiguration {
        case .failed:
          self?.presentVideoConfigurationErrorAlert()
        case .permissionDenied:
          self?.presentCameraPermissionsDeniedAlert()
        default:
          break
        }
      }
    }
  }
  
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    cameraFeedService?.stopSession()
    clearhandLandmarkerServiceOnSessionInterruption()
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    setupViews()
    setupGestures()
    cameraFeedService = CameraFeedService(previewView: previewView)
    cameraFeedService?.delegate = self
  }
  
  private func setupViews() {
    view.addSubview(previewView)
    view.addSubview(overlayView)
    view.addSubview(cameraUnavailableLabel)
    view.addSubview(resumeButton)
    
    NSLayoutConstraint.activate([
      // Preview view fills the screen
      previewView.topAnchor.constraint(equalTo: view.topAnchor),
      previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      
      // Overlay view fills the screen
      overlayView.topAnchor.constraint(equalTo: view.topAnchor),
      overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      
      // Camera unavailable label
      cameraUnavailableLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      cameraUnavailableLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      
      // Resume button
      resumeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      resumeButton.centerYAnchor.constraint(equalTo: view.centerYAnchor)
    ])
  }
  
  private func setupGestures() {
    view.addGestureRecognizer(panGestureRecognizer)
  }
  
  @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
    let touchPoint = gesture.location(in: view.window)
    
    switch gesture.state {
    case .began:
      initialTouchPoint = touchPoint
    case .changed:
      let horizontalDelta = touchPoint.x - initialTouchPoint.x
      // Only allow right swipe (positive delta)
      if horizontalDelta > 0 {
        view.transform = CGAffineTransform(translationX: horizontalDelta, y: 0)
      }
    case .ended, .cancelled:
      let horizontalDelta = touchPoint.x - initialTouchPoint.x
      let velocity = gesture.velocity(in: view).x
      
      // Dismiss if dragged more than threshold or if velocity is high enough
      if horizontalDelta > Constants.dismissThreshold || velocity > 500 {
        UIView.animate(withDuration: 0.3, animations: {
          self.view.transform = CGAffineTransform(translationX: self.view.bounds.width, y: 0)
        }) { _ in
          self.dismiss(animated: false)
        }
      } else {
        // Reset position if not dismissed
        UIView.animate(withDuration: 0.3) {
          self.view.transform = .identity
        }
      }
    default:
      break
    }
  }
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    cameraFeedService?.updateVideoPreviewLayer(toFrame: previewView.bounds)
  }
  
  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    cameraFeedService?.updateVideoPreviewLayer(toFrame: previewView.bounds)
  }
#endif
  
  // Remove @IBAction since we're not using storyboard
  @objc private func onClickResume(_ sender: Any) {
    cameraFeedService?.resumeInterruptedSession {[weak self] isSessionRunning in
      if isSessionRunning {
        self?.resumeButton.isHidden = true
        self?.cameraUnavailableLabel.isHidden = true
        self?.initializeHandLandmarkerServiceOnSessionResumption()
      }
    }
  }
  
  private func presentCameraPermissionsDeniedAlert() {
    let alertController = UIAlertController(
      title: "Camera Permissions Denied",
      message:
        "Camera permissions have been denied for this app. You can change this by going to Settings",
      preferredStyle: .alert)
    
    let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
    let settingsAction = UIAlertAction(title: "Settings", style: .default) { (action) in
      UIApplication.shared.open(
        URL(string: UIApplication.openSettingsURLString)!, options: [:], completionHandler: nil)
    }
    alertController.addAction(cancelAction)
    alertController.addAction(settingsAction)
    
    present(alertController, animated: true, completion: nil)
  }
  
  private func presentVideoConfigurationErrorAlert() {
    let alert = UIAlertController(
      title: "Camera Configuration Failed",
      message: "There was an error while configuring camera.",
      preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
    
    self.present(alert, animated: true)
  }
  
  private func initializeHandLandmarkerServiceOnSessionResumption() {
    clearAndInitializeHandLandmarkerService()
    startObserveConfigChanges()
  }
  
  @objc private func clearAndInitializeHandLandmarkerService() {
    handLandmarkerService = nil
    handLandmarkerService = HandLandmarkerService
      .liveStreamHandLandmarkerService(
        modelPath: InferenceConfigurationManager.sharedInstance.modelPath,
        numHands: InferenceConfigurationManager.sharedInstance.numHands,
        minHandDetectionConfidence: InferenceConfigurationManager.sharedInstance.minHandDetectionConfidence,
        minHandPresenceConfidence: InferenceConfigurationManager.sharedInstance.minHandPresenceConfidence,
        minTrackingConfidence: InferenceConfigurationManager.sharedInstance.minTrackingConfidence,
        liveStreamDelegate: self,
        delegate: InferenceConfigurationManager.sharedInstance.delegate)
  }
  
  private func clearhandLandmarkerServiceOnSessionInterruption() {
    stopObserveConfigChanges()
    handLandmarkerService = nil
  }
  
  private func startObserveConfigChanges() {
    NotificationCenter.default
      .addObserver(self,
                   selector: #selector(clearAndInitializeHandLandmarkerService),
                   name: InferenceConfigurationManager.notificationName,
                   object: nil)
    isObserving = true
  }
  
  private func stopObserveConfigChanges() {
    if isObserving {
      NotificationCenter.default
        .removeObserver(self,
                        name:InferenceConfigurationManager.notificationName,
                        object: nil)
    }
    isObserving = false
  }
}

extension CameraViewController: CameraFeedServiceDelegate {
  
  func didOutput(sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation) {
    let currentTimeMs = Date().timeIntervalSince1970 * 1000
    // Pass the pixel buffer to mediapipe
    backgroundQueue.async { [weak self] in
      self?.handLandmarkerService?.detectAsync(
        sampleBuffer: sampleBuffer,
        orientation: orientation,
        timeStamps: Int(currentTimeMs))
    }
  }
  
  // MARK: Session Handling Alerts
  func sessionWasInterrupted(canResumeManually resumeManually: Bool) {
    // Updates the UI when session is interupted.
    if resumeManually {
      resumeButton.isHidden = false
    } else {
      cameraUnavailableLabel.isHidden = false
    }
    clearhandLandmarkerServiceOnSessionInterruption()
  }
  
  func sessionInterruptionEnded() {
    // Updates UI once session interruption has ended.
    cameraUnavailableLabel.isHidden = true
    resumeButton.isHidden = true
    initializeHandLandmarkerServiceOnSessionResumption()
  }
  
  func didEncounterSessionRuntimeError() {
    // Handles session run time error by updating the UI and providing a button if session can be
    // manually resumed.
    resumeButton.isHidden = false
    clearhandLandmarkerServiceOnSessionInterruption()
  }
}

// MARK: HandLandmarkerServiceLiveStreamDelegate
extension CameraViewController: HandLandmarkerServiceLiveStreamDelegate {

  func handLandmarkerService(
    _ handLandmarkerService: HandLandmarkerService,
    didFinishDetection result: ResultBundle?,
    error: Error?) {
      DispatchQueue.main.async { [weak self] in
        guard let weakSelf = self else { return }
        weakSelf.inferenceResultDeliveryDelegate?.didPerformInference(result: result)
        guard let handLandmarkerResult = result?.handLandmarkerResults.first as? HandLandmarkerResult else { return }
        let imageSize = weakSelf.cameraFeedService?.videoResolution ?? CGSize(width: 0, height: 0)
        let handOverlays = OverlayView.handOverlays(
          fromMultipleHandLandmarks: handLandmarkerResult.landmarks,
          inferredOnImageOfSize: imageSize,
          ovelayViewSize: weakSelf.overlayView.bounds.size,
          imageContentMode: weakSelf.overlayView.imageContentMode,
          andOrientation: UIImage.Orientation.from(
            deviceOrientation: UIDevice.current.orientation))
        weakSelf.overlayView.draw(handOverlays: handOverlays,
                         inBoundsOfContentImageOfSize: imageSize,
                         imageContentMode: weakSelf.cameraFeedService?.videoGravity.contentMode ?? .scaleAspectFill)
      }
    }
}

// MARK: - AVLayerVideoGravity Extension
extension AVLayerVideoGravity {
  var contentMode: UIView.ContentMode {
    switch self {
    case .resizeAspectFill:
      return .scaleAspectFill
    case .resizeAspect:
      return .scaleAspectFit
    case .resize:
      return .scaleToFill
    default:
      return .scaleAspectFill
    }
  }
}

// MARK: - UIGestureRecognizerDelegate
extension CameraViewController: UIGestureRecognizerDelegate {
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    // Only allow gesture from left edge
    let touchPoint = touch.location(in: view)
    return touchPoint.x <= 50 // 50 points from left edge
  }
}

