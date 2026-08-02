//
//  LudoPowerupIcon.swift
//  ludo
//
//  Simple vector icons for mystery-tile powerups (SpriteKit shapes).
//

import SpriteKit

enum LudoPowerupIcon {

    static func makeIcon(for powerup: LudoPowerup, size: CGFloat = 44) -> SKNode {
        switch powerup {
        case .dash: return makeDashIcon(size: size)
        case .swap: return makeSwapIcon(size: size)
        case .trap: return makeTrapIcon(size: size)
        case .freezeToken: return makeFreezeIcon(size: size)
        case .smallShield: return makeShieldIcon(size: size, big: false)
        case .bigShield: return makeShieldIcon(size: size, big: true)
        case .blackhole: return makeBlackholeIcon(size: size)
        }
    }

    /// Fallback when rarity rolled but no powerup exists in the pool yet.
    static func makeMysteryIcon(size: CGFloat = 44) -> SKNode {
        let root = SKNode()
        root.name = "powerupIcon_mystery"

        let badge = SKShapeNode(circleOfRadius: size * 0.38)
        badge.fillColor = SKColor(red: 0.42, green: 0.32, blue: 0.62, alpha: 0.9)
        badge.strokeColor = SKColor(red: 0.78, green: 0.68, blue: 1, alpha: 0.85)
        badge.lineWidth = 1.5
        root.addChild(badge)

        let q = SKLabelNode(fontNamed: "AvenirNext-Bold")
        q.text = "?"
        q.fontSize = size * 0.52
        q.fontColor = SKColor(white: 1, alpha: 0.95)
        q.verticalAlignmentMode = .center
        q.horizontalAlignmentMode = .center
        root.addChild(q)

        return root
    }

    /// Three forward chevrons — “burst ahead”.
    private static func makeDashIcon(size: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "powerupIcon_dash"

        let plate = SKShapeNode(rectOf: CGSize(width: size * 0.9, height: size * 0.72), cornerRadius: size * 0.14)
        plate.fillColor = SKColor(red: 0.12, green: 0.38, blue: 0.28, alpha: 0.95)
        plate.strokeColor = SKColor(red: 0.35, green: 0.9, blue: 0.55, alpha: 0.9)
        plate.lineWidth = 1.4
        root.addChild(plate)

        let chevronColor = SKColor(red: 0.5, green: 1, blue: 0.72, alpha: 1)
        let spacing = size * 0.17
        for i in 0..<3 {
            let chevron = SKShapeNode(path: chevronPath(width: size * 0.14, height: size * 0.22))
            chevron.fillColor = chevronColor
            chevron.strokeColor = .clear
            chevron.position = CGPoint(x: -spacing + CGFloat(i) * spacing, y: 0)
            chevron.zRotation = 0
            root.addChild(chevron)
        }

        return root
    }

    /// Two tokens with crossing arrows — “swap places”.
    private static func makeSwapIcon(size: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "powerupIcon_swap"

        let plate = SKShapeNode(rectOf: CGSize(width: size * 0.9, height: size * 0.72), cornerRadius: size * 0.14)
        plate.fillColor = SKColor(red: 0.14, green: 0.22, blue: 0.42, alpha: 0.95)
        plate.strokeColor = SKColor(red: 0.45, green: 0.65, blue: 1, alpha: 0.9)
        plate.lineWidth = 1.4
        root.addChild(plate)

        let r = size * 0.13
        let left = SKShapeNode(circleOfRadius: r)
        left.fillColor = SKColor(red: 0.9, green: 0.35, blue: 0.3, alpha: 1)
        left.strokeColor = SKColor(white: 1, alpha: 0.35)
        left.lineWidth = 1
        left.position = CGPoint(x: -size * 0.2, y: size * 0.06)
        root.addChild(left)

        let right = SKShapeNode(circleOfRadius: r)
        right.fillColor = SKColor(red: 0.25, green: 0.55, blue: 0.95, alpha: 1)
        right.strokeColor = SKColor(white: 1, alpha: 0.35)
        right.lineWidth = 1
        right.position = CGPoint(x: size * 0.2, y: -size * 0.06)
        root.addChild(right)

        let arrow = SKShapeNode(path: swapArrowsPath(span: size * 0.34))
        arrow.strokeColor = SKColor(red: 0.85, green: 0.92, blue: 1, alpha: 1)
        arrow.lineWidth = 2.2
        arrow.lineCap = .round
        arrow.fillColor = .clear
        root.addChild(arrow)

        return root
    }

    private static func makeBlackholeIcon(size: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "powerupIcon_blackhole"
        let plate = SKShapeNode(rectOf: CGSize(width: size * 0.9, height: size * 0.72), cornerRadius: size * 0.14)
        plate.fillColor = SKColor(red: 0.18, green: 0.08, blue: 0.32, alpha: 0.96)
        plate.strokeColor = SKColor(red: 0.72, green: 0.35, blue: 1, alpha: 0.9)
        plate.lineWidth = 1.4
        root.addChild(plate)

        let core = SKShapeNode(circleOfRadius: size * 0.14)
        core.fillColor = SKColor(red: 0.05, green: 0.02, blue: 0.12, alpha: 1)
        core.strokeColor = SKColor(red: 0.85, green: 0.45, blue: 1, alpha: 0.85)
        core.lineWidth = 1.2
        root.addChild(core)

        let ring = SKShapeNode(circleOfRadius: size * 0.26)
        ring.fillColor = .clear
        ring.strokeColor = SKColor(red: 0.65, green: 0.25, blue: 0.95, alpha: 0.75)
        ring.lineWidth = 2
        root.addChild(ring)
        ring.run(SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 2.2)))

        return root
    }

    private static func makeTrapIcon(size: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "powerupIcon_trap"
        let plate = SKShapeNode(rectOf: CGSize(width: size * 0.9, height: size * 0.72), cornerRadius: size * 0.14)
        plate.fillColor = SKColor(red: 0.42, green: 0.12, blue: 0.1, alpha: 0.95)
        plate.strokeColor = SKColor(red: 1, green: 0.45, blue: 0.2, alpha: 0.9)
        plate.lineWidth = 1.4
        root.addChild(plate)
        for i in 0..<3 {
            let spike = SKShapeNode(path: trapSpikePath())
            spike.fillColor = SKColor(red: 0.95, green: 0.3, blue: 0.15, alpha: 1)
            spike.strokeColor = .clear
            spike.position = CGPoint(x: CGFloat(i - 1) * size * 0.14, y: size * 0.04)
            root.addChild(spike)
        }
        return root
    }

    private static func trapSpikePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 6))
        path.addLine(to: CGPoint(x: -3.5, y: -5))
        path.addLine(to: CGPoint(x: 3.5, y: -5))
        path.closeSubpath()
        return path
    }

    /// Six-arm snowflake (vector strokes — emoji snowflakes often fail to draw in SpriteKit).
    private static func makeFreezeIcon(size: CGFloat) -> SKNode {
        let root = SKNode()
        root.name = "powerupIcon_freeze"
        let plate = SKShapeNode(rectOf: CGSize(width: size * 0.9, height: size * 0.72), cornerRadius: size * 0.14)
        plate.fillColor = SKColor(red: 0.12, green: 0.28, blue: 0.45, alpha: 0.95)
        plate.strokeColor = SKColor(red: 0.5, green: 0.8, blue: 1, alpha: 0.9)
        plate.lineWidth = 1.4
        root.addChild(plate)

        let flake = SKShapeNode(path: snowflakePath(radius: size * 0.28))
        flake.strokeColor = SKColor(red: 0.78, green: 0.94, blue: 1, alpha: 1)
        flake.fillColor = .clear
        flake.lineWidth = max(1.6, size * 0.045)
        flake.lineCap = .round
        flake.lineJoin = .round
        root.addChild(flake)

        let hub = SKShapeNode(circleOfRadius: size * 0.055)
        hub.fillColor = SKColor(red: 0.9, green: 0.98, blue: 1, alpha: 1)
        hub.strokeColor = .clear
        root.addChild(hub)

        return root
    }

    private static func snowflakePath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let branch = radius * 0.22
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3 - .pi / 2
            let tip = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            let mid = CGPoint(x: cos(angle) * radius * 0.58, y: sin(angle) * radius * 0.58)
            let perpX = -sin(angle) * branch
            let perpY = cos(angle) * branch

            path.move(to: .zero)
            path.addLine(to: tip)
            path.move(to: mid)
            path.addLine(to: CGPoint(x: mid.x + perpX, y: mid.y + perpY))
            path.move(to: mid)
            path.addLine(to: CGPoint(x: mid.x - perpX, y: mid.y - perpY))
        }
        return path
    }

    private static func makeShieldIcon(size: CGFloat, big: Bool) -> SKNode {
        let root = SKNode()
        root.name = big ? "powerupIcon_bigShield" : "powerupIcon_smallShield"
        let plate = SKShapeNode(rectOf: CGSize(width: size * 0.9, height: size * 0.72), cornerRadius: size * 0.14)
        plate.fillColor = SKColor(red: 0.14, green: 0.22, blue: 0.38, alpha: 0.95)
        plate.strokeColor = SKColor(red: big ? 0.95 : 0.55, green: big ? 0.78 : 0.82, blue: big ? 0.25 : 1, alpha: 0.9)
        plate.lineWidth = 1.4
        root.addChild(plate)
        let shield = SKShapeNode(path: shieldPath(width: size * (big ? 0.42 : 0.36), height: size * 0.44))
        shield.fillColor = SKColor(red: 0.35, green: 0.55, blue: 0.9, alpha: 0.85)
        shield.strokeColor = SKColor(white: 1, alpha: 0.5)
        shield.lineWidth = 1.2
        root.addChild(shield)
        return root
    }

    private static func shieldPath(width: CGFloat, height: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: height * 0.5))
        path.addLine(to: CGPoint(x: width * 0.5, y: height * 0.15))
        path.addLine(to: CGPoint(x: width * 0.5, y: -height * 0.45))
        path.addLine(to: CGPoint(x: -width * 0.5, y: -height * 0.45))
        path.addLine(to: CGPoint(x: -width * 0.5, y: height * 0.15))
        path.closeSubpath()
        return path
    }

    private static func chevronPath(width: CGFloat, height: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -width * 0.5, y: height * 0.5))
        path.addLine(to: CGPoint(x: width * 0.5, y: 0))
        path.addLine(to: CGPoint(x: -width * 0.5, y: -height * 0.5))
        path.closeSubpath()
        return path
    }

    private static func swapArrowsPath(span: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let half = span * 0.5
        path.move(to: CGPoint(x: -half, y: half * 0.35))
        path.addQuadCurve(to: CGPoint(x: half, y: -half * 0.35), control: CGPoint(x: 0, y: 0))
        path.move(to: CGPoint(x: half - 5, y: -half * 0.35 + 4))
        path.addLine(to: CGPoint(x: half, y: -half * 0.35))
        path.addLine(to: CGPoint(x: half - 5, y: -half * 0.35 - 4))

        path.move(to: CGPoint(x: half, y: -half * 0.35))
        path.addQuadCurve(to: CGPoint(x: -half, y: half * 0.35), control: CGPoint(x: 0, y: 0))
        path.move(to: CGPoint(x: -half + 5, y: half * 0.35 - 4))
        path.addLine(to: CGPoint(x: -half, y: half * 0.35))
        path.addLine(to: CGPoint(x: -half + 5, y: half * 0.35 + 4))
        return path
    }
}
