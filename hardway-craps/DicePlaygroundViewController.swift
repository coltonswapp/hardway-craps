//
//  DicePlaygroundViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 3/16/26.
//

import UIKit
import SceneKit

// MARK: - Dice Roll Strategy Protocol

protocol DiceRollStrategy {
    var name: String { get }
    func animateDie(_ dieNode: SCNNode, toValue: Int, createMaterials: (Int) -> [SCNMaterial])
    var totalDuration: TimeInterval { get }
}

// MARK: - Strategy 1: Current (Tumble + Settle)

class TumbleSettleStrategy: DiceRollStrategy {
    let name = "Tumble + Settle"
    let totalDuration: TimeInterval = 0.6

    func animateDie(_ dieNode: SCNNode, toValue: Int, createMaterials: (Int) -> [SCNMaterial]) {
        if let geometry = dieNode.geometry as? SCNBox {
            geometry.materials = createMaterials(toValue)
        }

        let tumbleX = CGFloat.random(in: 2...3) * .pi
        let tumbleY = CGFloat.random(in: 2...3) * .pi
        let tumbleZ = CGFloat.random(in: 2...3) * .pi

        let tumble = SCNAction.rotateBy(x: tumbleX, y: tumbleY, z: tumbleZ, duration: 0.4)
        tumble.timingMode = .easeOut

        let settle = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.2, usesShortestUnitArc: true)
        settle.timingMode = .easeInEaseOut

        dieNode.runAction(.sequence([tumble, settle]))
    }
}

// MARK: - Strategy 2: Decoy Tumble (random face during spin, swap before settle)

class DecoyTumbleStrategy: DiceRollStrategy {
    let name = "Decoy Tumble"
    let totalDuration: TimeInterval = 0.6

    func animateDie(_ dieNode: SCNNode, toValue: Int, createMaterials: (Int) -> [SCNMaterial]) {
        // Show a random decoy face during the tumble
        if let geometry = dieNode.geometry as? SCNBox {
            let decoyValue = (1...6).filter { $0 != toValue }.randomElement() ?? 1
            geometry.materials = createMaterials(decoyValue)
        }

        let tumbleX = CGFloat.random(in: 2...3) * .pi
        let tumbleY = CGFloat.random(in: 2...3) * .pi
        let tumbleZ = CGFloat.random(in: 2...3) * .pi

        let tumble = SCNAction.rotateBy(x: tumbleX, y: tumbleY, z: tumbleZ, duration: 0.4)
        tumble.timingMode = .easeOut

        // Swap to the real value just before settling
        let materials = createMaterials(toValue)
        let applyFinal = SCNAction.run { node in
            guard let geometry = node.geometry as? SCNBox else { return }
            geometry.materials = materials
        }

        let settle = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.2, usesShortestUnitArc: true)
        settle.timingMode = .easeInEaseOut

        dieNode.runAction(.sequence([tumble, applyFinal, settle]))
    }
}

// MARK: - Strategy 3: Rapid Shuffle (cycle through faces during spin)

class RapidShuffleStrategy: DiceRollStrategy {
    let name = "Rapid Shuffle"
    let totalDuration: TimeInterval = 0.7

    func animateDie(_ dieNode: SCNNode, toValue: Int, createMaterials: (Int) -> [SCNMaterial]) {
        // Pre-generate material sets for cycling
        let shuffleCount = 6
        var shuffleActions: [SCNAction] = []

        for i in 0..<shuffleCount {
            let faceValue: Int
            if i == shuffleCount - 1 {
                faceValue = toValue
            } else {
                faceValue = Int.random(in: 1...6)
            }
            let materials = createMaterials(faceValue)

            let apply = SCNAction.run { node in
                guard let geometry = node.geometry as? SCNBox else { return }
                geometry.materials = materials
            }

            // Each shuffle step: rotate a bit + swap face
            let stepDuration = 0.07
            let rotateStep = SCNAction.rotateBy(
                x: CGFloat.random(in: 0.8...1.5) * .pi,
                y: CGFloat.random(in: 0.8...1.5) * .pi,
                z: CGFloat.random(in: 0.8...1.5) * .pi,
                duration: stepDuration
            )
            rotateStep.timingMode = i < shuffleCount / 2 ? .easeIn : .easeOut

            shuffleActions.append(SCNAction.group([apply, rotateStep]))
        }

        // Final settle to flat
        let settle = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.25, usesShortestUnitArc: true)
        settle.timingMode = .easeInEaseOut
        shuffleActions.append(settle)

        dieNode.runAction(.sequence(shuffleActions))
    }
}

// MARK: - Strategy 4: Bounce (tumble with a bounce before settling)

class BounceStrategy: DiceRollStrategy {
    let name = "Bounce"
    let totalDuration: TimeInterval = 0.8

    func animateDie(_ dieNode: SCNNode, toValue: Int, createMaterials: (Int) -> [SCNMaterial]) {
        // Decoy during tumble
        if let geometry = dieNode.geometry as? SCNBox {
            let decoyValue = (1...6).filter { $0 != toValue }.randomElement() ?? 1
            geometry.materials = createMaterials(decoyValue)
        }

        let startPos = dieNode.position

        // Phase 1: Tumble + rise up
        let tumbleX = CGFloat.random(in: 2...4) * .pi
        let tumbleY = CGFloat.random(in: 2...4) * .pi
        let tumbleZ = CGFloat.random(in: 2...4) * .pi
        let tumble = SCNAction.rotateBy(x: tumbleX, y: tumbleY, z: tumbleZ, duration: 0.3)
        tumble.timingMode = .easeOut

        let rise = SCNAction.moveBy(x: 0, y: 1.5, z: 0, duration: 0.3)
        rise.timingMode = .easeOut
        let phase1 = SCNAction.group([tumble, rise])

        // Phase 2: Drop + swap to final value
        let materials = createMaterials(toValue)
        let applyFinal = SCNAction.run { node in
            guard let geometry = node.geometry as? SCNBox else { return }
            geometry.materials = materials
        }

        let drop = SCNAction.move(to: startPos, duration: 0.15)
        drop.timingMode = .easeIn

        // Phase 3: Small bounce
        let bounceUp = SCNAction.moveBy(x: 0, y: 0.4, z: 0, duration: 0.1)
        bounceUp.timingMode = .easeOut
        let bounceDown = SCNAction.move(to: startPos, duration: 0.1)
        bounceDown.timingMode = .easeIn

        // Phase 4: Settle flat
        let settle = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.15, usesShortestUnitArc: true)
        settle.timingMode = .easeInEaseOut

        dieNode.runAction(.sequence([phase1, applyFinal, drop, bounceUp, bounceDown, settle]))
    }
}

// MARK: - Playground Scene (reusable dice scene for each strategy)

class PlaygroundDiceScene: NSObject, SCNSceneRendererDelegate {

    let scene = SCNScene()
    private(set) var diceNode1: SCNNode!
    private(set) var diceNode2: SCNNode!
    private var cameraNode: SCNNode!

    override init() {
        super.init()
        setupScene()
    }

    private func setupScene() {
        scene.background.contents = UIColor.clear

        let diceSize: CGFloat = 2.8

        let diceGeometry1 = SCNBox(width: diceSize, height: diceSize, length: diceSize, chamferRadius: 0.25)
        diceGeometry1.materials = createDiceMaterials(value: 1)
        diceNode1 = SCNNode(geometry: diceGeometry1)
        diceNode1.position = SCNVector3(-2.0, 0, 0)
        scene.rootNode.addChildNode(diceNode1)

        let diceGeometry2 = SCNBox(width: diceSize, height: diceSize, length: diceSize, chamferRadius: 0.15)
        diceGeometry2.materials = createDiceMaterials(value: 1)
        diceNode2 = SCNNode(geometry: diceGeometry2)
        diceNode2.position = SCNVector3(2.0, 0, 0)
        scene.rootNode.addChildNode(diceNode2)

        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = true
        cameraNode.camera?.orthographicScale = 7.0
        cameraNode.position = SCNVector3(0, 8, 0)
        cameraNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = UIColor.white.withAlphaComponent(0.6)
        scene.rootNode.addChildNode(ambientLight)
    }

    func createDiceMaterials(value: Int) -> [SCNMaterial] {
        // SCNBox face order: [right(+X), left(-X), top(+Y), bottom(-Y), front(+Z), back(-Z)]
        // Index 2 (top/+Y) is visible to camera after settling. Opposite faces sum to 7.
        let topFace = value
        let bottomFace = 7 - value
        var sideFaces = [1, 2, 3, 4, 5, 6].filter { $0 != topFace && $0 != bottomFace }.shuffled()
        let faceValues = [sideFaces[0], sideFaces[1], topFace, bottomFace, sideFaces[2], sideFaces[3]]

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
            HardwayColors.surfaceDropZone.setFill()
            context.fill(CGRect(origin: .zero, size: size))

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
        case 1: return [center]
        case 2: return [topLeft, bottomRight]
        case 3: return [topLeft, center, bottomRight]
        case 4: return [topLeft, topRight, bottomLeft, bottomRight]
        case 5: return [topLeft, topRight, center, bottomLeft, bottomRight]
        case 6: return [topLeft, topRight, middleLeft, middleRight, bottomLeft, bottomRight]
        default: return []
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {}

    func roll(strategy: DiceRollStrategy, completion: @escaping (Int, Int) -> Void) {
        let value1 = Int.random(in: 1...6)
        let value2 = Int.random(in: 1...6)

        strategy.animateDie(diceNode1, toValue: value1, createMaterials: createDiceMaterials)
        strategy.animateDie(diceNode2, toValue: value2, createMaterials: createDiceMaterials)

        DispatchQueue.main.asyncAfter(deadline: .now() + strategy.totalDuration) {
            completion(value1, value2)
        }
    }
}

// MARK: - Dice Cell (one strategy's dice + labels)

class DiceStrategyCell: UIView {

    private let sceneView: SCNView = {
        let view = SCNView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = false
        return view
    }()

    private let resultLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.textColor = .white
        label.text = ""
        label.isUserInteractionEnabled = false
        return label
    }()

    private let tapToRollLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14, weight: .bold)
        label.textColor = HardwayColors.betGray
        label.text = "Tap to Roll"
        label.isUserInteractionEnabled = false
        return label
    }()

    private let strategyNameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        label.isUserInteractionEnabled = false
        return label
    }()

    private var diceScene: PlaygroundDiceScene!
    let strategy: DiceRollStrategy
    private(set) var isRolling: Bool = false

    init(strategy: DiceRollStrategy) {
        self.strategy = strategy
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        layer.cornerRadius = 16
        layer.borderWidth = 1.5
        layer.borderColor = HardwayColors.label.withAlphaComponent(0.15).cgColor
        backgroundColor = HardwayColors.surfaceGray.withAlphaComponent(0.3)
        clipsToBounds = true

        addSubview(strategyNameLabel)
        addSubview(sceneView)
        addSubview(resultLabel)
        addSubview(tapToRollLabel)

        strategyNameLabel.text = strategy.name

        NSLayoutConstraint.activate([
            strategyNameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            strategyNameLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            sceneView.topAnchor.constraint(equalTo: strategyNameLabel.bottomAnchor, constant: 4),
            sceneView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: trailingAnchor),
            sceneView.bottomAnchor.constraint(equalTo: tapToRollLabel.topAnchor, constant: -4),

            resultLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            resultLabel.topAnchor.constraint(equalTo: sceneView.topAnchor, constant: 2),

            tapToRollLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            tapToRollLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        diceScene = PlaygroundDiceScene()
        sceneView.scene = diceScene.scene
        sceneView.delegate = diceScene
    }

    func roll() {
        guard !isRolling else { return }
        isRolling = true

        UIView.animate(withDuration: 0.15) {
            self.resultLabel.alpha = 0
        }

        diceScene.roll(strategy: strategy) { [weak self] value1, value2 in
            guard let self = self else { return }
            let total = value1 + value2
            self.showResult("\(total)")
            self.isRolling = false
            HapticsHelper.superLightHaptic()
        }
    }

    private func showResult(_ text: String) {
        resultLabel.text = text
        resultLabel.transform = CGAffineTransform(translationX: 0, y: 20)
        resultLabel.alpha = 0

        let animator = UIViewPropertyAnimator(
            duration: 0.2,
            controlPoint1: CGPoint(x: 0.01, y: 1.13),
            controlPoint2: CGPoint(x: 0.32, y: 1.38)
        ) {
            self.resultLabel.transform = .identity
            self.resultLabel.alpha = 1
        }
        animator.startAnimation()
    }
}

// MARK: - DicePlaygroundViewController

class DicePlaygroundViewController: UIViewController {

    private var strategyCells: [DiceStrategyCell] = []
    private var gridStack: UIStackView!
    private var rollAllButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Dice Playground"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(dismissPlayground)
        )

        setupStrategyCells()
        setupRollAllButton()
    }

    private func setupStrategyCells() {
        let strategies: [DiceRollStrategy] = [
            TumbleSettleStrategy(),
            DecoyTumbleStrategy(),
            RapidShuffleStrategy(),
            BounceStrategy()
        ]

        strategyCells = strategies.map { DiceStrategyCell(strategy: $0) }

        // 2x2 grid
        let topRow = UIStackView(arrangedSubviews: [strategyCells[0], strategyCells[1]])
        topRow.axis = .horizontal
        topRow.distribution = .fillEqually
        topRow.spacing = 12

        let bottomRow = UIStackView(arrangedSubviews: [strategyCells[2], strategyCells[3]])
        bottomRow.axis = .horizontal
        bottomRow.distribution = .fillEqually
        bottomRow.spacing = 12

        gridStack = UIStackView(arrangedSubviews: [topRow, bottomRow])
        gridStack.translatesAutoresizingMaskIntoConstraints = false
        gridStack.axis = .vertical
        gridStack.distribution = .fillEqually
        gridStack.spacing = 12

        view.addSubview(gridStack)

        NSLayoutConstraint.activate([
            gridStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            gridStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            gridStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])

        // NOTE: gridStack bottom is pinned to rollAllButton top in setupRollAllButton()

        // Add tap gesture to each cell
        for cell in strategyCells {
            let tap = UITapGestureRecognizer(target: self, action: #selector(cellTapped(_:)))
            cell.addGestureRecognizer(tap)
            cell.isUserInteractionEnabled = true
        }
    }

    private func setupRollAllButton() {
        rollAllButton = UIButton(type: .system)
        rollAllButton.translatesAutoresizingMaskIntoConstraints = false
        rollAllButton.setTitle("Roll All", for: .normal)
        rollAllButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        rollAllButton.backgroundColor = HardwayColors.green
        rollAllButton.setTitleColor(.white, for: .normal)
        rollAllButton.layer.cornerRadius = 20
        rollAllButton.layer.borderWidth = 1.5
        rollAllButton.layer.borderColor = HardwayColors.label.withAlphaComponent(0.35).cgColor
        rollAllButton.addTarget(self, action: #selector(rollAllTapped), for: .touchUpInside)

        view.addSubview(rollAllButton)

        NSLayoutConstraint.activate([
            rollAllButton.topAnchor.constraint(equalTo: gridStack.bottomAnchor, constant: 20),
            rollAllButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            rollAllButton.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -64),
            rollAllButton.heightAnchor.constraint(equalToConstant: 56),
            rollAllButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    // MARK: - Actions

    @objc private func dismissPlayground() {
        dismiss(animated: true)
    }

    @objc private func cellTapped(_ gesture: UITapGestureRecognizer) {
        guard let cell = gesture.view as? DiceStrategyCell else { return }
        HapticsHelper.thwompHaptic()
        animateTap(cell)
        cell.roll()
    }

    @objc private func rollAllTapped() {
        HapticsHelper.thwompHaptic()

        // Press animation on button
        UIView.animate(withDuration: 0.1, animations: {
            self.rollAllButton.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) {
                self.rollAllButton.transform = .identity
            }
        }

        for cell in strategyCells {
            cell.roll()
        }
    }

    private func animateTap(_ view: UIView) {
        UIView.animate(withDuration: 0.1, animations: {
            view.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        }) { _ in
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) {
                view.transform = .identity
            }
        }
    }
}
