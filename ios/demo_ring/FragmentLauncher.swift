import Foundation
import UIKit
import React

@objc(FragmentLauncher)
class FragmentLauncher: NSObject, RCTBridgeModule {
  // MARK: - RCTBridgeModule conformance
  static func moduleName() -> String! {
    return "FragmentLauncher"
  }
  
  static func requiresMainQueueSetup() -> Bool {
    return true
  }

  @objc
  func launchFragment() {
    DispatchQueue.main.async {
      if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
         let rootVC = windowScene.windows.first?.rootViewController {
        let dummyVC = CameraViewController()
        dummyVC.modalPresentationStyle = .fullScreen
        rootVC.present(dummyVC, animated: true, completion: nil)
      }
    }
  }
}

class SlideFromRightTransition: NSObject, UIViewControllerAnimatedTransitioning {
  let isPresenting: Bool
  init(isPresenting: Bool) {
    self.isPresenting = isPresenting
    super.init()
  }
  func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
    return 0.3
  }
  func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
    guard let toView = transitionContext.view(forKey: .to),
          let fromView = transitionContext.view(forKey: .from) else {
      transitionContext.completeTransition(false)
      return
    }
    let container = transitionContext.containerView
    let width = container.frame.width
    if isPresenting {
      toView.transform = CGAffineTransform(translationX: width, y: 0)
      container.addSubview(toView)
      UIView.animate(withDuration: transitionDuration(using: transitionContext), delay: 0, options: [.curveEaseOut], animations: {
        toView.transform = .identity
      }, completion: { finished in
        transitionContext.completeTransition(finished)
      })
    } else {
      UIView.animate(withDuration: transitionDuration(using: transitionContext), delay: 0, options: [.curveEaseIn], animations: {
        fromView.transform = CGAffineTransform(translationX: width, y: 0)
      }, completion: { finished in
        fromView.removeFromSuperview()
        transitionContext.completeTransition(finished)
      })
    }
  }
}
