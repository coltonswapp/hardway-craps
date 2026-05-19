//
//  FlipDiceScene.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit
import SceneKit

class FlipDiceScene: NSObject, SCNSceneRendererDelegate {

    let scene = SCNScene()
    private var cameraNode: SCNNode!
    private var diceNode1: SCNNode!
    private var diceNode2: SCNNode!
    
    var diceFaceColor: UIColor = HardwayColors.surfaceDropZone

    override init() {
        super.init()
        setupScene()
    }

    private func setupScene() {
        // Clear background (no background color)
        scene.background.contents = UIColor.clear

        // Create two dice - smaller for compact view
        let diceSize: CGFloat = 2.8

        // First die - positioned on the left (negative X)
        let diceGeometry1 = SCNBox(width: diceSize, height: diceSize, length: diceSize, chamferRadius: 0.25)
        diceGeometry1.materials = createDiceMaterials(value: 1)

        diceNode1 = SCNNode(geometry: diceGeometry1)
        diceNode1.position = SCNVector3(-2.0, 0, 0)  // Left side
        diceNode1.eulerAngles = SCNVector3Zero
        scene.rootNode.addChildNode(diceNode1)

        // Second die - positioned on the right (positive X)
        let diceGeometry2 = SCNBox(width: diceSize, height: diceSize, length: diceSize, chamferRadius: 0.15)
        diceGeometry2.materials = createDiceMaterials(value: 1)

        diceNode2 = SCNNode(geometry: diceGeometry2)
        diceNode2.position = SCNVector3(2.0, 0, 0)  // Right side
        diceNode2.eulerAngles = SCNVector3Zero
        scene.rootNode.addChildNode(diceNode2)

        // Camera - orthographic top-down view (no perspective, only see top faces)
        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.camera?.orthographicScale = 2.5  // Adjusted to fit horizontal dice layout
        cameraNode.position = SCNVector3(0, 8, 0)  // Directly above
        cameraNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)  // Looking straight down
        scene.rootNode.addChildNode(cameraNode)

        // Simple ambient lighting only (no shadows)
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = UIColor.white.withAlphaComponent(0.6)
        scene.rootNode.addChildNode(ambientLight)
    }

    private func createDiceMaterials(value: Int) -> [SCNMaterial] {
        // SCNBox face order is [front, right, back, left, top, bottom].
        // Set top directly to rolled value so the visual always matches game logic.
        let topFace = value
        let bottomFace = 7 - value
        let sideFaces = [1, 2, 3, 4, 5, 6]
            .filter { $0 != topFace && $0 != bottomFace }
            .shuffled()
        let faceValues = [sideFaces[0], sideFaces[1], sideFaces[2], sideFaces[3], topFace, bottomFace]

        return faceValues.map { faceValue in
            let material = SCNMaterial()
            material.diffuse.contents = createDiceFaceImage(number: faceValue)
            material.locksAmbientWithDiffuse = true
            return material
        }
    }

    private func createDiceFaceImage(number: Int) -> UIImage {
        let size = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            // Dark gray background
            diceFaceColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // Draw black dots
            UIColor.black.setFill()
            let dotRadius: CGFloat = 15
            let positions = getDotPositions(for: number, in: size, dotRadius: dotRadius)

            for position in positions {
                let rect = CGRect(x: position.x - dotRadius,
                                y: position.y - dotRadius,
                                width: dotRadius * 2,
                                height: dotRadius * 2)
                context.cgContext.fillEllipse(in: rect)
            }
        }
    }

    private func getDotPositions(for number: Int, in size: CGSize, dotRadius: CGFloat) -> [CGPoint] {
        let padding: CGFloat = 60
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let topLeft = CGPoint(x: padding, y: padding)
        let topRight = CGPoint(x: size.width - padding, y: padding)
        let bottomLeft = CGPoint(x: padding, y: size.height - padding)
        let bottomRight = CGPoint(x: size.width - padding, y: size.height - padding)
        let middleLeft = CGPoint(x: padding, y: center.y)
        let middleRight = CGPoint(x: size.width - padding, y: center.y)

        switch number {
        case 1:
            return [center]
        case 2:
            return [topLeft, bottomRight]
        case 3:
            return [topLeft, center, bottomRight]
        case 4:
            return [topLeft, topRight, bottomLeft, bottomRight]
        case 5:
            return [topLeft, topRight, center, bottomLeft, bottomRight]
        case 6:
            return [topLeft, topRight, middleLeft, middleRight, bottomLeft, bottomRight]
        default:
            return []
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        // No per-frame updates needed
    }

    func roll(excludingTotals: Set<Int> = [], completion: @escaping (Int, Int) -> Void) {
        let value1: Int
        let value2: Int
        if excludingTotals.isEmpty {
            value1 = Int.random(in: 1...6)
            value2 = Int.random(in: 1...6)
        } else {
            var v1 = 0
            var v2 = 0
            repeat {
                v1 = Int.random(in: 1...6)
                v2 = Int.random(in: 1...6)
            } while excludingTotals.contains(v1 + v2)
            value1 = v1
            value2 = v2
        }

        // Animate die 1
        animateDie(diceNode1, toValue: value1)

        // Animate die 2
        animateDie(diceNode2, toValue: value2)

        GameAnimationTiming.after(GameAnimationTiming.Dice.completionDelay) {
            completion(value1, value2)
        }
    }
    
    func rollFixed(die1: Int, die2: Int, completion: @escaping (Int, Int) -> Void) {
        animateDie(diceNode1, toValue: die1)
        animateDie(diceNode2, toValue: die2)

        GameAnimationTiming.after(GameAnimationTiming.Dice.completionDelay) {
            completion(die1, die2)
        }
    }

    private func animateDie(_ dieNode: SCNNode, toValue: Int) {
        // Update materials so the top face is the requested value
        if let geometry = dieNode.geometry as? SCNBox {
            geometry.materials = createDiceMaterials(value: toValue)
        }

        // Step 1: Tumble animation with random rotations (0.4s)
        let tumbleX = CGFloat.random(in: 2...3) * .pi
        let tumbleY = CGFloat.random(in: 2...3) * .pi
        let tumbleZ = CGFloat.random(in: 2...3) * .pi

        let tumble = SCNAction.rotateBy(x: tumbleX, y: tumbleY, z: tumbleZ, duration: GameAnimationTiming.Dice.tumbleDuration)
        tumble.timingMode = .easeOut

        // Step 2: Snap back to fixed orientation
        let settle = SCNAction.rotateTo(
            x: 0,
            y: 0,
            z: 0,
            duration: GameAnimationTiming.Dice.settleDuration,
            usesShortestUnitArc: true
        )
        settle.timingMode = .easeInEaseOut

        // Run sequence: tumble then settle flat
        let sequence = SCNAction.sequence([tumble, settle])
        dieNode.runAction(sequence)
    }
}
