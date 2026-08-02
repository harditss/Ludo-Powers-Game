//
//  LudoPartyStyle.swift
//  ludo
//
//  Lightweight “party game” feel helpers (procedural, no final art).
//  Tuned to be energetic without feeling blocky: softer corners, thinner strokes,
//  and no heavy black borders.
//

import CoreGraphics
import SpriteKit

enum LudoPartyStyle {

    // MARK: - Shared look

    /// A dark outline can quickly feel “sticker-like”; keep it soft.
    static let softOutline = SKColor(red: 0.12, green: 0.15, blue: 0.24, alpha: 0.55)
    static let outlineWidth: CGFloat = 1.4

    static let fontTitle = "AvenirNext-DemiBold"
    static let fontBody = "AvenirNext-Medium"

    // MARK: - Backdrop

    static func makeVibrantBackdrop(size: CGSize) -> SKNode {
        let root = SKNode()
        root.name = "sceneBackdrop"
        root.zPosition = -50

        let pad = max(size.width, size.height) * 0.12
        let rect = CGSize(width: size.width + pad * 2, height: size.height + pad * 2)

        let base = SKShapeNode(rectOf: rect)
        base.fillColor = SKColor(red: 0.10, green: 0.16, blue: 0.28, alpha: 1)
        base.strokeColor = .clear
        root.addChild(base)

        let blobs: [(SKColor, CGPoint, CGSize, TimeInterval)] = [
            (SKColor(red: 0.98, green: 0.38, blue: 0.58, alpha: 0.22), CGPoint(x: -size.width * 0.24, y: size.height * 0.14), CGSize(width: rect.width * 0.58, height: rect.height * 0.38), 2.6),
            (SKColor(red: 0.32, green: 0.86, blue: 0.98, alpha: 0.18), CGPoint(x: size.width * 0.20, y: -size.height * 0.10), CGSize(width: rect.width * 0.50, height: rect.height * 0.42), 2.9),
            (SKColor(red: 0.62, green: 0.38, blue: 0.98, alpha: 0.16), CGPoint(x: 0, y: size.height * 0.26), CGSize(width: rect.width * 0.36, height: rect.height * 0.28), 3.2),
        ]

        for (i, blob) in blobs.enumerated() {
            let e = SKShapeNode(ellipseOf: blob.2)
            e.fillColor = blob.0
            e.strokeColor = .clear
            e.position = blob.1
            root.addChild(e)

            let dur = blob.3 + TimeInterval(i) * 0.18
            e.run(.repeatForever(.sequence([
                .group([
                    .scale(to: 1.05, duration: dur),
                    .fadeAlpha(to: 0.72, duration: dur),
                ]),
                .group([
                    .scale(to: 0.96, duration: dur),
                    .fadeAlpha(to: 1, duration: dur),
                ]),
            ])))
        }
        return root
    }

    // MARK: - Tokens

    static func styleTokenToy(_ token: SKShapeNode, fill: SKColor, stroke: SKColor) {
        token.fillColor = fill
        token.strokeColor = stroke.withAlphaComponent(0.85)
        token.lineWidth = 2
        token.glowWidth = 0.8

        token.childNode(withName: "partyTokenShine")?.removeFromParent()
        let shine = SKShapeNode(circleOfRadius: 4.2)
        shine.name = "partyTokenShine"
        shine.fillColor = SKColor(white: 1, alpha: 0.45)
        shine.strokeColor = .clear
        shine.position = CGPoint(x: -2.4, y: 3)
        shine.zPosition = 1
        token.addChild(shine)
    }

    static func startIdleWobble(_ node: SKNode, amplitude: CGFloat = 0.28) {
        node.removeAction(forKey: "partyIdleWobble")
        let wobble = SKAction.repeatForever(SKAction.sequence([
            .group([
                .rotate(byAngle: 0.028, duration: 1.0),
                .moveBy(x: 0, y: amplitude, duration: 1.0),
            ]),
            .group([
                .rotate(byAngle: -0.056, duration: 1.2),
                .moveBy(x: 0, y: -amplitude, duration: 1.2),
            ]),
            .group([
                .rotate(byAngle: 0.028, duration: 1.0),
                .moveBy(x: 0, y: 0, duration: 1.0),
            ]),
        ]))
        wobble.timingMode = .easeInEaseOut
        node.run(wobble, withKey: "partyIdleWobble")
    }

    static func squashStretchLand(node: SKNode) -> SKAction {
        let sx = node.xScale
        let sy = node.yScale
        return .sequence([
            .group([
                .scaleX(to: sx * 1.18, duration: 0.06),
                .scaleY(to: sy * 0.86, duration: 0.06),
                .moveBy(x: 0, y: 2.0, duration: 0.06),
            ]),
            .group([
                .scaleX(to: sx, duration: 0.12),
                .scaleY(to: sy, duration: 0.12),
                .moveBy(x: 0, y: -2.0, duration: 0.12),
            ]),
        ])
    }

    // MARK: - HUD

    static func makeHudDock(width: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "partyHudDock"
        let h: CGFloat = 104

        let card = SKShapeNode(rectOf: CGSize(width: width, height: h), cornerRadius: 18)
        card.fillColor = SKColor(red: 0.08, green: 0.1, blue: 0.2, alpha: 0.46)
        card.strokeColor = SKColor(white: 1, alpha: 0.16)
        card.lineWidth = 1.2
        card.glowWidth = 1.5
        card.zPosition = -1
        root.addChild(card)

        let sheen = SKShapeNode(rectOf: CGSize(width: width * 0.92, height: h * 0.38), cornerRadius: 14)
        sheen.fillColor = SKColor(white: 1, alpha: 0.06)
        sheen.strokeColor = .clear
        sheen.position = CGPoint(x: 0, y: h * 0.16)
        sheen.zPosition = -0.5
        root.addChild(sheen)

        root.run(.repeatForever(.sequence([
            .moveBy(x: 0, y: 1.1, duration: 1.6),
            .moveBy(x: 0, y: -1.1, duration: 1.6),
        ])))
        return root
    }

    static func animatePopText(_ label: SKLabelNode?, text: String) {
        guard let label else { return }
        label.removeAction(forKey: "partyTextPop")
        label.text = text
        label.alpha = 0
        label.setScale(0.96)
        label.run(.group([
            .fadeIn(withDuration: 0.12),
            .sequence([
                .scale(to: 1.02, duration: 0.1),
                .scale(to: 1, duration: 0.08),
            ]),
        ]), withKey: "partyTextPop")
    }

    // MARK: - Dice

    static func makeDiceGlow(radius: CGFloat) -> SKShapeNode {
        let glow = SKShapeNode(circleOfRadius: radius)
        glow.fillColor = SKColor(red: 1, green: 0.86, blue: 0.28, alpha: 0.14)
        glow.strokeColor = SKColor(red: 1, green: 0.82, blue: 0.22, alpha: 0.22)
        glow.lineWidth = 1
        glow.glowWidth = 5
        glow.zPosition = -1
        glow.run(.repeatForever(.sequence([
            .scale(to: 1.06, duration: 0.65),
            .scale(to: 0.96, duration: 0.65),
        ])))
        return glow
    }
}

