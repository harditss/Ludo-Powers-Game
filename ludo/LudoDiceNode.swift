//
//  LudoDiceNode.swift
//  ludo
//

import SpriteKit

/// A standard six-sided die (pips) with roll animation.
@MainActor
final class LudoDiceNode: SKNode {

    private let dieSize: CGFloat
    private let body: SKShapeNode
    private let pipContainer = SKNode()
    private var isRolling = false
    private(set) var currentValue: Int = 1

    init(dieSize: CGFloat = 58) {
        self.dieSize = dieSize
        self.body = SKShapeNode(rectOf: CGSize(width: dieSize, height: dieSize), cornerRadius: dieSize * 0.18)
        super.init()
        name = "diceArea"

        body.fillColor = SKColor(red: 0.985, green: 0.985, blue: 1, alpha: 1)
        body.strokeColor = SKColor(white: 0.2, alpha: 0.55)
        body.lineWidth = 1.6
        body.glowWidth = 1
        body.zPosition = 0
        addChild(body)

        let sheen = SKShapeNode(rectOf: CGSize(width: dieSize * 0.82, height: dieSize * 0.34), cornerRadius: dieSize * 0.12)
        sheen.fillColor = SKColor(white: 1, alpha: 0.34)
        sheen.strokeColor = .clear
        sheen.position = CGPoint(x: 0, y: dieSize * 0.14)
        sheen.zPosition = 0.5
        body.addChild(sheen)

        pipContainer.zPosition = 1
        addChild(pipContainer)

        showFace(1)

        run(
            .repeatForever(.sequence([
                .moveBy(x: 0, y: 1.0, duration: 1.0),
                .moveBy(x: 0, y: -1.0, duration: 1.0),
            ])),
            withKey: "diceFloat"
        )
    }

    required init?(coder aDecoder: NSCoder) {
        nil
    }

    /// Shows `value` (1…6) with standard pip layout.
    func showFace(_ value: Int) {
        let v = min(6, max(1, value))
        currentValue = v
        pipContainer.removeAllChildren()

        let r = dieSize * 0.085
        let u = dieSize * 0.2
        let offsets: [CGPoint]
        switch v {
        case 1:
            offsets = [.zero]
        case 2:
            offsets = [CGPoint(x: -u, y: u), CGPoint(x: u, y: -u)]
        case 3:
            offsets = [CGPoint(x: -u, y: u), .zero, CGPoint(x: u, y: -u)]
        case 4:
            offsets = [
                CGPoint(x: -u, y: u), CGPoint(x: u, y: u),
                CGPoint(x: -u, y: -u), CGPoint(x: u, y: -u),
            ]
        case 5:
            offsets = [
                CGPoint(x: -u, y: u), CGPoint(x: u, y: u), .zero,
                CGPoint(x: -u, y: -u), CGPoint(x: u, y: -u),
            ]
        default:
            offsets = [
                CGPoint(x: -u, y: u), CGPoint(x: u, y: u),
                CGPoint(x: -u, y: .zero), CGPoint(x: u, y: .zero),
                CGPoint(x: -u, y: -u), CGPoint(x: u, y: -u),
            ]
        }

        for o in offsets {
            let pip = SKShapeNode(circleOfRadius: r)
            pip.fillColor = SKColor(white: 0.14, alpha: 1)
            pip.strokeColor = SKColor(white: 1, alpha: 0.12)
            pip.lineWidth = 0.4
            pip.position = o
            pipContainer.addChild(pip)
        }
    }

    /// Random roll with flicker + spin + settle. Calls `completion` on the main actor with the final value.
    func rollAnimated(completion: @escaping (Int) -> Void) {
        guard !isRolling else { return }
        isRolling = true

        let final = Int.random(in: 1...6)
        let flickerCount = 14
        var sequence: [SKAction] = []

        for _ in 0..<flickerCount {
            sequence.append(SKAction.run { [weak self] in
                self?.showFace(Int.random(in: 1...6))
            })
            sequence.append(SKAction.wait(forDuration: 0.04))
        }

        sequence.append(SKAction.run { [weak self] in
            self?.showFace(final)
        })

        let spin = SKAction.rotate(byAngle: .pi * 2.25, duration: 0.28)
        spin.timingMode = .easeOut

        let bumpUp = SKAction.scale(to: 1.14, duration: 0.1)
        bumpUp.timingMode = .easeInEaseOut
        let bumpDown = SKAction.scale(to: 1.0, duration: 0.14)
        bumpDown.timingMode = .easeOut

        sequence.append(SKAction.group([spin, SKAction.sequence([bumpUp, bumpDown])]))
        sequence.append(SKAction.run { [weak self] in
            guard let self else { return }
            self.zRotation = 0
            self.isRolling = false
            completion(final)
        })

        run(SKAction.sequence(sequence), withKey: "rollDice")
    }

    func cancelRollAnimation() {
        removeAction(forKey: "rollDice")
        isRolling = false
        zRotation = 0
        setScale(1)
    }

    /// Short flicker animation, then shows the given roll (debug / staged rolls).
    func revealRoll(to value: Int, completion: @escaping () -> Void) {
        cancelRollAnimation()
        isRolling = true
        let final = min(6, max(1, value))
        var sequence: [SKAction] = []
        for _ in 0..<8 {
            sequence.append(SKAction.run { [weak self] in
                self?.showFace(Int.random(in: 1...6))
            })
            sequence.append(SKAction.wait(forDuration: 0.035))
        }
        sequence.append(SKAction.run { [weak self] in
            guard let self else { return }
            self.showFace(final)
            self.isRolling = false
            completion()
        })
        run(SKAction.sequence(sequence), withKey: "rollDice")
    }
}
