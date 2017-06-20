//
//  ViewController.swift
//  crappyTTT
//
//  Created by Bjarne Møller Lundgren on 19/06/2017.
//  Copyright © 2017 Bjarne Møller Lundgren. All rights reserved.
//

import UIKit
import SceneKit

private let groundCategoryBitMask:Int = 1

class ViewController: UIViewController {

    @IBOutlet weak var gameStateLabel: UILabel!
    @IBOutlet weak var sceneView: SCNView!
    let board = Board()
    var gameState = GameState(currentPlayer: GameState.DefaultPlayer,
                              mode: GameState.DefaultMode,
                              board: GameState.EmptyBoard) {
        didSet {
            var s = gameState.currentPlayer.rawValue + " "
            switch gameState.mode {
            case .put: s += "put"
            case .move: s += "move"
            }
            gameStateLabel.text = s
            
            if let winner = gameState.currentWinner {
                let alert = UIAlertController(title: "Game Over", message: "\(winner.rawValue) wins!!!!", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { action in
                    self.reset()
                }))
                present(alert, animated: true, completion: nil)
            }
        }
    }
    var figures:[String:SCNNode] = [:]
    var draggingFrom:GamePosition? = nil
    var draggingFromPosition:SCNVector3? = nil
    var ground:SCNNode!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.scene = SCNScene()
        
        // detect taps
        let tap = UITapGestureRecognizer()
        tap.addTarget(self, action: #selector(didTap))
        sceneView.addGestureRecognizer(tap)
        
        let pan = UIPanGestureRecognizer()
        pan.addTarget(self, action: #selector(didPan))
        sceneView.addGestureRecognizer(pan)
     
        let groundGeometry = SCNFloor()
        groundGeometry.reflectivity = 0
        let groundMaterial = SCNMaterial()
        groundMaterial.diffuse.contents = UIColor.lightGray
        groundGeometry.materials = [groundMaterial]
        ground = SCNNode(geometry: groundGeometry)
        ground.categoryBitMask = groundCategoryBitMask
        
        let cam = SCNCamera()
        cam.zFar = 10000
        let camera = SCNNode()
        camera.camera = cam
        camera.position = SCNVector3(-18, 25, 18)
        let constraint = SCNLookAtConstraint(target: ground)
        constraint.isGimbalLockEnabled = true
        camera.constraints = [constraint]
        
        let ambientLight = SCNLight()
        ambientLight.color = UIColor.darkGray
        ambientLight.type = .ambient
        camera.light = ambientLight
        
        let spotLight = SCNLight()
        spotLight.type = .spot
        spotLight.castsShadow = true
        spotLight.spotInnerAngle = 70
        spotLight.spotOuterAngle = 90
        spotLight.zFar = 500
        let light = SCNNode()
        light.light = spotLight
        light.position = SCNVector3(0, 25, 25)
        light.constraints = [constraint]
        
        sceneView.scene?.rootNode.addChildNode(camera)
        sceneView.scene?.rootNode.addChildNode(ground)
        sceneView.scene?.rootNode.addChildNode(light)
        sceneView.scene?.rootNode.addChildNode(board.node)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sceneView.frame = view.bounds
        sceneView.setNeedsDisplay()
    }
    
    private func reset() {
        gameState = GameState(currentPlayer: GameState.DefaultPlayer,
                              mode: GameState.DefaultMode,
                              board: GameState.EmptyBoard)
        
        for (_, node) in figures {
            node.removeFromParentNode()
        }
        figures.removeAll()
    }
    
    @IBAction func didTapStartOver(_ sender: Any) {
        reset()
    }
    
    private func squareFrom(location:CGPoint) -> ((Int, Int), SCNNode)? {
        let hitResults = sceneView.hitTest(location, options: [SCNHitTestOption.firstFoundOnly: false,
                                                               SCNHitTestOption.rootNode:       board.node])
        
        for result in hitResults {
            if let square = board.nodeToSquare[result.node] {
                return (square, result.node)
            }
        }
        
        return nil
    }
    
    private func groundPositionFrom(location:CGPoint) -> SCNVector3? {
        // just hit test the ground, nothing else :)
        let hitResults = sceneView.hitTest(location, options: [SCNHitTestOption.firstFoundOnly:     true,
                                                               SCNHitTestOption.rootNode:           ground,
                                                               SCNHitTestOption.ignoreChildNodes:   true])
        
        guard hitResults.count > 0,
              hitResults[0].node == ground else { return nil }
        
        return hitResults[0].localCoordinates
    }
    
    private func revertDrag() {
        if let draggingFrom = draggingFrom {
            
            let action = SCNAction.move(to: draggingFromPosition!, duration: 0.3)
            figures["\(draggingFrom.x)x\(draggingFrom.y)"]?.runAction(action)
            
            self.draggingFrom = nil
            self.draggingFromPosition = nil
        }
    }
    
    @objc func didPan(_ sender:UIPanGestureRecognizer) {
        guard case .move = gameState.mode else { return }
        
        let location = sender.location(in: sceneView)
        
        switch sender.state {
        case .began:
            print("begin \(location)")
            guard let square = squareFrom(location: location) else { return }
            draggingFrom = (x: square.0.0, y: square.0.1)
            draggingFromPosition = square.1.position
            
        case .cancelled:
            print("cancelled \(location)")
            revertDrag()
            
        case .changed:
            print("changed \(location)")
            guard let draggingFrom = draggingFrom,
                  let groundPosition = groundPositionFrom(location: location) else { return }
            
            let action = SCNAction.move(to: SCNVector3(groundPosition.x, groundPosition.y + Float(Dimensions.DRAG_LIFTOFF), groundPosition.z),
                                        duration: 0.1)
            figures["\(draggingFrom.x)x\(draggingFrom.y)"]?.runAction(action)
            
        case .ended:
            print("ended \(location)")
            let figure = Figure.figure(for: gameState.currentPlayer)
            
            guard let draggingFrom = draggingFrom,
                  let square = squareFrom(location: location),
                  square.0.0 != draggingFrom.x || square.0.1 != draggingFrom.y,
                  let newGameState = gameState.move(from: draggingFrom, to: (x: square.0.0, y: square.0.1)) else {
                    revertDrag()
                    return
            }
            
            gameState = newGameState
            
            // remove node!
            figures["\(draggingFrom.x)x\(draggingFrom.y)"]?.removeFromParentNode()
            figures["\(draggingFrom.x)x\(draggingFrom.y)"] = nil
            self.draggingFrom = nil
            
            // copy pasted insert thingie
            figure.position = square.1.position
            
            sceneView.scene?.rootNode.addChildNode(figure)
            figures["\(square.0.0)x\(square.0.1)"] = figure
            
        
        case .failed:
            print("failed \(location)")
            revertDrag()
          
        default: break
        }
    }

    @objc func didTap(_ sender:UITapGestureRecognizer) {
        guard case .put = gameState.mode else { return }
        
        let location = sender.location(in: sceneView)
        
        let hitResults = sceneView.hitTest(location, options: nil)
        
        for result in hitResults {
            // need to get it now, for the currentPlayer
            let figure = Figure.figure(for: gameState.currentPlayer)
            
            if let square = board.nodeToSquare[result.node],
               let newGameState = gameState.put(at: (x: square.0, y: square.1)) {
                gameState = newGameState
                
                figure.position = result.node.position
                print(figure.position)
 
                sceneView.scene?.rootNode.addChildNode(figure)
                figures["\(square.0)x\(square.1)"] = figure
                
                
                break
            }
        }
    }
}

