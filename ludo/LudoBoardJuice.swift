//
//  LudoBoardJuice.swift
//  ludo
//
//  Procedural party-game polish — no artwork required.
//

import CoreGraphics
import SpriteKit

enum LudoBoardJuice {

  private static let shadowName = "tokenShadow"
  private static let glowName = "juiceGlow"
  private static let sparkleContainerName = "juiceSparkles"

  // MARK: - Scene backdrop

  static func makeSceneBackdrop(size: CGSize) -> SKNode {
    LudoPartyStyle.makeVibrantBackdrop(size: size)
  }

  // MARK: - Board tiles

  enum TileKind {
    case yard
    case trackWhite
    case trackSafe
    case home
  }

  static func styleTile(_ tile: SKShapeNode, kind: TileKind, accent: SKColor?, phase: CGFloat) {
    tile.removeAction(forKey: "juiceBob")
    if tile.childNode(withName: "juiceHighlight") == nil {
      let w = tile.frame.width > 1 ? tile.frame.width : 26
      let h = tile.frame.height > 1 ? tile.frame.height : 26
      let highlight = SKShapeNode(rectOf: CGSize(width: w * 0.82, height: h * 0.42), cornerRadius: 2)
      highlight.name = "juiceHighlight"
      highlight.fillColor = SKColor(white: 1, alpha: 0.22)
      highlight.strokeColor = .clear
      highlight.position = CGPoint(x: 0, y: h * 0.14)
      highlight.zPosition = 0.2
      tile.addChild(highlight)
    }

    switch kind {
    case .yard:
      applySoftGradient(tile, light: SKColor(white: 1, alpha: 0.35), dark: SKColor(white: 0.9, alpha: 0.08))
    case .trackWhite:
      applySoftGradient(tile, light: SKColor(white: 1, alpha: 0.28), dark: SKColor(white: 0.92, alpha: 0.05))
    case .trackSafe, .home:
      if let accent {
        applySoftGradient(tile, light: accent.withAlphaComponent(0.45), dark: accent.withAlphaComponent(0.12))
      }
    }

    if kind != .home, kind != .trackSafe {
      let bob = bobAction(phase: phase, amplitude: 0.9)
      tile.run(bob, withKey: "juiceBob")
    }

    if kind == .trackSafe, let accent {
      attachGlow(to: tile, color: accent, size: CGSize(width: 28, height: 28), lineWidth: 2.4, pulse: false)
    }
  }

  /// Home stretch: static gradient only (no pulsing glow or bob).
  static func styleHomeTile(_ tile: SKShapeNode, accent: SKColor) {
    tile.removeAction(forKey: "juiceBob")
    tile.childNode(withName: glowName)?.removeFromParent()
    if tile.childNode(withName: "juiceHighlight") == nil {
      let w = tile.frame.width > 1 ? tile.frame.width : 26
      let h = tile.frame.height > 1 ? tile.frame.height : 26
      let highlight = SKShapeNode(rectOf: CGSize(width: w * 0.82, height: h * 0.42), cornerRadius: 2)
      highlight.name = "juiceHighlight"
      highlight.fillColor = SKColor(white: 1, alpha: 0.18)
      highlight.strokeColor = .clear
      highlight.position = CGPoint(x: 0, y: h * 0.14)
      highlight.zPosition = 0.2
      tile.addChild(highlight)
    }
    applySoftGradient(tile, light: accent.withAlphaComponent(0.4), dark: accent.withAlphaComponent(0.14))
  }

  static func styleStarGlyph(_ star: SKShapeNode) {
    star.removeAction(forKey: "juiceBob")
    star.removeAction(forKey: "juiceTwinkle")
    star.alpha = 1
  }

  static func installBoardAmbient(on root: SKNode) {
    root.enumerateChildNodes(withName: "//*") { node, _ in
      guard let tile = node as? SKShapeNode else { return }
      let name = tile.name ?? ""
      let phase = CGFloat((name.hashValue & 0xFF)) / 255 * 0.8

      if name.hasPrefix("track_"), let idx = Int(name.replacingOccurrences(of: "track_", with: "")) {
        let safe = LudoBoardPath.safePublicPathIndices.contains(idx)
        if safe, let seat = seatForSafePathIndex(idx) {
          styleTile(tile, kind: .trackSafe, accent: seat.tokenFill, phase: phase)
        } else {
          styleTile(tile, kind: .trackWhite, accent: nil, phase: phase)
        }
      } else if name.hasPrefix("yard_"), let seatRaw = name.split(separator: "_").dropFirst().first,
                let seat = LudoSeat(rawValue: Int(seatRaw) ?? -1) {
        styleTile(tile, kind: .yard, accent: seat.tokenFill, phase: phase)
      } else if name.hasPrefix("home_"), let seatRaw = name.split(separator: "_").dropFirst().first,
                let seat = LudoSeat(rawValue: Int(seatRaw) ?? -1) {
        styleHomeTile(tile, accent: seat.tokenFill)
      } else if name == "starGlyph" {
        styleStarGlyph(tile)
      }
    }
  }

  private static func seatForSafePathIndex(_ index: Int) -> LudoSeat? {
    for seat in LudoSeat.allCases where LudoBoardPath.publicPathEntryIndex(for: seat) == index {
      return seat
    }
    return nil
  }

  static func applySoftGradient(_ tile: SKShapeNode, light: SKColor, dark: SKColor) {
    tile.fillColor = dark
    if let highlight = tile.childNode(withName: "juiceHighlight") as? SKShapeNode {
      highlight.fillColor = light
    }
  }

  static func attachGlow(to node: SKNode, color: SKColor, size: CGSize, lineWidth: CGFloat, pulse: Bool) {
    if node.childNode(withName: glowName) != nil { return }
    let glow = SKShapeNode(rectOf: size, cornerRadius: 4)
    glow.name = glowName
    glow.fillColor = .clear
    glow.strokeColor = color.withAlphaComponent(0.85)
    glow.lineWidth = lineWidth
    glow.glowWidth = 3
    glow.zPosition = -0.1
    node.addChild(glow)
    guard pulse else { return }
    let pulseAction = SKAction.repeatForever(SKAction.sequence([
      SKAction.customAction(withDuration: 0.55) { n, t in
        guard let shape = n as? SKShapeNode else { return }
        let wave = 0.55 + 0.45 * sin(t * .pi * 2)
        shape.strokeColor = color.withAlphaComponent(CGFloat(wave))
        shape.setScale(1 + 0.04 * sin(t * .pi * 2))
      },
      SKAction.wait(forDuration: 0.02),
    ]))
    glow.run(pulseAction, withKey: "juiceGlowPulse")
  }

  // MARK: - Tokens

  static func attachTokenShadow(to token: SKShapeNode) {
    guard token.childNode(withName: shadowName) == nil else { return }
    let shadow = SKShapeNode(ellipseOf: CGSize(width: 15, height: 6.5))
    shadow.name = shadowName
    shadow.fillColor = SKColor(white: 0, alpha: 0.26)
    shadow.strokeColor = .clear
    shadow.position = CGPoint(x: 1.5, y: -4)
    shadow.zPosition = -2
    token.addChild(shadow)

    let breathe = SKAction.repeatForever(SKAction.sequence([
      SKAction.fadeAlpha(to: 0.14, duration: 0.85),
      SKAction.fadeAlpha(to: 0.3, duration: 0.85),
    ]))
    shadow.run(breathe, withKey: "juiceShadowBreathe")
  }

  static func styleToyToken(_ token: SKShapeNode, fill: SKColor, stroke: SKColor) {
    LudoPartyStyle.styleTokenToy(token, fill: fill, stroke: stroke)
    attachTokenShadow(to: token)
    LudoPartyStyle.startIdleWobble(token)
  }

  // MARK: - Movement

  static func easedMove(to point: CGPoint, duration: TimeInterval) -> SKAction {
    let move = SKAction.move(to: point, duration: duration)
    move.timingMode = .easeInEaseOut
    return move
  }

  /// Fade out on the trap square, then invisibly relocate to the yard (no slide home).
  static func trapKillFade(on node: SKNode, toYardPosition: CGPoint, fadeDuration: TimeInterval = 0.65) -> SKAction {
    SKAction.sequence([
      SKAction.group([
        SKAction.fadeAlpha(to: 0, duration: fadeDuration),
        SKAction.scale(to: 0.5, duration: fadeDuration),
      ]),
      SKAction.run {
        node.position = toYardPosition
        node.setScale(1)
        node.alpha = 0
      },
      SKAction.fadeAlpha(to: 1, duration: 0.16),
    ])
  }

  static func landBounce(on node: SKNode) -> SKAction {
    SKAction.sequence([
      LudoPartyStyle.squashStretchLand(node: node),
      SKAction.run { LudoPartyStyle.startIdleWobble(node) },
    ])
  }

  // MARK: - Screen shake

  static func shake(_ node: SKNode, intensity: CGFloat = 5, duration: TimeInterval = 0.22) {
    node.removeAction(forKey: "juiceShake")
    let steps = max(3, Int(duration / 0.04))
    var actions: [SKAction] = []
    for i in 0..<steps {
      let falloff = 1 - CGFloat(i) / CGFloat(steps)
      let dx = (i % 2 == 0 ? 1 : -1) * intensity * falloff
      let dy = (i % 3 == 0 ? 0.35 : -0.35) * intensity * falloff
      actions.append(SKAction.moveBy(x: dx, y: dy, duration: duration / Double(steps)))
    }
    actions.append(SKAction.move(to: .zero, duration: 0.02))
    node.run(SKAction.sequence(actions), withKey: "juiceShake")
  }

  // MARK: - Particles

  static func spawnBurst(
    at position: CGPoint,
    in parent: SKNode,
    color: SKColor,
    count: Int = 14,
    spread: CGFloat = 24,
    zPosition: CGFloat = 20
  ) {
    for i in 0..<count {
      let dot = SKShapeNode(circleOfRadius: CGFloat.random(in: 2...4.5))
      dot.fillColor = color.withAlphaComponent(CGFloat.random(in: 0.65...1))
      dot.strokeColor = SKColor(white: 1, alpha: 0.35)
      dot.lineWidth = 0.5
      dot.position = position
      dot.zPosition = zPosition
      parent.addChild(dot)

      let angle = CGFloat.random(in: 0...(2 * .pi))
      let dist = CGFloat.random(in: spread * 0.35...spread)
      let end = CGPoint(x: position.x + cos(angle) * dist, y: position.y + sin(angle) * dist)
      let dur = TimeInterval.random(in: 0.22...0.42)
      dot.run(SKAction.sequence([
        SKAction.group([
          SKAction.move(to: end, duration: dur),
          SKAction.fadeOut(withDuration: dur),
          SKAction.scale(to: 0.2, duration: dur),
        ]),
        SKAction.removeFromParent(),
      ]))
      _ = i
    }
  }

  static func spawnSparkles(
    at position: CGPoint,
    in parent: SKNode,
    colors: [SKColor],
    count: Int = 10,
    zPosition: CGFloat = 21
  ) {
    guard !colors.isEmpty else { return }
    for _ in 0..<count {
      let star = SKShapeNode(circleOfRadius: 2.2)
      let c = colors.randomElement() ?? .white
      star.fillColor = c
      star.strokeColor = SKColor(white: 1, alpha: 0.5)
      star.lineWidth = 0.4
      star.position = position
      star.zPosition = zPosition
      star.setScale(0.4)
      parent.addChild(star)

      let angle = CGFloat.random(in: 0...(2 * .pi))
      let dist = CGFloat.random(in: 10...28)
      let end = CGPoint(x: position.x + cos(angle) * dist, y: position.y + sin(angle) * dist)
      star.run(SKAction.sequence([
        SKAction.group([
          SKAction.move(to: end, duration: 0.35),
          SKAction.scale(to: 1.1, duration: 0.18),
          SKAction.fadeOut(withDuration: 0.35),
        ]),
        SKAction.removeFromParent(),
      ]))
    }
  }

  // MARK: - Mystery / powerups

  static func decorateMysteryMarker(_ root: SKNode) {
    guard let bg = root.children.first(where: { $0 is SKShapeNode }) as? SKShapeNode else { return }
    attachGlow(to: bg, color: SKColor(red: 0.85, green: 0.45, blue: 1, alpha: 1), size: CGSize(width: 26, height: 26), lineWidth: 2.2, pulse: true)
    let pulse = SKAction.repeatForever(SKAction.sequence([
      SKAction.scale(to: 1.08, duration: 0.42),
      SKAction.scale(to: 0.96, duration: 0.42),
    ]))
    root.run(pulse, withKey: "juiceMysteryPulse")

    let orbit = SKNode()
    orbit.name = sparkleContainerName
    orbit.zPosition = 2
    root.addChild(orbit)
    let spin = SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 2.8))
    orbit.run(spin)

    for i in 0..<4 {
      let spark = SKShapeNode(circleOfRadius: 2)
      spark.fillColor = SKColor(red: 1, green: 0.85, blue: 0.35, alpha: 0.95)
      spark.strokeColor = .clear
      let a = CGFloat(i) / 4 * (.pi * 2)
      spark.position = CGPoint(x: cos(a) * 14, y: sin(a) * 14)
      orbit.addChild(spark)
      spark.run(SKAction.repeatForever(SKAction.sequence([
        SKAction.fadeAlpha(to: 0.35, duration: 0.35),
        SKAction.fadeAlpha(to: 1, duration: 0.35),
      ])))
    }
  }

  static func attachPowerupSparkles(to node: SKNode, colors: [SKColor]) {
    node.childNode(withName: sparkleContainerName)?.removeFromParent()
    let orbit = SKNode()
    orbit.name = sparkleContainerName
    orbit.zPosition = 5
    node.addChild(orbit)
    orbit.run(SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 2.2)))
    for i in 0..<5 {
      let s = SKShapeNode(circleOfRadius: 2.5)
      s.fillColor = colors[i % colors.count]
      s.strokeColor = SKColor(white: 1, alpha: 0.6)
      s.lineWidth = 0.5
      let a = CGFloat(i) / 5 * (.pi * 2)
      let r: CGFloat = node.calculateAccumulatedFrame().width > 1 ? node.calculateAccumulatedFrame().width * 0.55 : 30
      s.position = CGPoint(x: cos(a) * r, y: sin(a) * r)
      orbit.addChild(s)
      s.run(SKAction.repeatForever(SKAction.sequence([
        SKAction.fadeAlpha(to: 0.4, duration: 0.28),
        SKAction.fadeAlpha(to: 1, duration: 0.28),
      ])))
    }
  }

  // MARK: - Helpers

  private static func bobAction(phase: CGFloat, amplitude: CGFloat) -> SKAction {
    let dur = 0.95 + phase * 0.25
    let up = SKAction.moveBy(x: 0, y: amplitude, duration: dur)
    up.timingMode = .easeInEaseOut
    let down = up.reversed()
    return SKAction.repeatForever(SKAction.sequence([up, down]))
  }
}
