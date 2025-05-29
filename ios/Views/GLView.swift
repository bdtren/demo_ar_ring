import UIKit
import SceneKit

public class GLView: UIView {
    private var sceneView: SCNView!
    private var scene: SCNScene!
    private var ringNode: SCNNode?
    
    public override class var layerClass: AnyClass {
        return CALayer.self
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupScene()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupScene()
    }
    
    private func setupScene() {
        // Create scene view as a subview
        sceneView = SCNView(frame: bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.backgroundColor = .clear
        sceneView.autoenablesDefaultLighting = true
        sceneView.allowsCameraControl = false
        addSubview(sceneView)
        
        // Create scene
        scene = SCNScene()
        sceneView.scene = scene
        
        // Setup camera
        let camera = SCNCamera()
        camera.zNear = 0.1
        camera.zFar = 100
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 2)
        scene.rootNode.addChildNode(cameraNode)
        
        // Load ring model
        loadRingModel()
    }
    
    private func loadRingModel() {
        print("Attempting to load ring_3d.obj...")
        print("Bundle paths: \(Bundle.main.paths(forResourcesOfType: "obj", inDirectory: nil))")
        
        guard let path = Bundle.main.path(forResource: "ring_3d", ofType: "obj") else {
            print("ERROR: Could not find ring_3d.obj file")
            return
        }
        
        print("Found ring_3d.obj at path: \(path)")
        
        do {
            // Load the model
            let ringScene = try SCNScene(url: URL(fileURLWithPath: path), options: nil)
            ringNode = ringScene.rootNode.childNodes.first
            
            if let ringNode = ringNode {
                // Scale the ring
                let scale: Float = 0.01  // Much smaller scale
                ringNode.scale = SCNVector3(scale, scale, scale)
                
                // Position the ring
                ringNode.position = SCNVector3(0, 0, 0)
                
                // Keep original material
                // Add to scene
                scene.rootNode.addChildNode(ringNode)
                
                print("Ring model loaded successfully")
            }
        } catch {
            print("ERROR loading ring_3d.obj file: \(error)")
        }
    }
    
    public func updatePose(x: Float, y: Float, z: Float, angleDeg: Float, width: Float, height: Float) {
        guard let ringNode = ringNode else { return }
        
        // Convert screen coordinates to scene coordinates
        let screenX = CGFloat(x) / UIScreen.main.bounds.width - 0.5
        let screenY = 1.15 - (CGFloat(y) / UIScreen.main.bounds.height) * 2.3
        
        // Update position
        ringNode.position = SCNVector3(screenX, screenY, 0)
        
        // Update rotation
        ringNode.eulerAngles.z = Float(angleDeg) * .pi / 180
        
        // Update scale based on width
        let scale = width / 15000  // Much smaller scale factor
        ringNode.scale = SCNVector3(scale, scale, scale)
    }
    
    deinit {
        sceneView = nil
        scene = nil
        ringNode = nil
    }
} 
