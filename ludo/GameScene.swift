//
//  GameScene.swift
//  ludo
//

import SpriteKit

@MainActor
final class GameScene: SKScene {

    /// Set from `GameViewController` to return to the home flow (dismisses the game).
    var onRequestMenu: (() -> Void)?

    private let boardContainer = SKNode()
    private var sceneBackdrop: SKNode?
    private var juiceParticlesLayer: SKNode?
    private var pendingMoveJuiceMessage: String?
    private let hudContainer = SKNode()
    private let diceContainer = SKNode()
    private let menuContainer = SKNode()
    private let playerCount: Int

    private let engine: LudoPassAndPlayEngine
    private var tokenNodes: [LudoSeat: [SKShapeNode]] = [:]

    private var diceNode: LudoDiceNode?
    private var lastRollLabel: SKLabelNode?
    private var modeLabel: SKLabelNode?
    private var turnLabel: SKLabelNode?
    private var hintLabel: SKLabelNode?
    private var strengthHudLabel: SKLabelNode?
    private var partyHudDock: SKNode?
    private var diceGlowNode: SKShapeNode?

    /// Grid cell for each seat’s “?” marker (nearest that colour’s start). Four markers; Voronoi partition guarantees one pickup zone per player arm.
    private var mysteryCellBySeat: [LudoSeat: GridCoord] = [:]
    private let mysteryLayer = SKNode()
    private var mysteryMarkerBySeat: [LudoSeat: SKNode] = [:]

    private var didResolveOpening = false
    private var openingAnimationRunning = false
    private var gameplayRollInFlight = false
    private var pendingOpeningOutcome: LudoOpeningOutcome?
    private var gameOverLayer: SKNode?
    private var powerupRevealRoot: SKNode?
    private var powerupBannerState: PowerupBannerState?
    private var powerupsCatalogRoot: SKNode?
    private var catalogScrollContent: SKNode?
    private var catalogScrollOffset: CGFloat = 0
    private var catalogScrollMaxOffset: CGFloat = 0
    private var catalogScrollDrag: (startSceneY: CGFloat, startOffset: CGFloat)?
    private var swapConfirmRoot: SKNode?
    private var pendingSwapOffer: (seat: LudoSeat, tokenId: Int, showBanner: Bool)?
    private let trapLayer = SKNode()
    private var trapBoardMarkers: [SKNode] = []
    private var trapPlacementHighlightNodes: [SKNode] = []
    private var trapPlacementRoot: SKNode?
    private var trapPlacementContext: (seat: LudoSeat, tokenId: Int, showBanner: Bool)?
    private var blackholeBoardMarkers: [SKNode] = []
    private var blackholeWarningNodes: [SKNode] = []
    private var blackholePlacementHighlightNodes: [SKNode] = []
    private var blackholePlacementRoot: SKNode?
    private var blackholePlacementContext: (seat: LudoSeat, tokenId: Int, showBanner: Bool)?
    private var freezeSelectionRoot: SKNode?
    private var freezeSelectionContext: (applierSeat: LudoSeat, applierTokenId: Int, showBanner: Bool)?
    private var shieldSelectionRoot: SKNode?
    private var shieldSelectionContext: (applierSeat: LudoSeat, applierTokenId: Int, showBanner: Bool)?

    private struct PowerupBannerState {
        let moverSeat: LudoSeat
        let rarity: LudoPowerupRarity
        let powerup: LudoPowerup?
        let outcomeMessage: String
    }

    #if DEBUG
    private var debugPanelRoot: SKNode?
    private var debugStagedRoll: Int?
    private var debugStagedLabel: SKLabelNode?
    private var debugStatusLabel: SKLabelNode?
    private var debugPwrStatusLabel: SKLabelNode?
    private var debugSheet: SKShapeNode?
    private var debugPageDice: SKNode?
    private var debugPagePowerups: SKNode?
    private var debugSubTab: DebugSubTab = .dice
    private var debugSelectedPowerup: LudoPowerup = .dash
    private var debugTargetSeat: LudoSeat = .green
    private var debugTargetTokenId: Int = 0
    private var debugPowerupArmTap = false
    /// Freeze / shield arm step 1: tap your own token (mystery lander), then normal target selection.
    private var debugArmAwaitingMysteryToken = false

    private enum DebugSubTab {
        case dice
        case powerups
    }
    #endif

    override init(size: CGSize) {
        self.playerCount = 4
        self.engine = LudoPassAndPlayEngine(playerCount: 4)
        super.init(size: size)
        commonInit()
    }

    init(size: CGSize, playerCount: Int) {
        let n = min(4, max(2, playerCount))
        self.playerCount = n
        self.engine = LudoPassAndPlayEngine(playerCount: n)
        super.init(size: size)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        self.playerCount = 4
        self.engine = LudoPassAndPlayEngine(playerCount: 4)
        super.init(coder: aDecoder)
        commonInit()
    }

    private func commonInit() {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.1, green: 0.16, blue: 0.2, alpha: 1)
    }

    override func didMove(to view: SKView) {
        #if DEBUG
        debugPanelRoot?.removeFromParent()
        debugPanelRoot = nil
        debugPowerupArmTap = false
        debugArmAwaitingMysteryToken = false
        #endif
        removeAllChildren()
        gameOverLayer = nil
        powerupRevealRoot = nil
        powerupBannerState = nil
        powerupsCatalogRoot = nil
        dismissSwapConfirmation()
        dismissTrapPlacementMode()
        dismissBlackholePlacementMode()
        dismissFreezeSelectionMode()
        dismissShieldSelectionMode()
        strengthHudLabel = nil
        partyHudDock = nil
        diceGlowNode = nil
        boardContainer.removeAllChildren()
        hudContainer.removeAllChildren()
        diceContainer.removeAllChildren()

        sceneBackdrop?.removeFromParent()
        let backdrop = LudoBoardJuice.makeSceneBackdrop(size: size)
        insertChild(backdrop, at: 0)
        sceneBackdrop = backdrop

        addChild(boardContainer)
        addChild(hudContainer)
        addChild(diceContainer)
        addChild(menuContainer)
        hudContainer.zPosition = 100
        diceContainer.zPosition = 101
        menuContainer.zPosition = 102

        layoutBoard()
        layoutModeHUD()
        setupHudLabelsIfNeeded()
        setupDiceIfNeeded()
        layoutDice()
        setupMenuIfNeeded()
        setupPowerupsTabIfNeeded()
        #if DEBUG
        setupDebugTabIfNeeded()
        #endif
        layoutMenu()
        setupStrengthHudIfNeeded()
        refreshStrengthHud()
        syncTokenPositionsFromEngine()
        refreshTokenVisuals()

        if engine.isGameOver {
            presentGameOverOverlay(placementLines: engine.gameOverSummaryLines())
        }

        if !didResolveOpening {
            didResolveOpening = true
            let outcome = engine.resolveOpening()
            pendingOpeningOutcome = outcome
            if outcome.rounds.isEmpty {
                openingAnimationRunning = false
                finishOpeningBanner()
            } else {
                openingAnimationRunning = true
                turnLabel?.text = "Opening rolls…"
                hintLabel?.text = ""
                chainOpeningRoll(roundIndex: 0, rollIndex: 0)
            }
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutBoard()
        layoutModeHUD()
        layoutHudLabels()
        layoutDice()
        layoutMenu()
        relayoutPowerupsCatalogIfNeeded()
        #if DEBUG
        if debugPanelRoot != nil { presentDebugPanel() }
        #endif
        relayoutPowerupBannerIfNeeded()
        relayoutSwapConfirmationIfNeeded()
        relayoutTrapPlacementIfNeeded()
        relayoutBlackholePlacementIfNeeded()
        relayoutGameOverOverlayIfNeeded()
        layoutStrengthHud()
        syncTokenPositionsFromEngine()
        syncTrapBoardMarkersFromEngine()
        syncBlackholeBoardMarkersFromEngine()
    }

    private func layoutBoard() {
        boardContainer.removeAllChildren()
        mysteryMarkerBySeat.removeAll()
        mysteryLayer.removeAllChildren()
        tokenNodes = LudoBoardBuilder.buildBoard(in: boardContainer, playerCount: playerCount)
        mysteryLayer.name = "mysteryLayer"
        // Under tokens (z 12 in `LudoBoardBuilder`) but over track tiles so “?” stays visible on empty cells.
        mysteryLayer.zPosition = 11
        if let boardRoot = boardContainer.childNode(withName: "ludoBoard") {
            boardRoot.addChild(mysteryLayer)
        } else {
            boardContainer.addChild(mysteryLayer)
        }
        reconcileMysteryCellsWithActivePlayersIfNeeded()
        rebuildMysteryMarkers(animated: false)

        trapLayer.removeAllChildren()
        trapLayer.name = "trapLayer"
        trapLayer.zPosition = 11.5
        trapBoardMarkers.removeAll()
        if let boardRoot = boardContainer.childNode(withName: "ludoBoard") {
            boardRoot.addChild(trapLayer)
        } else {
            boardContainer.addChild(trapLayer)
        }
        syncTrapBoardMarkersFromEngine()
        syncBlackholeBoardMarkersFromEngine()

        let boardSpanPoints = LudoBoardBuilder.worldBoardSpan
        let s = min(size.width, size.height) * 0.97 / boardSpanPoints
        boardContainer.setScale(s)

        if let boardRoot = boardContainer.childNode(withName: "ludoBoard") {
            juiceParticlesLayer?.removeFromParent()
            let particles = SKNode()
            particles.name = "juiceParticles"
            particles.zPosition = 13
            boardRoot.addChild(particles)
            juiceParticlesLayer = particles
            LudoBoardJuice.installBoardAmbient(on: boardRoot)
            for (seat, nodes) in tokenNodes {
                for node in nodes {
                    LudoBoardJuice.styleToyToken(node, fill: seat.tokenFill, stroke: seat.tokenStroke)
                }
            }
        }
    }

    // MARK: - Mystery “?” tiles (one per colour on the white track arm, always four sides)

    private func reconcileMysteryCellsWithActivePlayersIfNeeded() {
        for seat in LudoSeat.allCases {
            let cells = LudoBoardPath.mysteryWhiteTrackCells(for: seat)
            guard !cells.isEmpty else { continue }
            if let existing = mysteryCellBySeat[seat], cells.contains(existing) { continue }
            mysteryCellBySeat[seat] = cells.randomElement()!
        }
    }

    private func randomizeMysteryCellsOnAllSides() {
        var used = Set<GridCoord>()
        for seat in LudoSeat.allCases {
            let pool = LudoBoardPath.mysteryWhiteTrackCells(for: seat).filter { !used.contains($0) }
            guard let pick = pool.randomElement() else { continue }
            mysteryCellBySeat[seat] = pick
            used.insert(pick)
        }
    }

    private func makeMysteryMarker() -> SKNode {
        let root = SKNode()
        let bg = SKShapeNode(rectOf: CGSize(width: 22, height: 22), cornerRadius: 5)
        bg.fillColor = SKColor(red: 0.72, green: 0.38, blue: 0.95, alpha: 0.94)
        bg.strokeColor = SKColor(white: 0.15, alpha: 0.88)
        bg.lineWidth = 1.2
        root.addChild(bg)
        let q = SKLabelNode(fontNamed: "AvenirNext-Bold")
        q.text = "?"
        q.fontSize = 15
        q.fontColor = SKColor(white: 1, alpha: 0.98)
        q.verticalAlignmentMode = .center
        q.horizontalAlignmentMode = .center
        root.addChild(q)
        LudoBoardJuice.decorateMysteryMarker(root)
        return root
    }

    private func rebuildMysteryMarkers(animated: Bool) {
        for seat in LudoSeat.allCases {
            if mysteryMarkerBySeat[seat] == nil {
                let node = makeMysteryMarker()
                node.name = "mystery_\(seat.rawValue)"
                mysteryLayer.addChild(node)
                mysteryMarkerBySeat[seat] = node
            }
            guard let cell = mysteryCellBySeat[seat], let node = mysteryMarkerBySeat[seat] else { continue }
            let target = LudoBoardBuilder.boardPoint(row: cell.row, col: cell.col)
            node.removeAllActions()
            if animated {
                let d = 0.28
                node.run(SKAction.move(to: target, duration: d))
            } else {
                node.position = target
            }
        }
    }

    /// Mystery tiles re-roll only once per full pass-and-play **round**, **after** token motion (or a short delay if no pieces moved). `afterTokenMotionCompletes` is true when called from `syncTokenPositionsFromEngine(animated:)` completion; false after e.g. pass-without-move.
    private func scheduleMysteryTileShuffleIfRoundWrapped(previousRoller: LudoSeat, afterTokenMotionCompletes: Bool) {
        guard gameOverLayer == nil, !engine.isGameOver else { return }
        let order = engine.activeSeatsOrdered
        guard let fromIdx = order.firstIndex(of: previousRoller),
              let toIdx = order.firstIndex(of: engine.currentSeat),
              toIdx < fromIdx else { return }

        let runShuffle = { [weak self] in
            guard let self, self.gameOverLayer == nil else { return }
            self.randomizeMysteryCellsOnAllSides()
            self.rebuildMysteryMarkers(animated: true)
        }

        if afterTokenMotionCompletes {
            runShuffle()
        } else {
            run(SKAction.sequence([
                SKAction.wait(forDuration: 0.22),
                SKAction.run(runShuffle),
            ]))
        }
    }

    /// After piece movement: optional mystery reward (consumes `engine.lastAppliedMove`), then round-end mystery shuffle.
    private func onMoveAnimationsCompleted(previousRoller: LudoSeat) {
        checkMysteryPickupAndPresentPowerupIfNeeded(roller: previousRoller)
        refreshBoardHazardsIfFullRoundWrapped(previousRoller: previousRoller)
        scheduleMysteryTileShuffleIfRoundWrapped(previousRoller: previousRoller, afterTokenMotionCompletes: true)
    }

    /// Rebuild trap/blackhole markers so round counters match engine state (ticks happen in `advanceToNextSeat`).
    private func refreshBoardHazardsFromEngine() {
        syncTrapBoardMarkersFromEngine()
        syncBlackholeBoardMarkersFromEngine()
    }

    private func didFullRoundWrap(from previousRoller: LudoSeat) -> Bool {
        let order = engine.activeSeatsOrdered
        guard let fromIdx = order.firstIndex(of: previousRoller),
              let toIdx = order.firstIndex(of: engine.currentSeat) else { return false }
        return toIdx < fromIdx
    }

    private func refreshBoardHazardsIfFullRoundWrapped(previousRoller: LudoSeat) {
        guard didFullRoundWrap(from: previousRoller) else { return }
        refreshBoardHazardsFromEngine()
    }

    private func afterTurnEndedWithoutExtraRoll(grantsExtraRoll: Bool) {
        guard !grantsExtraRoll else { return }
        refreshBoardHazardsFromEngine()
    }

    private func checkMysteryPickupAndPresentPowerupIfNeeded(roller: LudoSeat) {
        guard gameOverLayer == nil else {
            _ = engine.consumeLastAppliedMove()
            return
        }
        guard let move = engine.consumeLastAppliedMove(), move.seat == roller else { return }
        guard let spot = engine.spot(for: move.seat, tokenId: move.tokenId),
              let g = LudoBoardPath.gridCoord(for: move.seat, tokenId: move.tokenId, spot: spot) else { return }
        let mysteryCoords = Set(mysteryCellBySeat.values)
        guard mysteryCoords.contains(g) else { return }

        let active = LudoSeat.activeSeats(forPlayerCount: playerCount)
        let gap = LudoStrengthScoring.gapToLeader(for: move.seat, tokens: engine.tokens, activeSeats: active)
        let rarity = LudoPowerupDecider.rollRarity(scoreGapToLeader: gap)
        let powerup = LudoPowerupDecider.rollPowerup(for: rarity)

        let mysteryPt = LudoBoardBuilder.boardPoint(row: g.row, col: g.col)
        if let juiceParent = juiceParticlesLayer {
            LudoBoardJuice.spawnSparkles(
                at: mysteryPt,
                in: juiceParent,
                colors: [
                    SKColor(red: 0.85, green: 0.4, blue: 1, alpha: 1),
                    SKColor(red: 1, green: 0.9, blue: 0.35, alpha: 1),
                    SKColor(red: 0.45, green: 0.95, blue: 0.75, alpha: 1),
                ],
                count: 16
            )
            LudoBoardJuice.shake(boardContainer, intensity: 3.5)
        }

        if let powerup {
            offerPowerup(powerup, seat: move.seat, tokenId: move.tokenId, showBanner: true)
        } else {
            presentPowerupBanner(
                moverSeat: move.seat,
                rarity: rarity,
                powerup: nil,
                outcomeMessage: "No powerup in pool for \(rarity.displayTitle) yet."
            )
        }
    }

    private func outcomeMessage(from outcome: LudoPowerupApplyOutcome) -> String {
        switch outcome {
        case .applied(let message), .noEffect(let message), .gameOver(_, let message),
             .awaitingTrapPlacement(let message), .awaitingBlackholePlacement(let message),
             .awaitingFreezeTarget(let message),
             .awaitingSmallShieldTarget(let message):
            return message
        }
    }

    private func offerPowerup(_ powerup: LudoPowerup, seat: LudoSeat, tokenId: Int, showBanner: Bool = true) {
        if powerup == .swap {
            pendingSwapOffer = (seat, tokenId, showBanner)
            presentSwapConfirmation(seat: seat, tokenId: tokenId)
            return
        }
        if powerup == .trap {
            let outcome = engine.applyPowerup(.trap, seat: seat, tokenId: tokenId)
            handleTrapPowerupOfferOutcome(outcome, seat: seat, tokenId: tokenId, showBanner: showBanner)
            return
        }
        if powerup == .blackhole {
            let outcome = engine.applyPowerup(.blackhole, seat: seat, tokenId: tokenId)
            handleBlackholePowerupOfferOutcome(outcome, seat: seat, tokenId: tokenId, showBanner: showBanner)
            return
        }
        if powerup == .freezeToken {
            let outcome = engine.applyPowerup(.freezeToken, seat: seat, tokenId: tokenId)
            handleFreezePowerupOfferOutcome(outcome, applierSeat: seat, applierTokenId: tokenId, showBanner: showBanner)
            return
        }
        if powerup == .smallShield {
            let outcome = engine.applyPowerup(.smallShield, seat: seat, tokenId: tokenId)
            handleSmallShieldPowerupOfferOutcome(outcome, applierSeat: seat, applierTokenId: tokenId, showBanner: showBanner)
            return
        }
        runPowerupTest(powerup, seat: seat, tokenId: tokenId, showBanner: showBanner)
    }

    private func handleFreezePowerupOfferOutcome(
        _ outcome: LudoPowerupApplyOutcome,
        applierSeat: LudoSeat,
        applierTokenId: Int,
        showBanner: Bool
    ) {
        switch outcome {
        case .awaitingFreezeTarget(let message):
            turnLabel?.text = message
            beginFreezeSelectionMode(applierSeat: applierSeat, applierTokenId: applierTokenId, showBanner: showBanner)
        default:
            if showBanner {
                presentPowerupBanner(
                    moverSeat: applierSeat,
                    rarity: LudoPowerup.freezeToken.rarity,
                    powerup: .freezeToken,
                    outcomeMessage: outcomeMessage(from: outcome)
                )
            }
            handlePowerupOutcome(outcome)
        }
    }

    private func handleTrapPowerupOfferOutcome(
        _ outcome: LudoPowerupApplyOutcome,
        seat: LudoSeat,
        tokenId: Int,
        showBanner: Bool
    ) {
        switch outcome {
        case .awaitingTrapPlacement(let message):
            turnLabel?.text = message
            beginTrapPlacementMode(seat: seat, tokenId: tokenId, showBanner: showBanner)
        default:
            if showBanner {
                presentPowerupBanner(
                    moverSeat: seat,
                    rarity: .common,
                    powerup: .trap,
                    outcomeMessage: outcomeMessage(from: outcome)
                )
            }
            handlePowerupOutcome(outcome)
        }
    }

    private func handleBlackholePowerupOfferOutcome(
        _ outcome: LudoPowerupApplyOutcome,
        seat: LudoSeat,
        tokenId: Int,
        showBanner: Bool
    ) {
        switch outcome {
        case .awaitingBlackholePlacement(let message):
            turnLabel?.text = message
            beginBlackholePlacementMode(seat: seat, tokenId: tokenId, showBanner: showBanner)
        default:
            if showBanner {
                presentPowerupBanner(
                    moverSeat: seat,
                    rarity: LudoPowerup.blackhole.rarity,
                    powerup: .blackhole,
                    outcomeMessage: outcomeMessage(from: outcome)
                )
            }
            handlePowerupOutcome(outcome)
        }
    }

    private func runPowerupTest(_ powerup: LudoPowerup, seat: LudoSeat, tokenId: Int, showBanner: Bool = true) {
        let outcome = engine.applyPowerup(powerup, seat: seat, tokenId: tokenId)
        if showBanner {
            presentPowerupBanner(
                moverSeat: seat,
                rarity: powerup.rarity,
                powerup: powerup,
                outcomeMessage: outcomeMessage(from: outcome)
            )
        }
        handlePowerupOutcome(outcome)
    }

    private func handlePowerupOutcome(_ outcome: LudoPowerupApplyOutcome) {
        switch outcome {
        case .awaitingTrapPlacement, .awaitingBlackholePlacement, .awaitingFreezeTarget, .awaitingSmallShieldTarget:
            break
        case .applied(let message), .noEffect(let message):
            #if DEBUG
            debugPowerupArmTap = false
            #endif
            turnLabel?.text = message
            pendingMoveJuiceMessage = message
            let trapKill = prepareTrapMoveVisuals(for: message)
            syncTokenPositionsFromEngine(animated: true, trapKill: trapKill) { [weak self] in
                self?.finishAnimatedMoveJuice()
                self?.refreshStrengthHud()
                self?.refreshTokenVisuals()
            }
        case .gameOver(let lines, let message):
            #if DEBUG
            debugPowerupArmTap = false
            #endif
            turnLabel?.text = message
            hintLabel?.text = ""
            lastRollLabel?.text = ""
            syncTokenPositionsFromEngine(animated: true) { [weak self] in
                guard let self else { return }
                LudoBoardJuice.shake(self.boardContainer, intensity: 7, duration: 0.32)
                self.refreshStrengthHud()
                self.refreshTokenVisuals()
                if self.gameOverLayer == nil {
                    self.presentGameOverOverlay(placementLines: lines)
                }
            }
        }
        refreshStrengthHud()
        refreshBoardHazardsFromEngine()
        #if DEBUG
        refreshDebugPanel()
        #endif
    }

    // MARK: - Freeze Token target selection

    private func dismissFreezeSelectionMode() {
        freezeSelectionRoot?.removeFromParent()
        freezeSelectionRoot = nil
        freezeSelectionContext = nil
        engine.cancelFreezeSelection()
    }

    private func beginFreezeSelectionMode(applierSeat: LudoSeat, applierTokenId: Int, showBanner: Bool) {
        freezeSelectionRoot?.removeFromParent()
        freezeSelectionRoot = nil
        freezeSelectionContext = (applierSeat, applierTokenId, showBanner)
        presentFreezeSelectionPanel(applierSeat: applierSeat)
        hintLabel?.text = "Freeze — tap an opponent's token on the track"
        refreshTokenVisuals()
    }

    private func presentFreezeSelectionPanel(applierSeat: LudoSeat) {
        freezeSelectionRoot?.removeFromParent()
        let layout = powerupBannerLayout()
        let panelW = layout.panelW
        let panelH: CGFloat = 100
        let panelY = layout.panelY

        let root = SKNode()
        root.name = "freezeSelectionRoot"
        root.zPosition = 105

        let panel = SKShapeNode(rectOf: CGSize(width: panelW, height: panelH), cornerRadius: 16)
        panel.fillColor = SKColor(white: 0.12, alpha: 0.97)
        panel.strokeColor = SKColor(red: 0.45, green: 0.75, blue: 1, alpha: 0.7)
        panel.lineWidth = 1.5
        root.addChild(panel)

        let icon = LudoPowerupIcon.makeIcon(for: .freezeToken, size: 48)
        icon.position = CGPoint(x: -panelW * 0.5 + 44, y: 4)
        panel.addChild(icon)

        let title = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        title.text = "\(applierSeat.displayName) · Freeze Token"
        title.fontSize = 15
        title.fontColor = SKColor(white: 1, alpha: 0.95)
        title.verticalAlignmentMode = .center
        title.horizontalAlignmentMode = .left
        title.position = CGPoint(x: -panelW * 0.5 + 88, y: panelH * 0.5 - 26)
        panel.addChild(title)

        let prompt = SKLabelNode(fontNamed: "AvenirNext-Medium")
        prompt.text = "Tap opponent token on track · visible to all"
        prompt.fontSize = 11
        prompt.fontColor = SKColor(white: 0.78, alpha: 0.92)
        prompt.verticalAlignmentMode = .center
        prompt.horizontalAlignmentMode = .left
        prompt.position = CGPoint(x: -panelW * 0.5 + 88, y: panelH * 0.5 - 46)
        panel.addChild(prompt)

        let cancel = makeSwapConfirmButton(title: "Cancel", name: "freezeSelectionCancel", width: 88, height: 32,
                                           fill: SKColor(white: 0.28, alpha: 1))
        cancel.position = CGPoint(x: panelW * 0.5 - 56, y: -panelH * 0.5 + 26)
        panel.addChild(cancel)

        panel.position = CGPoint(x: 0, y: panelY)
        addChild(root)
        freezeSelectionRoot = root
    }

    private func confirmFreezeTarget(owner: LudoSeat, tokenId: Int) {
        guard let ctx = freezeSelectionContext else { return }
        finalizeFreezeTarget(
            owner: owner,
            tokenId: tokenId,
            applierSeat: ctx.applierSeat,
            showBanner: ctx.showBanner
        )
    }

    private func finalizeFreezeTarget(
        owner: LudoSeat,
        tokenId: Int,
        applierSeat: LudoSeat,
        showBanner: Bool
    ) {
        let outcome = engine.applyFreeze(to: owner, tokenId: tokenId, appliedBy: applierSeat)
        if case .noEffect(let msg) = outcome {
            turnLabel?.text = msg
            engine.cancelFreezeSelection()
            return
        }
        dismissFreezeSelectionMode()
        if showBanner {
            presentPowerupBanner(
                moverSeat: applierSeat,
                rarity: LudoPowerup.freezeToken.rarity,
                powerup: .freezeToken,
                outcomeMessage: outcomeMessage(from: outcome)
            )
        }
        handlePowerupOutcome(outcome)
    }

    @discardableResult
    private func handleFreezeSelectionTouch(_ touch: UITouch) -> Bool {
        guard freezeSelectionContext != nil else { return false }
        if let root = freezeSelectionRoot {
            let loc = touch.location(in: root)
            for node in root.nodes(at: loc) {
                var current: SKNode? = node
                while let c = current {
                    if c.name == "freezeSelectionCancel" {
                        let ctx = freezeSelectionContext!
                        dismissFreezeSelectionMode()
                        let msg = "\(ctx.applierSeat.displayName) cancelled Freeze Token."
                        turnLabel?.text = msg
                        if ctx.showBanner {
                            presentPowerupBanner(
                                moverSeat: ctx.applierSeat,
                                rarity: LudoPowerup.freezeToken.rarity,
                                powerup: .freezeToken,
                                outcomeMessage: msg
                            )
                        }
                        hintLabel?.text = "\(engine.currentSeat.displayName)'s turn — tap die."
                        refreshTokenVisuals()
                        return true
                    }
                    current = c.parent
                }
            }
        }
        return false
    }

    // MARK: - Small Shield target selection

    private func dismissShieldSelectionMode() {
        shieldSelectionRoot?.removeFromParent()
        shieldSelectionRoot = nil
        shieldSelectionContext = nil
        engine.cancelSmallShieldSelection()
    }

    private func beginShieldSelectionMode(applierSeat: LudoSeat, applierTokenId: Int, showBanner: Bool) {
        shieldSelectionRoot?.removeFromParent()
        shieldSelectionRoot = nil
        shieldSelectionContext = (applierSeat, applierTokenId, showBanner)
        presentShieldSelectionPanel(applierSeat: applierSeat)
        hintLabel?.text = "Small Shield — tap your token on track or home stretch"
        refreshTokenVisuals()
    }

    private func presentShieldSelectionPanel(applierSeat: LudoSeat) {
        shieldSelectionRoot?.removeFromParent()
        let layout = powerupBannerLayout()
        let panelW = layout.panelW
        let panelH: CGFloat = 100
        let panelY = layout.panelY

        let root = SKNode()
        root.name = "shieldSelectionRoot"
        root.zPosition = 105

        let panel = SKShapeNode(rectOf: CGSize(width: panelW, height: panelH), cornerRadius: 16)
        panel.fillColor = SKColor(white: 0.12, alpha: 0.97)
        panel.strokeColor = SKColor(red: 0.45, green: 0.72, blue: 1, alpha: 0.7)
        panel.lineWidth = 1.5
        root.addChild(panel)

        let icon = LudoPowerupIcon.makeIcon(for: .smallShield, size: 48)
        icon.position = CGPoint(x: -panelW * 0.5 + 44, y: 4)
        panel.addChild(icon)

        let title = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        title.text = "\(applierSeat.displayName) · Small Shield"
        title.fontSize = 15
        title.fontColor = SKColor(white: 1, alpha: 0.95)
        title.verticalAlignmentMode = .center
        title.horizontalAlignmentMode = .left
        title.position = CGPoint(x: -panelW * 0.5 + 88, y: panelH * 0.5 - 26)
        panel.addChild(title)

        let prompt = SKLabelNode(fontNamed: "AvenirNext-Medium")
        prompt.text = "Tap your token · 1-hit shield · visible to all"
        prompt.fontSize = 11
        prompt.fontColor = SKColor(white: 0.78, alpha: 0.92)
        prompt.verticalAlignmentMode = .center
        prompt.horizontalAlignmentMode = .left
        prompt.position = CGPoint(x: -panelW * 0.5 + 88, y: panelH * 0.5 - 46)
        panel.addChild(prompt)

        let cancel = makeSwapConfirmButton(title: "Cancel", name: "shieldSelectionCancel", width: 88, height: 32,
                                           fill: SKColor(white: 0.28, alpha: 1))
        cancel.position = CGPoint(x: panelW * 0.5 - 56, y: -panelH * 0.5 + 26)
        panel.addChild(cancel)

        panel.position = CGPoint(x: 0, y: panelY)
        addChild(root)
        shieldSelectionRoot = root
    }

    private func handleSmallShieldPowerupOfferOutcome(
        _ outcome: LudoPowerupApplyOutcome,
        applierSeat: LudoSeat,
        applierTokenId: Int,
        showBanner: Bool
    ) {
        switch outcome {
        case .awaitingSmallShieldTarget(let message):
            turnLabel?.text = message
            beginShieldSelectionMode(applierSeat: applierSeat, applierTokenId: applierTokenId, showBanner: showBanner)
        default:
            if showBanner {
                presentPowerupBanner(
                    moverSeat: applierSeat,
                    rarity: LudoPowerup.smallShield.rarity,
                    powerup: .smallShield,
                    outcomeMessage: outcomeMessage(from: outcome)
                )
            }
            handlePowerupOutcome(outcome)
        }
    }

    private func confirmShieldTarget(owner: LudoSeat, tokenId: Int) {
        guard let ctx = shieldSelectionContext else { return }
        finalizeShieldTarget(
            owner: owner,
            tokenId: tokenId,
            applierSeat: ctx.applierSeat,
            showBanner: ctx.showBanner
        )
    }

    private func finalizeShieldTarget(
        owner: LudoSeat,
        tokenId: Int,
        applierSeat: LudoSeat,
        showBanner: Bool
    ) {
        let outcome = engine.applySmallShield(to: owner, tokenId: tokenId, appliedBy: applierSeat)
        if case .noEffect(let msg) = outcome {
            turnLabel?.text = msg
            engine.cancelSmallShieldSelection()
            return
        }
        dismissShieldSelectionMode()
        if showBanner {
            presentPowerupBanner(
                moverSeat: applierSeat,
                rarity: LudoPowerup.smallShield.rarity,
                powerup: .smallShield,
                outcomeMessage: outcomeMessage(from: outcome)
            )
        }
        handlePowerupOutcome(outcome)
    }

    @discardableResult
    private func handleShieldSelectionTouch(_ touch: UITouch) -> Bool {
        guard shieldSelectionContext != nil else { return false }
        if let root = shieldSelectionRoot {
            let loc = touch.location(in: root)
            for node in root.nodes(at: loc) {
                var current: SKNode? = node
                while let c = current {
                    if c.name == "shieldSelectionCancel" {
                        let ctx = shieldSelectionContext!
                        dismissShieldSelectionMode()
                        let msg = "\(ctx.applierSeat.displayName) cancelled Small Shield."
                        turnLabel?.text = msg
                        if ctx.showBanner {
                            presentPowerupBanner(
                                moverSeat: ctx.applierSeat,
                                rarity: LudoPowerup.smallShield.rarity,
                                powerup: .smallShield,
                                outcomeMessage: msg
                            )
                        }
                        hintLabel?.text = "\(engine.currentSeat.displayName)'s turn — tap die."
                        refreshTokenVisuals()
                        return true
                    }
                    current = c.parent
                }
            }
        }
        return false
    }

    private func updateShieldBadge(on node: SKShapeNode, kind: LudoShieldKind?) {
        node.childNode(withName: "shieldBadge")?.removeFromParent()
        guard let kind else { return }
        let ring = SKShapeNode(circleOfRadius: 13)
        ring.name = "shieldBadge"
        switch kind {
        case .small:
            ring.strokeColor = SKColor(red: 0.55, green: 0.82, blue: 1, alpha: 1)
            ring.fillColor = SKColor(red: 0.3, green: 0.55, blue: 0.9, alpha: 0.35)
        case .big:
            ring.strokeColor = SKColor(red: 0.95, green: 0.78, blue: 0.25, alpha: 1)
            ring.fillColor = SKColor(red: 0.85, green: 0.6, blue: 0.1, alpha: 0.35)
        }
        ring.lineWidth = 3
        ring.zPosition = 2
        node.addChild(ring)
    }

    private func updateFreezeBadge(on node: SKShapeNode, show: Bool) {
        node.childNode(withName: "freezeBadge")?.removeFromParent()
        guard show else { return }
        let ring = SKShapeNode(circleOfRadius: 13)
        ring.name = "freezeBadge"
        ring.strokeColor = SKColor(red: 0.55, green: 0.88, blue: 1, alpha: 1)
        ring.fillColor = SKColor(red: 0.35, green: 0.65, blue: 0.95, alpha: 0.28)
        ring.lineWidth = 3
        ring.zPosition = 2
        node.addChild(ring)
    }

    // MARK: - Trap placement & board marker

    private func clearTrapPlacementUI() {
        trapPlacementRoot?.removeFromParent()
        trapPlacementRoot = nil
        trapPlacementContext = nil
        trapPlacementHighlightNodes.forEach { $0.removeFromParent() }
        trapPlacementHighlightNodes.removeAll()
    }

    private func dismissTrapPlacementMode() {
        clearTrapPlacementUI()
        engine.cancelTrapPlacement()
    }

    private func beginTrapPlacementMode(seat: LudoSeat, tokenId: Int, showBanner: Bool) {
        clearTrapPlacementUI()
        trapPlacementContext = (seat, tokenId, showBanner)
        rebuildTrapPlacementHighlights()
        presentTrapPlacementPanel(seat: seat)
        hintLabel?.text = "Trap — tap a highlighted track tile (Cancel to skip)"
    }

    private func relayoutTrapPlacementIfNeeded() {
        guard trapPlacementContext != nil else { return }
        let seat = trapPlacementContext!.seat
        rebuildTrapPlacementHighlights()
        presentTrapPlacementPanel(seat: seat)
    }

    private func rebuildTrapPlacementHighlights() {
        trapPlacementHighlightNodes.forEach { $0.removeFromParent() }
        trapPlacementHighlightNodes.removeAll()
        for cell in engine.validTrapPlacementCells() {
            let ring = SKShapeNode(rectOf: CGSize(width: 22, height: 22), cornerRadius: 4)
            ring.strokeColor = SKColor(red: 0.95, green: 0.35, blue: 0.2, alpha: 0.85)
            ring.fillColor = SKColor(red: 0.95, green: 0.35, blue: 0.2, alpha: 0.18)
            ring.lineWidth = 2
            ring.position = LudoBoardBuilder.boardPoint(row: cell.row, col: cell.col)
            ring.zPosition = 11.3
            trapLayer.addChild(ring)
            trapPlacementHighlightNodes.append(ring)
        }
    }

    private func presentTrapPlacementPanel(seat: LudoSeat) {
        trapPlacementRoot?.removeFromParent()
        let layout = powerupBannerLayout()
        let panelW = layout.panelW
        let panelH: CGFloat = 100
        let panelY = layout.panelY

        let root = SKNode()
        root.name = "trapPlacementRoot"
        root.zPosition = 105

        let panel = SKShapeNode(rectOf: CGSize(width: panelW, height: panelH), cornerRadius: 16)
        panel.fillColor = SKColor(white: 0.12, alpha: 0.97)
        panel.strokeColor = SKColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 0.7)
        panel.lineWidth = 1.5
        root.addChild(panel)

        let icon = LudoPowerupIcon.makeIcon(for: .trap, size: 48)
        icon.position = CGPoint(x: -panelW * 0.5 + 44, y: 4)
        panel.addChild(icon)

        let title = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        title.text = "\(seat.displayName) · Trap"
        title.fontSize = 15
        title.fontColor = SKColor(white: 1, alpha: 0.95)
        title.verticalAlignmentMode = .center
        title.horizontalAlignmentMode = .left
        title.position = CGPoint(x: -panelW * 0.5 + 88, y: panelH * 0.5 - 28)
        panel.addChild(title)

        let prompt = SKLabelNode(fontNamed: "AvenirNext-Medium")
        prompt.text = "Tap a white track tile · lasts 3 full rounds"
        prompt.fontSize = 11
        prompt.fontColor = SKColor(white: 0.78, alpha: 0.92)
        prompt.verticalAlignmentMode = .center
        prompt.horizontalAlignmentMode = .left
        prompt.position = CGPoint(x: -panelW * 0.5 + 88, y: panelH * 0.5 - 48)
        panel.addChild(prompt)

        let cancel = makeSwapConfirmButton(title: "Cancel", name: "trapPlacementCancel", width: 88, height: 32,
                                           fill: SKColor(white: 0.28, alpha: 1))
        cancel.position = CGPoint(x: panelW * 0.5 - 56, y: -panelH * 0.5 + 26)
        panel.addChild(cancel)

        panel.position = CGPoint(x: 0, y: panelY)
        addChild(root)
        trapPlacementRoot = root
    }

    private func syncTrapBoardMarkersFromEngine() {
        trapBoardMarkers.forEach { $0.removeFromParent() }
        trapBoardMarkers.removeAll()
        for trap in engine.activeTraps {
            let marker = makeTrapBoardMarker(fullRoundsRemaining: trap.fullRoundsRemaining)
            marker.position = LudoBoardBuilder.boardPoint(row: trap.cell.row, col: trap.cell.col)
            trapLayer.addChild(marker)
            trapBoardMarkers.append(marker)
        }
    }

    private func makeTrapBoardMarker(fullRoundsRemaining: Int) -> SKNode {
        let root = SKNode()
        root.name = "trapBoardMarker"

        let base = SKShapeNode(rectOf: CGSize(width: 24, height: 24), cornerRadius: 3)
        base.fillColor = SKColor(red: 0.55, green: 0.12, blue: 0.1, alpha: 0.55)
        base.strokeColor = SKColor(red: 1, green: 0.45, blue: 0.2, alpha: 0.95)
        base.lineWidth = 2
        root.addChild(base)

        for i in 0..<3 {
            let spike = SKShapeNode(path: trapSpikePath())
            spike.fillColor = SKColor(red: 0.9, green: 0.25, blue: 0.15, alpha: 1)
            spike.strokeColor = .clear
            spike.position = CGPoint(x: CGFloat(i - 1) * 7, y: 2)
            root.addChild(spike)
        }

        let badge = SKLabelNode(fontNamed: "AvenirNext-Bold")
        badge.text = "\(fullRoundsRemaining)"
        badge.fontSize = 9
        badge.fontColor = SKColor(white: 1, alpha: 0.95)
        badge.verticalAlignmentMode = .center
        badge.horizontalAlignmentMode = .center
        badge.position = CGPoint(x: 0, y: -14)
        root.addChild(badge)

        let pulse = SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.72, duration: 0.55),
            SKAction.fadeAlpha(to: 1, duration: 0.55),
        ]))
        root.run(pulse)
        LudoBoardJuice.attachGlow(
            to: base,
            color: SKColor(red: 1, green: 0.4, blue: 0.15, alpha: 1),
            size: CGSize(width: 28, height: 28),
            lineWidth: 2,
            pulse: true
        )
        return root
    }

    private func trapSpikePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 7))
        path.addLine(to: CGPoint(x: -4, y: -5))
        path.addLine(to: CGPoint(x: 4, y: -5))
        path.closeSubpath()
        return path
    }

    // MARK: - Blackhole placement & board marker

    private func clearBlackholePlacementUI() {
        blackholePlacementRoot?.removeFromParent()
        blackholePlacementRoot = nil
        blackholePlacementContext = nil
        blackholePlacementHighlightNodes.forEach { $0.removeFromParent() }
        blackholePlacementHighlightNodes.removeAll()
    }

    private func dismissBlackholePlacementMode() {
        clearBlackholePlacementUI()
        engine.cancelBlackholePlacement()
    }

    private func beginBlackholePlacementMode(seat: LudoSeat, tokenId: Int, showBanner: Bool) {
        clearBlackholePlacementUI()
        blackholePlacementContext = (seat, tokenId, showBanner)
        rebuildBlackholePlacementHighlights()
        presentBlackholePlacementPanel(seat: seat)
        hintLabel?.text = "Blackhole — tap a highlighted track tile (Cancel to skip)"
    }

    private func relayoutBlackholePlacementIfNeeded() {
        guard blackholePlacementContext != nil else { return }
        let seat = blackholePlacementContext!.seat
        rebuildBlackholePlacementHighlights()
        presentBlackholePlacementPanel(seat: seat)
    }

    private func rebuildBlackholePlacementHighlights() {
        blackholePlacementHighlightNodes.forEach { $0.removeFromParent() }
        blackholePlacementHighlightNodes.removeAll()
        for cell in engine.validBlackholePlacementCells() {
            let ring = SKShapeNode(rectOf: CGSize(width: 26, height: 26), cornerRadius: 4)
            ring.fillColor = SKColor(red: 0.45, green: 0.15, blue: 0.75, alpha: 0.28)
            ring.strokeColor = SKColor(red: 0.85, green: 0.45, blue: 1, alpha: 0.95)
            ring.lineWidth = 2
            ring.glowWidth = 2
            ring.position = LudoBoardBuilder.boardPoint(row: cell.row, col: cell.col)
            trapLayer.addChild(ring)
            blackholePlacementHighlightNodes.append(ring)
        }
    }

    private func presentBlackholePlacementPanel(seat: LudoSeat) {
        blackholePlacementRoot?.removeFromParent()
        let layout = powerupBannerLayout()
        let panelW = layout.panelW
        let panelH: CGFloat = 92
        let panelY = layout.panelY + 108

        let root = SKNode()
        root.name = "blackholePlacementRoot"
        root.zPosition = 105

        let panel = SKShapeNode(rectOf: CGSize(width: panelW, height: panelH), cornerRadius: 14)
        panel.fillColor = SKColor(red: 0.14, green: 0.08, blue: 0.22, alpha: 0.97)
        panel.strokeColor = SKColor(red: 0.72, green: 0.35, blue: 1, alpha: 0.75)
        panel.lineWidth = 1.5
        root.addChild(panel)

        let icon = LudoPowerupIcon.makeIcon(for: .blackhole, size: 48)
        icon.position = CGPoint(x: -panelW * 0.5 + 44, y: 0)
        panel.addChild(icon)

        let title = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        title.text = "\(seat.displayName) · Blackhole"
        title.fontSize = 16
        title.fontColor = SKColor(red: 0.9, green: 0.75, blue: 1, alpha: 1)
        title.verticalAlignmentMode = .center
        title.horizontalAlignmentMode = .left
        title.position = CGPoint(x: -panelW * 0.5 + 78, y: 10)
        panel.addChild(title)

        let sub = SKLabelNode(fontNamed: "AvenirNext-Medium")
        sub.text = "Tap a highlighted tile · lasts \(LudoActiveBlackhole.maxFullRounds) full rounds"
        sub.fontSize = 11
        sub.fontColor = SKColor(white: 0.8, alpha: 0.9)
        sub.verticalAlignmentMode = .center
        sub.horizontalAlignmentMode = .left
        sub.position = CGPoint(x: -panelW * 0.5 + 78, y: -12)
        panel.addChild(sub)

        let cancel = makeSwapConfirmButton(title: "Cancel", name: "blackholePlacementCancel", width: 88, height: 32,
                                           fill: SKColor(white: 0.28, alpha: 1))
        cancel.position = CGPoint(x: panelW * 0.5 - 56, y: -panelH * 0.5 + 26)
        panel.addChild(cancel)

        panel.position = CGPoint(x: 0, y: panelY)
        addChild(root)
        blackholePlacementRoot = root
    }

    private func syncBlackholeBoardMarkersFromEngine() {
        blackholeBoardMarkers.forEach { $0.removeFromParent() }
        blackholeBoardMarkers.removeAll()
        blackholeWarningNodes.forEach { $0.removeFromParent() }
        blackholeWarningNodes.removeAll()

        for hole in engine.activeBlackholes {
            let marker = makeBlackholeBoardMarker(fullRoundsRemaining: hole.fullRoundsRemaining)
            marker.position = LudoBoardBuilder.boardPoint(row: hole.cell.row, col: hole.cell.col)
            trapLayer.addChild(marker)
            blackholeBoardMarkers.append(marker)
        }
        rebuildBlackholeWarningGlows()
    }

    private func rebuildBlackholeWarningGlows() {
        var warned = Set<GridCoord>()
        for hole in engine.activeBlackholes {
            for cell in adjacentPublicTrackCells(to: hole.cell) {
                guard !warned.contains(cell), cell != hole.cell else { continue }
                warned.insert(cell)
                let glow = SKShapeNode(rectOf: CGSize(width: 24, height: 24), cornerRadius: 3)
                glow.fillColor = SKColor(red: 0.55, green: 0.2, blue: 0.85, alpha: 0.12)
                glow.strokeColor = SKColor(red: 0.75, green: 0.35, blue: 1, alpha: 0.35)
                glow.lineWidth = 1
                glow.position = LudoBoardBuilder.boardPoint(row: cell.row, col: cell.col)
                glow.zPosition = -0.5
                let pulse = SKAction.repeatForever(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.45, duration: 0.7),
                    SKAction.fadeAlpha(to: 1, duration: 0.7),
                ]))
                glow.run(pulse)
                trapLayer.addChild(glow)
                blackholeWarningNodes.append(glow)
            }
        }
    }

    private func adjacentPublicTrackCells(to cell: GridCoord) -> [GridCoord] {
        guard let index = LudoBoardPath.publicPathIndex(of: cell) else { return [] }
        var cells: [GridCoord] = []
        let prev = (index + 1) % 52
        let next = LudoBoardPath.clockwiseNextPathIndex(from: index)
        cells.append(LudoBoardPath.publicTrack[prev])
        cells.append(LudoBoardPath.publicTrack[next])
        for dr in -1...1 {
            for dc in -1...1 where dr != 0 || dc != 0 {
                let g = GridCoord(row: cell.row + dr, col: cell.col + dc)
                if LudoBoardPath.publicPathIndex(of: g) != nil {
                    cells.append(g)
                }
            }
        }
        return Array(Set(cells))
    }

    private func makeBlackholeBoardMarker(fullRoundsRemaining: Int) -> SKNode {
        let root = SKNode()
        root.name = "blackholeBoardMarker"

        let core = SKShapeNode(circleOfRadius: 10)
        core.fillColor = SKColor(red: 0.04, green: 0.02, blue: 0.1, alpha: 0.92)
        core.strokeColor = SKColor(red: 0.75, green: 0.35, blue: 1, alpha: 0.95)
        core.lineWidth = 2
        core.glowWidth = 3
        root.addChild(core)

        let swirl = SKNode()
        for i in 0..<3 {
            let arc = SKShapeNode(circleOfRadius: 11 + CGFloat(i) * 3)
            arc.fillColor = .clear
            arc.strokeColor = SKColor(red: 0.7, green: 0.3, blue: 1, alpha: 0.55 - CGFloat(i) * 0.12)
            arc.lineWidth = 1.6
            swirl.addChild(arc)
        }
        swirl.run(SKAction.repeatForever(SKAction.rotate(byAngle: -.pi * 2, duration: 1.6)))
        root.addChild(swirl)

        let badge = SKLabelNode(fontNamed: "AvenirNext-Bold")
        badge.text = "\(fullRoundsRemaining)"
        badge.fontSize = 9
        badge.fontColor = SKColor(white: 1, alpha: 0.95)
        badge.verticalAlignmentMode = .center
        badge.horizontalAlignmentMode = .center
        badge.position = CGPoint(x: 0, y: -15)
        root.addChild(badge)

        let pulse = SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.06, duration: 0.5),
            SKAction.scale(to: 0.94, duration: 0.5),
        ]))
        root.run(pulse)
        return root
    }

    private func confirmBlackholePlacement(at cell: GridCoord) {
        guard let ctx = blackholePlacementContext else { return }
        let outcome = engine.placeBlackhole(at: cell, placedBy: ctx.seat)
        if case .noEffect(let msg) = outcome {
            turnLabel?.text = msg
            return
        }
        dismissBlackholePlacementMode()
        if ctx.showBanner {
            presentPowerupBanner(
                moverSeat: ctx.seat,
                rarity: LudoPowerup.blackhole.rarity,
                powerup: .blackhole,
                outcomeMessage: outcomeMessage(from: outcome)
            )
        }
        handlePowerupOutcome(outcome)
    }

    @discardableResult
    private func handleBlackholePlacementTouch(_ touch: UITouch) -> Bool {
        guard blackholePlacementContext != nil else { return false }
        if let root = blackholePlacementRoot {
            let loc = touch.location(in: root)
            for node in root.nodes(at: loc) {
                var current: SKNode? = node
                while let c = current {
                    if c.name == "blackholePlacementCancel" {
                        let ctx = blackholePlacementContext!
                        dismissBlackholePlacementMode()
                        let msg = "\(ctx.seat.displayName) cancelled Blackhole placement."
                        turnLabel?.text = msg
                        if ctx.showBanner {
                            presentPowerupBanner(
                                moverSeat: ctx.seat,
                                rarity: LudoPowerup.blackhole.rarity,
                                powerup: .blackhole,
                                outcomeMessage: msg
                            )
                        }
                        hintLabel?.text = "\(engine.currentSeat.displayName)'s turn — tap die."
                        return true
                    }
                    current = c.parent
                }
            }
        }
        guard let cell = gridCoordAtBoardTouch(touch) else { return true }
        confirmBlackholePlacement(at: cell)
        return true
    }

    private func gridCoordAtBoardTouch(_ touch: UITouch) -> GridCoord? {
        let loc = touch.location(in: boardContainer)
        let half = LudoBoardBuilder.worldBoardSpan / 2
        let step = LudoBoardBuilder.worldCellStep
        let col = Int(floor((loc.x + half) / step))
        let row = Int(floor((loc.y + half) / step))
        guard (0..<LudoBoardPath.gridSize).contains(row), (0..<LudoBoardPath.gridSize).contains(col) else {
            return nil
        }
        return GridCoord(row: row, col: col)
    }

    private func confirmTrapPlacement(at cell: GridCoord) {
        guard let ctx = trapPlacementContext else { return }
        let outcome = engine.placeTrap(at: cell, placedBy: ctx.seat)
        if case .noEffect(let msg) = outcome {
            turnLabel?.text = msg
            return
        }
        dismissTrapPlacementMode()
        if ctx.showBanner {
            presentPowerupBanner(
                moverSeat: ctx.seat,
                rarity: LudoPowerup.trap.rarity,
                powerup: .trap,
                outcomeMessage: outcomeMessage(from: outcome)
            )
        }
        handlePowerupOutcome(outcome)
    }

    @discardableResult
    private func handleTrapPlacementTouch(_ touch: UITouch) -> Bool {
        guard trapPlacementContext != nil else { return false }
        if let root = trapPlacementRoot {
            let loc = touch.location(in: root)
            for node in root.nodes(at: loc) {
                var current: SKNode? = node
                while let c = current {
                    if c.name == "trapPlacementCancel" {
                        let ctx = trapPlacementContext!
                        dismissTrapPlacementMode()
                        let msg = "\(ctx.seat.displayName) cancelled Trap placement."
                        turnLabel?.text = msg
                        if ctx.showBanner {
                            presentPowerupBanner(
                                moverSeat: ctx.seat,
                                rarity: LudoPowerup.trap.rarity,
                                powerup: .trap,
                                outcomeMessage: msg
                            )
                        }
                        hintLabel?.text = "\(engine.currentSeat.displayName)'s turn — tap die."
                        return true
                    }
                    current = c.parent
                }
            }
        }
        guard let cell = gridCoordAtBoardTouch(touch) else { return true }
        confirmTrapPlacement(at: cell)
        return true
    }

    private func dismissPowerupBanner() {
        powerupRevealRoot?.removeAllActions()
        powerupRevealRoot?.removeFromParent()
        powerupRevealRoot = nil
        powerupBannerState = nil
    }

    private func removeSwapConfirmationUI() {
        swapConfirmRoot?.removeAllActions()
        swapConfirmRoot?.removeFromParent()
        swapConfirmRoot = nil
    }

    private func dismissSwapConfirmation() {
        removeSwapConfirmationUI()
        pendingSwapOffer = nil
    }

    private func presentSwapConfirmation(seat: LudoSeat, tokenId: Int) {
        removeSwapConfirmationUI()
        dismissPowerupBanner()

        let layout = powerupBannerLayout()
        let panelW = layout.panelW
        let panelH: CGFloat = 108
        let panelY = layout.panelY

        let root = SKNode()
        root.name = "swapConfirmRoot"
        root.zPosition = 105

        let panel = SKShapeNode(rectOf: CGSize(width: panelW, height: panelH), cornerRadius: 16)
        panel.fillColor = SKColor(white: 0.12, alpha: 0.97)
        panel.strokeColor = SKColor(white: 0.55, alpha: 0.65)
        panel.lineWidth = 1.5
        root.addChild(panel)

        let iconSize: CGFloat = 52
        let iconX = -panelW * 0.5 + 20 + iconSize * 0.5
        let icon = LudoPowerupIcon.makeIcon(for: .swap, size: iconSize)
        icon.position = CGPoint(x: iconX, y: 6)
        panel.addChild(icon)

        let textLeft = iconX + iconSize * 0.5 + 14
        let title = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        title.text = "\(seat.displayName) · Swap"
        title.fontSize = 15
        title.fontColor = SKColor(white: 1, alpha: 0.95)
        title.verticalAlignmentMode = .center
        title.horizontalAlignmentMode = .left
        title.position = CGPoint(x: textLeft, y: panelH * 0.5 - 24)
        panel.addChild(title)

        let prompt = SKLabelNode(fontNamed: "AvenirNext-Medium")
        prompt.text = "Use this powerup on token \(tokenId + 1)?"
        prompt.fontSize = 12
        prompt.fontColor = SKColor(white: 0.78, alpha: 0.92)
        prompt.verticalAlignmentMode = .center
        prompt.horizontalAlignmentMode = .left
        prompt.position = CGPoint(x: textLeft, y: panelH * 0.5 - 46)
        panel.addChild(prompt)

        let btnW: CGFloat = 88
        let btnH: CGFloat = 36
        let yes = makeSwapConfirmButton(title: "Yes", name: "swapConfirmYes", width: btnW, height: btnH,
                                        fill: SKColor(red: 0.18, green: 0.48, blue: 0.32, alpha: 1))
        yes.position = CGPoint(x: btnW * 0.5 + 8, y: -panelH * 0.5 + 28)
        panel.addChild(yes)

        let no = makeSwapConfirmButton(title: "No", name: "swapConfirmNo", width: btnW, height: btnH,
                                       fill: SKColor(white: 0.28, alpha: 1))
        no.position = CGPoint(x: -btnW * 0.5 - 8, y: -panelH * 0.5 + 28)
        panel.addChild(no)

        panel.position = CGPoint(x: 0, y: panelY - 72)
        panel.alpha = 0
        panel.run(SKAction.group([
            SKAction.move(to: CGPoint(x: 0, y: panelY), duration: 0.28),
            SKAction.fadeIn(withDuration: 0.22),
        ]))

        addChild(root)
        swapConfirmRoot = root
        hintLabel?.text = "Swap — tap Yes or No"
    }

    private func makeSwapConfirmButton(title: String, name: String, width: CGFloat, height: CGFloat, fill: SKColor) -> SKNode {
        let n = SKNode()
        n.name = name
        let bg = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 10)
        bg.fillColor = fill
        bg.strokeColor = SKColor(white: 1, alpha: 0.35)
        bg.lineWidth = 1.2
        n.addChild(bg)
        let l = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        l.text = title
        l.fontSize = 16
        l.fontColor = SKColor(white: 1, alpha: 0.95)
        l.verticalAlignmentMode = .center
        l.horizontalAlignmentMode = .center
        n.addChild(l)
        return n
    }

    private func relayoutSwapConfirmationIfNeeded() {
        guard pendingSwapOffer != nil else { return }
        let seat = pendingSwapOffer!.seat
        let tokenId = pendingSwapOffer!.tokenId
        presentSwapConfirmation(seat: seat, tokenId: tokenId)
    }

    private func resolveSwapConfirmation(usePowerup: Bool) {
        guard let offer = pendingSwapOffer else {
            dismissSwapConfirmation()
            return
        }
        dismissSwapConfirmation()
        if usePowerup {
            runPowerupTest(.swap, seat: offer.seat, tokenId: offer.tokenId, showBanner: offer.showBanner)
        } else {
            let msg = "\(offer.seat.displayName) chose not to use Swap."
            turnLabel?.text = msg
            if offer.showBanner {
                presentPowerupBanner(
                    moverSeat: offer.seat,
                    rarity: LudoPowerup.swap.rarity,
                    powerup: .swap,
                    outcomeMessage: msg
                )
            }
            hintLabel?.text = "\(engine.currentSeat.displayName)'s turn — tap die."
        }
    }

    @discardableResult
    private func handleSwapConfirmTouch(_ touch: UITouch) -> Bool {
        guard let root = swapConfirmRoot else { return false }
        let loc = touch.location(in: root)
        for node in root.nodes(at: loc) {
            var current: SKNode? = node
            while let c = current {
                if c.name == "swapConfirmYes" {
                    resolveSwapConfirmation(usePowerup: true)
                    return true
                }
                if c.name == "swapConfirmNo" {
                    resolveSwapConfirmation(usePowerup: false)
                    return true
                }
                current = c.parent
            }
        }
        return true
    }

    private func boardBottomYInScene() -> CGFloat {
        let span = LudoBoardBuilder.worldBoardSpan * boardContainer.xScale
        return boardContainer.position.y - span * 0.5
    }

    private func powerupBannerLayout() -> (panelW: CGFloat, panelH: CGFloat, panelY: CGFloat) {
        let panelW = min(size.width - 24, max(280, size.width * 0.94))
        let panelH: CGFloat = 104
        let gapBelowBoard: CGFloat = 10
        let panelY = boardBottomYInScene() - gapBelowBoard - panelH * 0.5
        return (panelW, panelH, panelY)
    }

    /// Bottom dock under the board — same panel styling as before, no fullscreen dim.
    private func presentPowerupBanner(
        moverSeat: LudoSeat,
        rarity: LudoPowerupRarity,
        powerup: LudoPowerup?,
        outcomeMessage: String
    ) {
        powerupBannerState = PowerupBannerState(
            moverSeat: moverSeat,
            rarity: rarity,
            powerup: powerup,
            outcomeMessage: outcomeMessage
        )
        rebuildPowerupBanner(animated: true)
    }

    private func relayoutPowerupBannerIfNeeded() {
        guard powerupBannerState != nil else { return }
        rebuildPowerupBanner(animated: false)
    }

    private func rebuildPowerupBanner(animated: Bool) {
        guard let state = powerupBannerState else {
            dismissPowerupBanner()
            return
        }

        powerupRevealRoot?.removeAllActions()
        powerupRevealRoot?.removeFromParent()

        let layout = powerupBannerLayout()
        let panelW = layout.panelW
        let panelH = layout.panelH
        let panelY = layout.panelY

        let root = SKNode()
        root.name = "powerupRevealRoot"
        root.zPosition = 104

        let panel = SKShapeNode(rectOf: CGSize(width: panelW, height: panelH), cornerRadius: 16)
        panel.fillColor = SKColor(white: 0.12, alpha: 0.97)
        panel.strokeColor = SKColor(white: 0.55, alpha: 0.65)
        panel.lineWidth = 1.5
        panel.name = "powerupRevealDismiss"
        root.addChild(panel)

        let iconSize: CGFloat = 52
        let iconX = -panelW * 0.5 + 20 + iconSize * 0.5
        let iconNode: SKNode = if let powerup = state.powerup {
            LudoPowerupIcon.makeIcon(for: powerup, size: iconSize)
        } else {
            LudoPowerupIcon.makeMysteryIcon(size: iconSize)
        }
        iconNode.position = CGPoint(x: iconX, y: 0)
        panel.addChild(iconNode)
        if state.powerup != nil {
            LudoBoardJuice.attachPowerupSparkles(
                to: iconNode,
                colors: [
                    SKColor(red: 0.5, green: 0.95, blue: 0.75, alpha: 1),
                    SKColor(red: 0.85, green: 0.45, blue: 1, alpha: 1),
                    SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1),
                ]
            )
        }

        let textLeft = iconX + iconSize * 0.5 + 14
        let textRight = panelW * 0.5 - 14
        let textWidth = textRight - textLeft

        let title = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        title.text = "\(state.moverSeat.displayName) · mystery tile"
        title.fontSize = 13
        title.fontColor = SKColor(white: 1, alpha: 0.88)
        title.verticalAlignmentMode = .center
        title.horizontalAlignmentMode = .left
        title.position = CGPoint(x: textLeft, y: panelH * 0.5 - 20)
        panel.addChild(title)

        if let powerup = state.powerup {
            let nameLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
            nameLabel.text = powerup.displayName
            nameLabel.fontSize = 20
            nameLabel.fontColor = SKColor(red: 0.45, green: 0.95, blue: 0.72, alpha: 1)
            nameLabel.verticalAlignmentMode = .center
            nameLabel.horizontalAlignmentMode = .left
            nameLabel.position = CGPoint(x: textLeft, y: panelH * 0.5 - 42)
            panel.addChild(nameLabel)

            addRarityPill(
                to: panel,
                rarity: state.rarity,
                textLeft: textLeft,
                y: panelH * 0.5 - 60
            )
        } else {
            addRarityPill(
                to: panel,
                rarity: state.rarity,
                textLeft: textLeft,
                y: panelH * 0.5 - 44
            )
        }

        let sub = SKLabelNode(fontNamed: "AvenirNext-Medium")
        sub.text = state.outcomeMessage
        sub.fontSize = 11
        sub.fontColor = SKColor(white: 0.75, alpha: 0.92)
        sub.verticalAlignmentMode = .center
        sub.horizontalAlignmentMode = .left
        sub.preferredMaxLayoutWidth = max(120, textWidth)
        sub.numberOfLines = 3
        sub.position = CGPoint(x: textLeft, y: panelH * 0.5 - 82)
        panel.addChild(sub)

        let targetY = panelY
        if animated {
            panel.position = CGPoint(x: 0, y: targetY - 72)
            panel.alpha = 0
            panel.run(SKAction.group([
                SKAction.move(to: CGPoint(x: 0, y: targetY), duration: 0.28),
                SKAction.fadeIn(withDuration: 0.22),
            ]))
        } else {
            panel.position = CGPoint(x: 0, y: targetY)
            panel.alpha = 1
        }

        addChild(root)
        powerupRevealRoot = root

        root.run(
            SKAction.sequence([
                SKAction.wait(forDuration: 5),
                SKAction.run { [weak self] in self?.dismissPowerupBanner() },
            ])
        )
    }

    private func hudMessageMaxWidth() -> CGFloat {
        min(380, max(260, size.width - 36))
    }

    private func setupHudLabelsIfNeeded() {
        let maxW = hudMessageMaxWidth()
        if turnLabel == nil {
            let t = SKLabelNode(fontNamed: LudoPartyStyle.fontTitle)
            t.fontSize = 16
            t.fontColor = SKColor(white: 1, alpha: 0.95)
            t.verticalAlignmentMode = .top
            t.horizontalAlignmentMode = .center
            t.numberOfLines = 0
            t.preferredMaxLayoutWidth = maxW
            turnLabel = t
            hudContainer.addChild(t)
        }
        if hintLabel == nil {
            let h = SKLabelNode(fontNamed: LudoPartyStyle.fontBody)
            h.fontSize = 13
            h.fontColor = SKColor(white: 1, alpha: 0.72)
            h.verticalAlignmentMode = .top
            h.horizontalAlignmentMode = .center
            h.numberOfLines = 0
            h.preferredMaxLayoutWidth = maxW
            hintLabel = h
            hudContainer.addChild(h)
        }
        setupPartyHudDockIfNeeded()
        layoutHudLabels()
    }

    private func setupPartyHudDockIfNeeded() {
        guard partyHudDock == nil else { return }
        let dockW = min(size.width - 18, 420)
        let dock = LudoPartyStyle.makeHudDock(width: dockW)
        dock.zPosition = -2
        partyHudDock = dock
        hudContainer.insertChild(dock, at: 0)
    }

    private func layoutHudLabels() {
        let maxW = hudMessageMaxWidth()
        turnLabel?.preferredMaxLayoutWidth = maxW
        hintLabel?.preferredMaxLayoutWidth = maxW
        turnLabel?.position = CGPoint(x: 0, y: size.height * 0.5 - 142)
        hintLabel?.position = CGPoint(x: 0, y: size.height * 0.5 - 202)
        partyHudDock?.position = CGPoint(x: 0, y: size.height * 0.5 - 72)
    }

    private func updateTurnLabel(_ text: String) {
        setupHudLabelsIfNeeded()
        LudoPartyStyle.animatePopText(turnLabel, text: text)
    }

    private func updateHintLabel(_ text: String) {
        setupHudLabelsIfNeeded()
        LudoPartyStyle.animatePopText(hintLabel, text: text)
    }

    private static let extraRollHint = "Roll again (6, capture, or reaching HOME)."

    private func setupDiceIfNeeded() {
        if diceNode == nil {
            let die = min(74, max(52, size.width * 0.145))
            let node = LudoDiceNode(dieSize: die)
            node.name = "diceArea"
            diceNode = node
        }
        if diceNode?.parent == nil, let node = diceNode {
            diceContainer.addChild(node)
        }

        if diceGlowNode == nil, let node = diceNode {
            let r = (node.calculateAccumulatedFrame().width > 1 ? node.calculateAccumulatedFrame().width : 64) * 0.58
            diceGlowNode = LudoPartyStyle.makeDiceGlow(radius: r)
        }
        if let glow = diceGlowNode, glow.parent == nil {
            diceContainer.insertChild(glow, at: 0)
        }

        if lastRollLabel == nil {
            let label = SKLabelNode(fontNamed: LudoPartyStyle.fontBody)
            label.fontSize = 15
            label.fontColor = SKColor(white: 0.92, alpha: 0.88)
            label.text = "Tap die to roll"
            label.verticalAlignmentMode = .top
            label.horizontalAlignmentMode = .center
            lastRollLabel = label
        }
        if lastRollLabel?.parent == nil, let label = lastRollLabel {
            diceContainer.addChild(label)
        }

        if modeLabel == nil {
            let label = SKLabelNode(fontNamed: LudoPartyStyle.fontBody)
            label.fontSize = 15
            label.fontColor = SKColor(white: 1, alpha: 0.82)
            label.verticalAlignmentMode = .top
            label.horizontalAlignmentMode = .center
            modeLabel = label
        }
        if modeLabel?.parent == nil, let label = modeLabel {
            hudContainer.addChild(label)
        }
    }

    private func layoutModeHUD() {
        if playerCount == 2 {
            modeLabel?.text = "Pass and play · green vs red"
        } else {
            modeLabel?.text = "Pass and play · \(playerCount) players"
        }
        // Just under the die (die bottom ≈ top − 122), above turn / hint lines.
        modeLabel?.position = CGPoint(x: 0, y: size.height * 0.5 - 124)
    }

    private func setupMenuIfNeeded() {
        guard menuContainer.childNode(withName: "menuTap") == nil else { return }
        let w: CGFloat = 112
        let h: CGFloat = 40
        let pad = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 12)
        pad.fillColor = SKColor(white: 1, alpha: 0.14)
        pad.strokeColor = SKColor(white: 1, alpha: 0.22)
        pad.lineWidth = 1
        pad.glowWidth = 1
        pad.name = "menuTap"
        menuContainer.addChild(pad)

        let label = SKLabelNode(fontNamed: LudoPartyStyle.fontTitle)
        label.text = "Menu"
        label.fontSize = 17
        label.fontColor = SKColor(white: 1, alpha: 0.92)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.name = "menuLabel"
        menuContainer.addChild(label)
    }

    private func setupPowerupsTabIfNeeded() {
        guard menuContainer.childNode(withName: "powerupsTabTap") == nil else { return }
        let w: CGFloat = 112
        let h: CGFloat = 40
        let pad = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 12)
        pad.fillColor = SKColor(red: 0.35, green: 0.28, blue: 0.55, alpha: 0.36)
        pad.strokeColor = SKColor(red: 0.9, green: 0.86, blue: 1, alpha: 0.18)
        pad.lineWidth = 1
        pad.glowWidth = 1
        pad.position = CGPoint(x: 124, y: 0)
        pad.name = "powerupsTabTap"
        menuContainer.addChild(pad)

        let label = SKLabelNode(fontNamed: LudoPartyStyle.fontTitle)
        label.text = "Powerups"
        label.fontSize = 15
        label.fontColor = SKColor(red: 0.92, green: 0.88, blue: 1, alpha: 0.96)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 124, y: 0)
        label.name = "powerupsTabLabel"
        menuContainer.addChild(label)
    }

    private func layoutMenu() {
        let insetX: CGFloat = 16
        let insetY: CGFloat = 20
        let x = -size.width * 0.5 + insetX + 56
        let y = -size.height * 0.5 + insetY + 20
        menuContainer.position = CGPoint(x: x, y: y)
    }

    private func addRarityPill(to panel: SKNode, rarity: LudoPowerupRarity, textLeft: CGFloat, y: CGFloat) {
        let title = rarity.displayTitle
        let textW = max(48, CGFloat(title.count) * 7.5 + 18)
        let pill = SKShapeNode(rectOf: CGSize(width: textW, height: 18), cornerRadius: 6)
        pill.fillColor = rarityColor(rarity).withAlphaComponent(0.22)
        pill.strokeColor = rarityColor(rarity).withAlphaComponent(0.75)
        pill.lineWidth = 1
        pill.position = CGPoint(x: textLeft + textW * 0.5, y: y)
        panel.addChild(pill)

        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = title
        label.fontSize = 11
        label.fontColor = rarityColor(rarity)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: textLeft + textW * 0.5, y: y)
        panel.addChild(label)
    }

    private func rarityColor(_ rarity: LudoPowerupRarity) -> SKColor {
        switch rarity {
        case .common: return SKColor(red: 0.75, green: 0.82, blue: 0.78, alpha: 1)
        case .rare: return SKColor(red: 0.45, green: 0.72, blue: 1, alpha: 1)
        case .epic: return SKColor(red: 0.78, green: 0.5, blue: 1, alpha: 1)
        case .legendary: return SKColor(red: 1, green: 0.78, blue: 0.35, alpha: 1)
        case .bad: return SKColor(red: 1, green: 0.42, blue: 0.38, alpha: 1)
        }
    }

    private func dismissPowerupsCatalog() {
        powerupsCatalogRoot?.removeFromParent()
        powerupsCatalogRoot = nil
        catalogScrollContent = nil
        catalogScrollOffset = 0
        catalogScrollMaxOffset = 0
        catalogScrollDrag = nil
    }

    private func applyCatalogScrollOffset() {
        catalogScrollContent?.position.y = catalogScrollOffset
    }

    private func catalogScrollViewportContains(_ scenePoint: CGPoint) -> Bool {
        guard let crop = catalogScrollContent?.parent as? SKCropNode else { return false }
        let local = crop.convert(scenePoint, from: self)
        guard let mask = crop.maskNode as? SKShapeNode, let path = mask.path else { return false }
        return path.contains(local)
    }

    @discardableResult
    private func handleCatalogScrollBegan(_ touch: UITouch) -> Bool {
        guard catalogScrollContent != nil, catalogScrollMaxOffset > 0 else { return false }
        let loc = touch.location(in: self)
        guard catalogScrollViewportContains(loc) else { return false }
        catalogScrollDrag = (startSceneY: loc.y, startOffset: catalogScrollOffset)
        return true
    }

    @discardableResult
    private func handleCatalogScrollMoved(_ touch: UITouch) -> Bool {
        guard let drag = catalogScrollDrag else { return false }
        let loc = touch.location(in: self)
        let delta = loc.y - drag.startSceneY
        catalogScrollOffset = min(catalogScrollMaxOffset, max(0, drag.startOffset + delta))
        applyCatalogScrollOffset()
        return true
    }

    @discardableResult
    private func handleCatalogScrollEnded() -> Bool {
        guard catalogScrollDrag != nil else { return false }
        catalogScrollDrag = nil
        return true
    }

    private func togglePowerupsCatalog() {
        if powerupsCatalogRoot != nil {
            dismissPowerupsCatalog()
        } else {
            #if DEBUG
            dismissDebugPanel()
            #endif
            presentPowerupsCatalog()
        }
    }

    private func powerupCatalogRowHeight(for powerup: LudoPowerup, textWidth: CGFloat) -> CGFloat {
        let desc = powerup.effectSummary
        let charsPerLine = max(18, Int(textWidth / 6.5))
        let lineCount = max(1, (desc.count + charsPerLine - 1) / charsPerLine)
        let titleBlock: CGFloat = 24
        let descBlock = CGFloat(lineCount) * 14
        return 14 + titleBlock + 8 + descBlock + 14
    }

    private func presentPowerupsCatalog() {
        let savedOffset = catalogScrollOffset
        dismissPowerupsCatalog()
        catalogScrollOffset = savedOffset
        dismissPowerupBanner()

        let root = SKNode()
        root.name = "powerupsCatalogRoot"
        root.zPosition = 160

        let dim = SKShapeNode(rectOf: CGSize(width: size.width + 8, height: size.height + 8))
        dim.fillColor = SKColor(white: 0, alpha: 0.5)
        dim.strokeColor = .clear
        dim.name = "powerupsCatalogDismiss"
        root.addChild(dim)

        let panelW = min(360, max(300, size.width * 0.9))
        let marginH: CGFloat = 20
        let headerBlockH: CGFloat = 70
        let sectionHeaderH: CGFloat = 26
        let sectionGap: CGFloat = 10
        let footerH: CGFloat = 48
        let textWidth = panelW - marginH * 2 - 56
        let panelH = min(max(280, size.height * 0.82), size.height - 40)

        let panel = SKShapeNode(rectOf: CGSize(width: panelW, height: panelH), cornerRadius: 18)
        panel.fillColor = SKColor(white: 0.1, alpha: 0.98)
        panel.strokeColor = SKColor(white: 0.5, alpha: 0.7)
        panel.lineWidth = 1.5
        root.addChild(panel)

        let left = -panelW * 0.5 + marginH
        let textX = left + 52

        let title = SKLabelNode(fontNamed: "AvenirNext-Bold")
        title.text = "Powerups"
        title.fontSize = 24
        title.fontColor = SKColor(white: 1, alpha: 0.98)
        title.verticalAlignmentMode = .center
        title.horizontalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: panelH * 0.5 - 28)
        panel.addChild(title)

        let subtitle = SKLabelNode(fontNamed: "AvenirNext-Regular")
        subtitle.text = "Mystery tile rewards · by rarity"
        subtitle.fontSize = 12
        subtitle.fontColor = SKColor(white: 0.62, alpha: 0.92)
        subtitle.verticalAlignmentMode = .center
        subtitle.horizontalAlignmentMode = .center
        subtitle.position = CGPoint(x: 0, y: panelH * 0.5 - 50)
        panel.addChild(subtitle)

        let headerRule = SKShapeNode(rectOf: CGSize(width: panelW - marginH * 2, height: 1))
        headerRule.fillColor = SKColor(white: 1, alpha: 0.12)
        headerRule.strokeColor = .clear
        headerRule.position = CGPoint(x: 0, y: panelH * 0.5 - headerBlockH + 6)
        panel.addChild(headerRule)

        let scrollTop = panelH * 0.5 - headerBlockH
        let scrollBottom = -panelH * 0.5 + footerH
        let viewportH = scrollTop - scrollBottom
        let viewportCenterY = (scrollTop + scrollBottom) * 0.5

        let crop = SKCropNode()
        crop.name = "catalogScrollCrop"
        crop.position = CGPoint(x: 0, y: viewportCenterY)
        let mask = SKShapeNode(rectOf: CGSize(width: panelW - marginH * 2, height: viewportH))
        mask.fillColor = .white
        mask.strokeColor = .clear
        crop.maskNode = mask
        panel.addChild(crop)

        let content = SKNode()
        content.name = "catalogScrollContent"
        crop.addChild(content)
        catalogScrollContent = content

        let grouped = LudoPowerup.catalogGroupedByRarity()
        var y = viewportH * 0.5
        for (rarity, powerups) in grouped {
            let sectionY = y - sectionHeaderH * 0.5
            let header = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            header.text = rarity.displayTitle
            header.fontSize = 12
            header.fontColor = rarityColor(rarity)
            header.verticalAlignmentMode = .center
            header.horizontalAlignmentMode = .left
            header.position = CGPoint(x: left, y: sectionY)
            content.addChild(header)
            y -= sectionHeaderH + sectionGap

            for p in powerups {
                let rowH = powerupCatalogRowHeight(for: p, textWidth: textWidth)
                let rowTop = y
                let rowCenter = y - rowH * 0.5

                let rowBg = SKShapeNode(rectOf: CGSize(width: panelW - marginH * 2, height: rowH - 4), cornerRadius: 10)
                rowBg.fillColor = SKColor(white: 1, alpha: 0.04)
                rowBg.strokeColor = SKColor(white: 1, alpha: 0.08)
                rowBg.lineWidth = 1
                rowBg.position = CGPoint(x: 0, y: rowCenter)
                content.addChild(rowBg)

                let rowIcon = LudoPowerupIcon.makeIcon(for: p, size: 40)
                rowIcon.position = CGPoint(x: left + 22, y: rowCenter)
                content.addChild(rowIcon)

                let nameY = rowTop - 18
                let name = SKLabelNode(fontNamed: "AvenirNext-Bold")
                name.text = p.displayName
                name.fontSize = 16
                name.fontColor = SKColor(white: 1, alpha: 0.96)
                name.verticalAlignmentMode = .center
                name.horizontalAlignmentMode = .left
                name.position = CGPoint(x: textX, y: nameY)
                content.addChild(name)

                if !p.isImplemented {
                    let soon = SKLabelNode(fontNamed: "AvenirNext-Medium")
                    soon.text = "Coming soon"
                    soon.fontSize = 10
                    soon.fontColor = SKColor(white: 0.5, alpha: 0.88)
                    soon.verticalAlignmentMode = .center
                    soon.horizontalAlignmentMode = .right
                    soon.position = CGPoint(x: panelW * 0.5 - marginH, y: nameY)
                    content.addChild(soon)
                }

                let body = SKLabelNode(fontNamed: "AvenirNext-Regular")
                body.text = p.effectSummary
                body.fontSize = 11
                body.fontColor = SKColor(white: 0.72, alpha: 0.94)
                body.verticalAlignmentMode = .top
                body.horizontalAlignmentMode = .left
                body.preferredMaxLayoutWidth = textWidth
                body.numberOfLines = 0
                body.position = CGPoint(x: textX, y: nameY - 20)
                content.addChild(body)

                y -= rowH
            }
            y -= 4
        }

        let contentH = viewportH * 0.5 - y + 8
        catalogScrollMaxOffset = max(0, contentH - viewportH)
        catalogScrollOffset = min(catalogScrollOffset, catalogScrollMaxOffset)
        applyCatalogScrollOffset()

        if catalogScrollMaxOffset > 0 {
            let hint = SKLabelNode(fontNamed: "AvenirNext-Regular")
            hint.text = "Scroll for more"
            hint.fontSize = 10
            hint.fontColor = SKColor(white: 0.45, alpha: 0.85)
            hint.verticalAlignmentMode = .center
            hint.horizontalAlignmentMode = .center
            hint.position = CGPoint(x: 0, y: scrollBottom + 10)
            panel.addChild(hint)
        }

        let closeW: CGFloat = 120
        let closeH: CGFloat = 34
        let closeBg = SKShapeNode(rectOf: CGSize(width: closeW, height: closeH), cornerRadius: closeH * 0.5)
        closeBg.fillColor = SKColor(red: 0.2, green: 0.38, blue: 0.55, alpha: 1)
        closeBg.strokeColor = SKColor(red: 0.45, green: 0.7, blue: 1, alpha: 0.85)
        closeBg.lineWidth = 1.2
        closeBg.position = CGPoint(x: 0, y: -panelH * 0.5 + footerH * 0.5)
        closeBg.name = "powerupsCatalogDismiss"
        panel.addChild(closeBg)

        let close = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        close.text = "Close"
        close.fontSize = 15
        close.fontColor = SKColor(white: 1, alpha: 0.96)
        close.verticalAlignmentMode = .center
        close.horizontalAlignmentMode = .center
        close.position = CGPoint(x: 0, y: -panelH * 0.5 + footerH * 0.5)
        close.name = "powerupsCatalogDismiss"
        panel.addChild(close)

        addChild(root)
        powerupsCatalogRoot = root
    }

    private func relayoutPowerupsCatalogIfNeeded() {
        guard powerupsCatalogRoot != nil else { return }
        presentPowerupsCatalog()
    }

    // MARK: - Strength score HUD (provisional — hide later)

    private func setupStrengthHudIfNeeded() {
        if strengthHudLabel != nil { return }
        let l = SKLabelNode(fontNamed: "AvenirNext-Medium")
        l.fontSize = 12
        l.fontColor = SKColor(white: 1, alpha: 0.9)
        l.verticalAlignmentMode = .top
        l.horizontalAlignmentMode = .center
        l.numberOfLines = 0
        l.text = ""
        strengthHudLabel = l
        l.zPosition = 99
        addChild(l)
    }

    private func layoutStrengthHud() {
        guard let l = strengthHudLabel else { return }
        l.preferredMaxLayoutWidth = max(240, size.width - 48)
        l.position = CGPoint(x: 0, y: -size.height * 0.5 + 72)
    }

    private func refreshStrengthHud() {
        setupStrengthHudIfNeeded()
        let active = LudoSeat.activeSeats(forPlayerCount: playerCount)
        let pairs = LudoStrengthScoring.strengthScoresAll(tokens: engine.tokens, activeSeats: active)
        let maxScore = pairs.map(\.score).max() ?? 0
        let parts = pairs.map { pair in
            let gap = max(0, maxScore - pair.score)
            return "\(pair.seat.displayName) \(pair.score) (gap \(gap))"
        }
        strengthHudLabel?.text = "Strength  " + parts.joined(separator: "   ·   ")
        layoutStrengthHud()
    }

    private func layoutDice() {
        setupDiceIfNeeded()
        guard diceNode != nil else { return }

        let top = size.height * 0.5 - 34
        lastRollLabel?.position = CGPoint(x: 0, y: top)
        lastRollLabel?.verticalAlignmentMode = .top
        diceNode?.position = CGPoint(x: 0, y: top - 56)
        diceGlowNode?.position = diceNode?.position ?? .zero
    }

    // MARK: - Opening

    private func chainOpeningRoll(roundIndex: Int, rollIndex: Int) {
        guard let outcome = pendingOpeningOutcome else {
            finishOpeningBanner()
            return
        }
        if roundIndex >= outcome.rounds.count {
            finishOpeningBanner()
            return
        }
        let rolls = outcome.rounds[roundIndex].rolls
        if rollIndex >= rolls.count {
            chainOpeningRoll(roundIndex: roundIndex + 1, rollIndex: 0)
            return
        }
        let seat = rolls[rollIndex].seat
        let value = rolls[rollIndex].value
        turnLabel?.text = "\(seat.displayName) rolls \(value)."
        diceNode?.revealRoll(to: value) { [weak self] in
            guard let self else { return }
            self.run(
                SKAction.sequence([
                    SKAction.wait(forDuration: 0.4),
                    SKAction.run { [weak self] in
                        self?.chainOpeningRoll(roundIndex: roundIndex, rollIndex: rollIndex + 1)
                    },
                ])
            )
        }
    }

    private func finishOpeningBanner() {
        openingAnimationRunning = false
        guard let outcome = pendingOpeningOutcome else {
            turnLabel?.text = "Roll the die."
            hintLabel?.text = ""
            refreshStrengthHud()
            return
        }
        pendingOpeningOutcome = nil
        let fp = outcome.firstPlayer
        turnLabel?.text = "\(fp.displayName) starts!"
        hintLabel?.text = ""
        lastRollLabel?.text = "\(fp.displayName)'s turn — tap die"
        #if DEBUG
        refreshDebugPanel()
        #endif
        refreshStrengthHud()
    }

    // MARK: - Gameplay

    private func canAcceptGameplayRoll(allowWhileDebugPanelOpen: Bool = false) -> Bool {
        guard gameOverLayer == nil, powerupsCatalogRoot == nil, swapConfirmRoot == nil,
              trapPlacementContext == nil, blackholePlacementContext == nil,
              freezeSelectionContext == nil,
              shieldSelectionContext == nil else { return false }
        #if DEBUG
        if !allowWhileDebugPanelOpen, debugPanelRoot != nil { return false }
        #endif
        return !openingAnimationRunning
            && !gameplayRollInFlight
            && engine.pendingChoice == nil
    }

    private func canAcceptDiceRoll() -> Bool {
        canAcceptGameplayRoll(allowWhileDebugPanelOpen: false)
    }

    private func handleGameplayRoll(_ value: Int) {
        engine.syncCurrentSeatSkippingFinishedPlayers()
        let roller = engine.currentSeat
        let outcome = engine.applyGameplayRoll(value)
        lastRollLabel?.text = "Rolled \(value)"
        switch outcome {
        case .passedNoMove(let msg):
            turnLabel?.text = msg
            hintLabel?.text = "\(engine.currentSeat.displayName)'s turn — tap die."
            afterTurnEndedWithoutExtraRoll(grantsExtraRoll: false)
            scheduleMysteryTileShuffleIfRoundWrapped(previousRoller: roller, afterTokenMotionCompletes: false)
        case .needsTokenChoice(let roll, let yard, let track, let home):
            turnLabel?.text = "\(engine.currentSeat.displayName) rolled \(roll). Pick a token."
            if !yard.isEmpty {
                hintLabel?.text = "Six: choose a yard piece, or another highlighted piece."
            } else if !track.isEmpty, !home.isEmpty {
                hintLabel?.text = "Tap track or home stretch — home moves cannot overshoot HOME."
            } else if !home.isEmpty {
                hintLabel?.text = "Tap a highlighted home-stretch piece (exact or short only)."
            } else {
                hintLabel?.text = "Tap a piece on the track to move \(roll) steps clockwise."
            }
            refreshTokenVisuals()
        case .autoApplied(let msg, let grantsExtraRoll):
            turnLabel?.text = msg
            refreshTokenVisuals()
            if grantsExtraRoll {
                hintLabel?.text = Self.extraRollHint
                lastRollLabel?.text = "\(engine.currentSeat.displayName) — tap die"
            } else {
                hintLabel?.text = "\(engine.currentSeat.displayName)'s turn — tap die."
            }
            afterTurnEndedWithoutExtraRoll(grantsExtraRoll: grantsExtraRoll)
            pendingMoveJuiceMessage = msg
            let trapKill = prepareTrapMoveVisuals(for: msg)
            syncTokenPositionsFromEngine(animated: true, trapKill: trapKill) { [weak self] in
                self?.finishAnimatedMoveJuice()
                self?.onMoveAnimationsCompleted(previousRoller: roller)
            }
        case .gameOver(let lines, let summary):
            turnLabel?.text = summary
            hintLabel?.text = ""
            lastRollLabel?.text = ""
            _ = engine.consumeLastAppliedMove()
            syncTokenPositionsFromEngine()
            syncTrapBoardMarkersFromEngine()
            refreshTokenVisuals()
            if gameOverLayer == nil {
                presentGameOverOverlay(placementLines: lines)
            }
        }
        refreshStrengthHud()
        #if DEBUG
        refreshDebugPanel()
        #endif
    }

    private func handleTokenTap(seat: LudoSeat, tokenId: Int) {
        #if DEBUG
        if debugPowerupArmTap {
            debugApplyPowerupToToken(seat: seat, tokenId: tokenId)
            return
        }
        #endif
        guard gameOverLayer == nil, engine.pendingChoice != nil, seat == engine.currentSeat else { return }
        let roller = engine.currentSeat
        guard let result = engine.applyTokenChoice(seat: seat, tokenId: tokenId) else { return }
        switch result {
        case .applied(let message, let grantsExtraRoll):
            turnLabel?.text = message
            refreshTokenVisuals()
            if grantsExtraRoll {
                hintLabel?.text = Self.extraRollHint
                lastRollLabel?.text = "\(engine.currentSeat.displayName) — tap die"
            } else {
                hintLabel?.text = "\(engine.currentSeat.displayName)'s turn — tap die."
            }
            afterTurnEndedWithoutExtraRoll(grantsExtraRoll: grantsExtraRoll)
            pendingMoveJuiceMessage = message
            let trapKill = prepareTrapMoveVisuals(for: message)
            syncTokenPositionsFromEngine(animated: true, trapKill: trapKill) { [weak self] in
                self?.finishAnimatedMoveJuice()
                self?.onMoveAnimationsCompleted(previousRoller: roller)
            }
        case .gameOver(let lines, let message):
            turnLabel?.text = message
            hintLabel?.text = ""
            lastRollLabel?.text = ""
            _ = engine.consumeLastAppliedMove()
            syncTokenPositionsFromEngine()
            refreshBoardHazardsFromEngine()
            refreshTokenVisuals()
            if gameOverLayer == nil {
                LudoBoardJuice.shake(boardContainer, intensity: 7, duration: 0.32)
                presentGameOverOverlay(placementLines: lines)
            }
        }
        refreshStrengthHud()
        #if DEBUG
        refreshDebugPanel()
        #endif
    }

    private struct TrapKillAnimation {
        let seat: LudoSeat
        let tokenId: Int
        let trapPoint: CGPoint
        let yardPoint: CGPoint
    }

    /// Sync trap markers as soon as a trap fires; return trap square + yard for two-step VFX.
    private func prepareTrapMoveVisuals(for message: String) -> TrapKillAnimation? {
        let lower = message.lowercased()
        if lower.contains("trap triggered") {
            syncTrapBoardMarkersFromEngine()
        }
        if lower.contains("blackhole") {
            syncBlackholeBoardMarkersFromEngine()
        }
        let killed = lower.contains("sent to the yard") || lower.contains("sucked in")
        guard killed,
              let info = engine.pendingTrapKillVisual,
              let yardSpot = engine.spot(for: info.seat, tokenId: info.tokenId) else { return nil }
        let trapPoint = baseBoardPoint(seat: info.seat, tokenId: info.tokenId, spot: info.landingSpot)
        let yardPoint = baseBoardPoint(seat: info.seat, tokenId: info.tokenId, spot: yardSpot)
        return TrapKillAnimation(
            seat: info.seat,
            tokenId: info.tokenId,
            trapPoint: trapPoint,
            yardPoint: yardPoint
        )
    }

    private func finishAnimatedMoveJuice() {
        let message = pendingMoveJuiceMessage ?? ""
        pendingMoveJuiceMessage = nil
        let move = engine.lastAppliedMove
        playMoveJuice(message: message, mover: move?.seat, tokenId: move?.tokenId)
    }

    private func playMoveJuice(message: String, mover: LudoSeat?, tokenId: Int?) {
        guard let parent = juiceParticlesLayer else { return }
        let lower = message.lowercased()
        var point: CGPoint?
        if let mover, let tokenId, let spot = engine.spot(for: mover, tokenId: tokenId) {
            point = baseBoardPoint(seat: mover, tokenId: tokenId, spot: spot)
        }

        if lower.contains("captured") {
            LudoBoardJuice.shake(boardContainer, intensity: 6)
            if let point {
                LudoBoardJuice.spawnBurst(
                    at: point,
                    in: parent,
                    color: SKColor(red: 1, green: 0.32, blue: 0.18, alpha: 1),
                    count: 16,
                    spread: 28
                )
                LudoBoardJuice.spawnSparkles(
                    at: point,
                    in: parent,
                    colors: [
                        SKColor(red: 1, green: 0.9, blue: 0.2, alpha: 1),
                        SKColor(red: 1, green: 0.55, blue: 0.1, alpha: 1),
                        SKColor(red: 1, green: 0.25, blue: 0.15, alpha: 1),
                    ],
                    count: 12
                )
            }
        } else if lower.contains("blackhole") {
            LudoBoardJuice.shake(boardContainer, intensity: 5.5)
            var suctionPoint = point
            if let info = engine.pendingTrapKillVisual {
                suctionPoint = baseBoardPoint(seat: info.seat, tokenId: info.tokenId, spot: info.landingSpot)
            }
            if let suctionPoint {
                LudoBoardJuice.spawnBurst(
                    at: suctionPoint,
                    in: parent,
                    color: SKColor(red: 0.55, green: 0.15, blue: 0.9, alpha: 1),
                    count: 18,
                    spread: 22
                )
                LudoBoardJuice.spawnSparkles(
                    at: suctionPoint,
                    in: parent,
                    colors: [
                        SKColor(red: 0.75, green: 0.35, blue: 1, alpha: 1),
                        SKColor(red: 0.2, green: 0.05, blue: 0.35, alpha: 1),
                        SKColor(white: 1, alpha: 0.9),
                    ],
                    count: 14
                )
            }
        } else if lower.contains("trap triggered") {
            LudoBoardJuice.shake(boardContainer, intensity: 4.5)
            if let info = engine.pendingTrapKillVisual {
                let trapPoint = baseBoardPoint(seat: info.seat, tokenId: info.tokenId, spot: info.landingSpot)
                LudoBoardJuice.spawnBurst(
                    at: trapPoint,
                    in: parent,
                    color: SKColor(red: 0.95, green: 0.28, blue: 0.12, alpha: 1),
                    count: 12
                )
            }
        } else if message.contains("HOME") {
            LudoBoardJuice.shake(boardContainer, intensity: 3.2)
            if let point {
                LudoBoardJuice.spawnSparkles(
                    at: point,
                    in: parent,
                    colors: [
                        SKColor(red: 1, green: 0.9, blue: 0.25, alpha: 1),
                        SKColor(white: 1, alpha: 1),
                        SKColor(red: 0.4, green: 1, blue: 0.65, alpha: 1),
                    ],
                    count: 14
                )
            }
        }
    }

    private func presentGameOverOverlay(placementLines: [String]) {
        guard gameOverLayer == nil else { return }
        let root = SKNode()
        root.name = "gameOverRoot"
        root.zPosition = 400

        let w = size.width
        let h = size.height
        let dim = SKShapeNode(rectOf: CGSize(width: w + 4, height: h + 4))
        dim.fillColor = SKColor(white: 0, alpha: 0.55)
        dim.strokeColor = .clear
        dim.position = .zero
        root.addChild(dim)

        let panelW = min(340, max(280, w * 0.88))
        let lineCount = CGFloat(max(placementLines.count, 1))
        let panelH = min(h * 0.72, 56 + lineCount * 28 + 120)
        let panel = SKShapeNode(rectOf: CGSize(width: panelW, height: panelH), cornerRadius: 16)
        panel.fillColor = SKColor(white: 0.14, alpha: 0.97)
        panel.strokeColor = SKColor(white: 0.5, alpha: 0.5)
        panel.lineWidth = 1.5
        panel.position = .zero
        root.addChild(panel)

        let title = SKLabelNode(fontNamed: "AvenirNext-Bold")
        title.text = "Game over"
        title.fontSize = 26
        title.fontColor = SKColor(white: 1, alpha: 0.96)
        title.verticalAlignmentMode = .center
        title.horizontalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: panelH * 0.5 - 36)
        panel.addChild(title)

        let body = SKLabelNode(fontNamed: "AvenirNext-Medium")
        body.text = placementLines.joined(separator: "\n")
        body.fontSize = 17
        body.fontColor = SKColor(white: 0.92, alpha: 0.95)
        body.verticalAlignmentMode = .top
        body.horizontalAlignmentMode = .center
        body.numberOfLines = 0
        body.preferredMaxLayoutWidth = panelW - 32
        body.position = CGPoint(x: 0, y: panelH * 0.5 - 72)
        panel.addChild(body)

        let btnW: CGFloat = 220
        let btnH: CGFloat = 48
        let btn = SKShapeNode(rectOf: CGSize(width: btnW, height: btnH), cornerRadius: 12)
        btn.fillColor = SKColor(white: 0.96, alpha: 1)
        btn.strokeColor = SKColor(white: 0.35, alpha: 0.6)
        btn.lineWidth = 1.2
        btn.name = "gameOverMainMenuTap"
        btn.position = CGPoint(x: 0, y: -panelH * 0.5 + 48)
        panel.addChild(btn)

        let btnLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        btnLabel.text = "Main menu"
        btnLabel.fontSize = 19
        btnLabel.fontColor = SKColor(red: 0.12, green: 0.22, blue: 0.14, alpha: 1)
        btnLabel.verticalAlignmentMode = .center
        btnLabel.horizontalAlignmentMode = .center
        btnLabel.position = btn.position
        btnLabel.name = "gameOverMainMenuTap"
        panel.addChild(btnLabel)

        addChild(root)
        gameOverLayer = root
    }

    private func relayoutGameOverOverlayIfNeeded() {
        guard engine.isGameOver else { return }
        gameOverLayer?.removeFromParent()
        gameOverLayer = nil
        presentGameOverOverlay(placementLines: engine.gameOverSummaryLines())
    }

    // MARK: - Token layout

    private func baseBoardPoint(seat: LudoSeat, tokenId: Int, spot: LudoTokenSpot) -> CGPoint {
        switch spot {
        case .yard:
            let g = LudoBoardPath.yardCells(for: seat)[tokenId]
            return LudoBoardBuilder.boardPoint(row: g.row, col: g.col)
        case .track(let pathIndex, _):
            let g = LudoBoardPath.publicTrack[(pathIndex % 52 + 52) % 52]
            return LudoBoardBuilder.boardPoint(row: g.row, col: g.col)
        case .home(let step):
            let cells = LudoBoardPath.homeStretchCellsInGoalOrder(for: seat)
            let g = cells[min(max(0, step), cells.count - 1)]
            return LudoBoardBuilder.boardPoint(row: g.row, col: g.col)
        case .finished:
            let g = LudoBoardPath.goalHub
            return LudoBoardBuilder.boardPoint(row: g.row, col: g.col)
        }
    }

    private func bucketKey(seat: LudoSeat, tokenId: Int, spot: LudoTokenSpot) -> String {
        switch spot {
        case .yard:
            let g = LudoBoardPath.yardCells(for: seat)[tokenId]
            return "y_\(g.row)_\(g.col)"
        case .track(let pathIndex, _):
            return "t_\(pathIndex % 52)"
        case .home(let step):
            return "h_\(seat.rawValue)_\(step)"
        case .finished:
            return "f_\(seat.rawValue)_\(tokenId)"
        }
    }

    private func syncTokenPositionsFromEngine(
        animated: Bool = false,
        trapKill: TrapKillAnimation? = nil,
        completion: (() -> Void)? = nil
    ) {
        var buckets: [String: [(seat: LudoSeat, id: Int, spot: LudoTokenSpot)]] = [:]
        for (seat, nodes) in tokenNodes {
            for i in 0..<nodes.count {
                guard let spot = engine.spot(for: seat, tokenId: i) else { continue }
                let key = bucketKey(seat: seat, tokenId: i, spot: spot)
                buckets[key, default: []].append((seat, i, spot))
            }
        }

        struct TokenMoveItem {
            let node: SKShapeNode
            let seat: LudoSeat
            let tokenId: Int
            let target: CGPoint
        }

        var items: [TokenMoveItem] = []
        items.reserveCapacity(16)
        for (_, group) in buckets {
            let n = group.count
            for (idx, entry) in group.enumerated() {
                guard let node = tokenNodes[entry.seat]?[entry.id] else { continue }
                var p = baseBoardPoint(seat: entry.seat, tokenId: entry.id, spot: entry.spot)
                if n > 1 {
                    let angle = CGFloat(idx) / CGFloat(n) * (.pi * 2)
                    let r: CGFloat = 9
                    p.x += cos(angle) * r
                    p.y += sin(angle) * r
                }
                items.append(TokenMoveItem(node: node, seat: entry.seat, tokenId: entry.id, target: p))
            }
        }

        if !animated {
            for item in items {
                item.node.position = item.target
                item.node.alpha = 1
                item.node.setScale(1)
            }
            completion?()
            return
        }

        let threshold: CGFloat = 1.25
        let moving = items.filter { item in
            if let trapKill,
               item.seat == trapKill.seat,
               item.tokenId == trapKill.tokenId {
                return true
            }
            return hypot(item.node.position.x - item.target.x, item.node.position.y - item.target.y) > threshold
        }
        if moving.isEmpty {
            completion?()
            return
        }

        var remaining = moving.count
        let finish: () -> Void = {
            remaining -= 1
            if remaining == 0 {
                completion?()
            }
        }

        for item in moving {
            item.node.removeAction(forKey: "tokenMove")
            if let trapKill,
               item.seat == trapKill.seat,
               item.tokenId == trapKill.tokenId {
                let distToTrap = hypot(
                    item.node.position.x - trapKill.trapPoint.x,
                    item.node.position.y - trapKill.trapPoint.y
                )
                let durToTrap = TimeInterval(min(0.58, max(0.14, Double(distToTrap) / 280)))
                var steps: [SKAction] = []
                if distToTrap > threshold {
                    steps.append(LudoBoardJuice.easedMove(to: trapKill.trapPoint, duration: durToTrap))
                }
                steps.append(LudoBoardJuice.trapKillFade(on: item.node, toYardPosition: trapKill.yardPoint))
                steps.append(SKAction.run(finish))
                item.node.run(SKAction.sequence(steps), withKey: "tokenMove")
                continue
            }
            let dist = hypot(item.node.position.x - item.target.x, item.node.position.y - item.target.y)
            let dur = TimeInterval(min(0.58, max(0.14, Double(dist) / 280)))
            item.node.run(
                SKAction.sequence([
                    LudoBoardJuice.easedMove(to: item.target, duration: dur),
                    LudoBoardJuice.landBounce(on: item.node),
                    SKAction.run(finish),
                ]),
                withKey: "tokenMove"
            )
        }
    }

    private func refreshTokenVisuals() {
        let pending = engine.pendingChoice
        let validFreezeTargets: Set<String> = if let ctx = freezeSelectionContext {
            Set(engine.validFreezeTargets(for: ctx.applierSeat).map { "\($0.seat.rawValue)_\($0.tokenId)" })
        } else {
            []
        }
        let validShieldTargets: Set<String> = if let ctx = shieldSelectionContext {
            Set(engine.validSmallShieldTargets(for: ctx.applierSeat).map { "\($0.seat.rawValue)_\($0.tokenId)" })
        } else {
            []
        }
        let activeSeats = Set(LudoSeat.activeSeats(forPlayerCount: playerCount))
        for (seat, nodes) in tokenNodes {
            for i in 0..<nodes.count {
                let node = nodes[i]
                let frozen = engine.isTokenFrozen(owner: seat, tokenId: i)
                updateFreezeBadge(on: node, show: frozen)
                updateShieldBadge(on: node, kind: engine.shieldKind(for: seat, tokenId: i))
                if !activeSeats.contains(seat) {
                    node.setScale(1)
                    node.alpha = 0.32
                    continue
                }
                #if DEBUG
                if debugPowerupArmTap {
                    let key = "\(seat.rawValue)_\(i)"
                    let valid = debugValidArmTokenKeys()
                    if valid.contains(key) {
                        node.alpha = 1
                        node.setScale(1.12)
                    } else {
                        node.alpha = 0.28
                    }
                    continue
                }
                #endif
                node.setScale(1)
                if let ctx = freezeSelectionContext {
                    let key = "\(seat.rawValue)_\(i)"
                    if validFreezeTargets.contains(key) {
                        node.alpha = 1
                        node.setScale(1.12)
                    } else if seat == ctx.applierSeat {
                        node.alpha = 0.35
                    } else {
                        node.alpha = 0.28
                    }
                } else if let ctx = shieldSelectionContext {
                    let key = "\(seat.rawValue)_\(i)"
                    if validShieldTargets.contains(key) {
                        node.alpha = 1
                        node.setScale(1.12)
                    } else {
                        node.alpha = 0.28
                    }
                } else if let p = pending, seat == engine.currentSeat {
                    let legal = p.legalYard.contains(i) || p.legalTrack.contains(i) || p.legalHome.contains(i)
                    node.alpha = legal ? 1 : 0.32
                } else if seat == engine.currentSeat {
                    node.alpha = 1
                } else {
                    node.alpha = pending != nil ? 0.45 : 1
                }
                if let sp = engine.spot(for: seat, tokenId: i), case .finished = sp {
                    node.alpha = min(node.alpha, 0.85)
                }
            }
        }
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        _ = handleCatalogScrollBegan(touch)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        _ = handleCatalogScrollMoved(touch)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }

        if handleCatalogScrollEnded() { return }

        let sceneLoc = touch.location(in: self)
        for node in nodes(at: sceneLoc) {
            var current: SKNode? = node
            while let c = current {
                if c.name == "gameOverMainMenuTap" {
                    onRequestMenu?()
                    return
                }
                current = c.parent
            }
        }

        if gameOverLayer != nil { return }

        if handleBlackholePlacementTouch(touch) { return }

        if handleTrapPlacementTouch(touch) { return }

        if handleFreezeSelectionTouch(touch) { return }

        if handleShieldSelectionTouch(touch) { return }

        if handleSwapConfirmTouch(touch) { return }

        if let root = powerupRevealRoot {
            let prLoc = touch.location(in: root)
            for node in root.nodes(at: prLoc) {
                var current: SKNode? = node
                while let c = current {
                    if c.name == "powerupRevealDismiss" {
                        dismissPowerupBanner()
                        return
                    }
                    current = c.parent
                }
            }
        }

        if let catalog = powerupsCatalogRoot {
            let catLoc = touch.location(in: catalog)
            for node in catalog.nodes(at: catLoc) {
                var current: SKNode? = node
                while let c = current {
                    if c.name == "powerupsCatalogDismiss" {
                        dismissPowerupsCatalog()
                        return
                    }
                    current = c.parent
                }
            }
            return
        }

        let menuLoc = touch.location(in: menuContainer)
        for node in menuContainer.nodes(at: menuLoc) {
            var current: SKNode? = node
            while let c = current {
                if c.name == "menuTap" {
                    onRequestMenu?()
                    return
                }
                if c.name == "powerupsTabTap" {
                    togglePowerupsCatalog()
                    return
                }
                #if DEBUG
                if c.name == "debugTabTap" {
                    if debugPowerupArmTap {
                        cancelDebugArmMode()
                    }
                    toggleDebugPanel()
                    return
                }
                #endif
                current = c.parent
            }
        }

        #if DEBUG
        if debugPowerupArmTap {
            if let (seat, tid) = debugTokenHit(at: touch.location(in: boardContainer)) {
                debugApplyPowerupToToken(seat: seat, tokenId: tid)
            } else {
                let valid = debugValidArmTokenKeys()
                if valid.isEmpty {
                    turnLabel?.text = "Debug: no valid tile for \(debugSelectedPowerup.displayName). Tap Debug to cancel."
                    cancelDebugArmMode()
                } else {
                    turnLabel?.text = "Debug: tap a highlighted token (\(debugSelectedPowerup.displayName)). Tap Debug to cancel."
                }
            }
            return
        }
        if debugPanelRoot != nil {
            if handleDebugTouch(touch) { return }
            if !debugAllowsBoardTouchesWhilePanelOpen { return }
        }
        #endif

        if let (seat, tid) = tokenHit(at: touch.location(in: boardContainer)) {
            if let ctx = freezeSelectionContext {
                if engine.validFreezeTargets(for: ctx.applierSeat).contains(where: { $0.seat == seat && $0.tokenId == tid }) {
                    confirmFreezeTarget(owner: seat, tokenId: tid)
                } else {
                    turnLabel?.text = "Freeze Token — pick an opponent token on the track."
                }
                return
            }
            if let ctx = shieldSelectionContext {
                if engine.validSmallShieldTargets(for: ctx.applierSeat).contains(where: { $0.seat == seat && $0.tokenId == tid }) {
                    confirmShieldTarget(owner: seat, tokenId: tid)
                } else {
                    turnLabel?.text = "Small Shield — pick your token on the track or home stretch."
                }
                return
            }
            handleTokenTap(seat: seat, tokenId: tid)
            return
        }

        let diceLoc = touch.location(in: diceContainer)
        let diceHits = diceContainer.nodes(at: diceLoc)
        for node in diceHits {
            var current: SKNode? = node
            while let c = current {
                if c.name == "diceArea" || c.name == "diceHitPad" {
                    guard canAcceptDiceRoll() else { return }
                    #if DEBUG
                    if let s = debugStagedRoll {
                        applyDebugRoll(s)
                        return
                    }
                    #endif
                    gameplayRollInFlight = true
                    diceNode?.rollAnimated { [weak self] value in
                        guard let self else { return }
                        self.gameplayRollInFlight = false
                        self.lastRollLabel?.text = "Rolled \(value)"
                        self.handleGameplayRoll(value)
                    }
                    return
                }
                current = c.parent
            }
        }
    }

    private func tokenHit(at point: CGPoint) -> (LudoSeat, Int)? {
        for node in boardContainer.nodes(at: point) {
            if let hit = tokenIdentity(from: node) { return hit }
        }
        return nil
    }

    #if DEBUG
    private func debugTokenHit(at point: CGPoint) -> (LudoSeat, Int)? {
        if let hit = tokenHit(at: point) { return hit }
        return closestTokenHit(at: point, maxDistance: 36)
    }

    private func closestTokenHit(at point: CGPoint, maxDistance: CGFloat) -> (LudoSeat, Int)? {
        let boardRoot = boardContainer.childNode(withName: "ludoBoard") ?? boardContainer
        let pointInBoard = boardRoot.convert(point, from: boardContainer)
        let hitRadius = maxDistance / max(boardContainer.xScale, 0.01)
        var best: (seat: LudoSeat, id: Int, d: CGFloat)?
        for (seat, nodes) in tokenNodes {
            for (index, node) in nodes.enumerated() {
                let d = hypot(node.position.x - pointInBoard.x, node.position.y - pointInBoard.y)
                guard d <= hitRadius else { continue }
                if best == nil || d < best!.d {
                    best = (seat, index, d)
                }
            }
        }
        if let match = best { return (match.seat, match.id) }
        return nil
    }

    /// Active player used as freeze/shield caster when the panel target seat is inactive (2p/3p).
    private func debugPowerupApplierSeat() -> LudoSeat {
        let active = LudoSeat.activeSeats(forPlayerCount: playerCount)
        if active.contains(debugTargetSeat) { return debugTargetSeat }
        return engine.currentSeat
    }

    private func debugValidArmTokenKeys() -> Set<String> {
        var keys = Set<String>()
        func add(_ seat: LudoSeat, _ tokenId: Int) {
            keys.insert("\(seat.rawValue)_\(tokenId)")
        }
        let applier = debugPowerupApplierSeat()
        switch debugSelectedPowerup {
        case .freezeToken, .smallShield:
            if debugArmAwaitingMysteryToken {
                for i in 0..<4 where engine.spot(for: applier, tokenId: i) != nil {
                    add(applier, i)
                }
            } else if debugSelectedPowerup == .freezeToken {
                for t in engine.validFreezeTargets(for: applier) {
                    add(t.seat, t.tokenId)
                }
            } else {
                for t in engine.validSmallShieldTargets(for: applier) {
                    add(t.seat, t.tokenId)
                }
            }
        case .trap:
            guard !engine.validTrapPlacementCells().isEmpty else { break }
            for seat in engine.activeSeatsOrdered {
                for i in 0..<4 where engine.spot(for: seat, tokenId: i) != nil {
                    add(seat, i)
                }
            }
        case .blackhole:
            guard !engine.validBlackholePlacementCells().isEmpty else { break }
            for seat in engine.activeSeatsOrdered {
                for i in 0..<4 where engine.spot(for: seat, tokenId: i) != nil {
                    add(seat, i)
                }
            }
        case .dash, .swap:
            for seat in engine.activeSeatsOrdered {
                for i in 0..<4 {
                    guard let sp = engine.spot(for: seat, tokenId: i) else { continue }
                    switch sp {
                    case .track, .home: add(seat, i)
                    default: break
                    }
                }
            }
        default:
            break
        }
        return keys
    }

    /// Arm-token: dash/swap/trap apply from tapped token; freeze/shield use mystery lander then normal target pick.
    private func debugApplyPowerupToToken(seat: LudoSeat, tokenId: Int) {
        guard gameOverLayer == nil, debugPowerupArmTap else { return }
        let key = "\(seat.rawValue)_\(tokenId)"
        guard debugValidArmTokenKeys().contains(key) else {
            turnLabel?.text = "Debug: that token can't receive \(debugSelectedPowerup.displayName) right now."
            return
        }

        switch debugSelectedPowerup {
        case .freezeToken:
            let applier = debugPowerupApplierSeat()
            guard seat == applier else {
                turnLabel?.text = "Freeze — tap your \(applier.displayName) token first (mystery pickup)."
                return
            }
            debugPowerupArmTap = false
            debugArmAwaitingMysteryToken = false
            let start = engine.applyPowerup(.freezeToken, seat: seat, tokenId: tokenId)
            handleFreezePowerupOfferOutcome(start, applierSeat: seat, applierTokenId: tokenId, showBanner: true)
            if freezeSelectionContext != nil {
                hintLabel?.text = "Freeze — tap an opponent's token on the track"
            } else {
                hintLabel?.text = "\(engine.currentSeat.displayName)'s turn — tap die."
            }
        case .smallShield:
            let applier = debugPowerupApplierSeat()
            guard seat == applier else {
                turnLabel?.text = "Small Shield — tap your \(applier.displayName) token first (mystery pickup)."
                return
            }
            debugPowerupArmTap = false
            debugArmAwaitingMysteryToken = false
            let start = engine.applyPowerup(.smallShield, seat: seat, tokenId: tokenId)
            handleSmallShieldPowerupOfferOutcome(start, applierSeat: seat, applierTokenId: tokenId, showBanner: true)
            if shieldSelectionContext != nil {
                hintLabel?.text = "Small Shield — tap your token on track or home stretch"
            } else {
                hintLabel?.text = "\(engine.currentSeat.displayName)'s turn — tap die."
            }
        case .trap:
            let outcome = engine.applyPowerup(.trap, seat: seat, tokenId: tokenId)
            handleTrapPowerupOfferOutcome(outcome, seat: seat, tokenId: tokenId, showBanner: true)
            debugPowerupArmTap = false
        case .blackhole:
            let outcome = engine.applyPowerup(.blackhole, seat: seat, tokenId: tokenId)
            handleBlackholePowerupOfferOutcome(outcome, seat: seat, tokenId: tokenId, showBanner: true)
            debugPowerupArmTap = false
        default:
            runPowerupTest(debugSelectedPowerup, seat: seat, tokenId: tokenId, showBanner: true)
            debugPowerupArmTap = false
            hintLabel?.text = "\(engine.currentSeat.displayName)'s turn — tap die."
        }
        refreshTokenVisuals()
    }

    private func cancelDebugArmMode() {
        debugPowerupArmTap = false
        debugArmAwaitingMysteryToken = false
        refreshTokenVisuals()
        hintLabel?.text = "\(engine.currentSeat.displayName)'s turn — tap die."
    }
    #endif

    private func tokenIdentity(from node: SKNode) -> (LudoSeat, Int)? {
        var current: SKNode? = node
        while let c = current {
            if let name = c.name, name.hasPrefix("token_") {
                let parts = name.split(separator: "_")
                if parts.count == 3, let raw = Int(parts[1]), let tid = Int(parts[2]),
                   let seat = LudoSeat(rawValue: raw) {
                    return (seat, tid)
                }
            }
            current = c.parent
        }
        return nil
    }

    #if DEBUG

    private func setupDebugTabIfNeeded() {
        guard menuContainer.childNode(withName: "debugTabTap") == nil else { return }
        let w: CGFloat = 88
        let h: CGFloat = 40
        let pad = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 10)
        pad.fillColor = SKColor(red: 0.55, green: 0.32, blue: 0.12, alpha: 0.5)
        pad.strokeColor = SKColor(red: 1, green: 0.72, blue: 0.35, alpha: 0.65)
        pad.lineWidth = 1.2
        pad.position = CGPoint(x: 248, y: 0)
        pad.name = "debugTabTap"
        menuContainer.addChild(pad)

        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = "Debug"
        label.fontSize = 15
        label.fontColor = SKColor(red: 1, green: 0.9, blue: 0.7, alpha: 0.96)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 248, y: 0)
        label.name = "debugTabLabel"
        menuContainer.addChild(label)
    }

    private func toggleDebugPanel() {
        if debugPanelRoot != nil {
            dismissDebugPanel()
        } else {
            presentDebugPanel()
        }
    }

    private func dismissDebugPanel(clearArm: Bool = false) {
        debugPanelRoot?.removeFromParent()
        debugPanelRoot = nil
        if clearArm {
            debugPowerupArmTap = false
            debugArmAwaitingMysteryToken = false
        }
        refreshTokenVisuals()
    }

    private func presentDebugPanel() {
        dismissDebugPanel()
        dismissPowerupsCatalog()
        debugTargetSeat = engine.currentSeat
        debugSubTab = .dice

        let root = SKNode()
        root.name = "debugPanelRoot"
        root.zPosition = 165

        let dim = SKShapeNode(rectOf: CGSize(width: size.width + 8, height: size.height + 8))
        dim.fillColor = SKColor(white: 0, alpha: 0.45)
        dim.strokeColor = .clear
        dim.name = "debugPanelDismiss"
        root.addChild(dim)

        let sheetW = min(360, max(300, size.width * 0.92))
        let sheetH: CGFloat = 430
        let sheet = SKShapeNode(rectOf: CGSize(width: sheetW, height: sheetH), cornerRadius: 14)
        sheet.fillColor = SKColor(white: 0.1, alpha: 0.98)
        sheet.strokeColor = SKColor(red: 1, green: 0.65, blue: 0.3, alpha: 0.75)
        sheet.lineWidth = 1.5
        root.addChild(sheet)
        debugSheet = sheet

        let title = SKLabelNode(fontNamed: "AvenirNext-Bold")
        title.text = "Debug"
        title.fontSize = 20
        title.fontColor = SKColor(white: 1, alpha: 0.98)
        title.verticalAlignmentMode = .center
        title.horizontalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: sheetH * 0.5 - 28)
        sheet.addChild(title)

        let subY = sheetH * 0.5 - 56
        let subW: CGFloat = 118
        let subDice = makeDebugButton(title: "Dice", name: "dbgSubDice", width: subW, height: 30)
        subDice.position = CGPoint(x: -subW * 0.5 - 4, y: subY)
        sheet.addChild(subDice)
        let subPwr = makeDebugButton(title: "Powerups", name: "dbgSubPowerups", width: subW, height: 30)
        subPwr.position = CGPoint(x: subW * 0.5 + 4, y: subY)
        sheet.addChild(subPwr)

        let pageDice = SKNode()
        pageDice.name = "dbgPageDice"
        sheet.addChild(pageDice)
        debugPageDice = pageDice

        let staged = SKLabelNode(fontNamed: "AvenirNext-Medium")
        staged.fontSize = 12
        staged.fontColor = SKColor(white: 0.85, alpha: 0.9)
        staged.verticalAlignmentMode = .center
        staged.horizontalAlignmentMode = .center
        staged.position = CGPoint(x: 0, y: sheetH * 0.5 - 88)
        staged.text = "Tap 1–6 to roll immediately"
        pageDice.addChild(staged)
        debugStagedLabel = staged

        let rowY = sheetH * 0.5 - 114
        let dieW: CGFloat = 44
        let gap: CGFloat = 6
        let rowW = 6 * dieW + 5 * gap
        var x0 = -rowW * 0.5 + dieW * 0.5
        for v in 1...6 {
            let b = makeDebugButton(title: "\(v)", name: "dbgDie\(v)", width: dieW, height: 32)
            b.position = CGPoint(x: x0, y: rowY)
            pageDice.addChild(b)
            x0 += dieW + gap
        }

        func addPreset(_ label: String, name: String, y: CGFloat) {
            let b = makeDebugButton(title: label, name: name, width: sheetW - 36, height: 28)
            b.position = CGPoint(x: 0, y: y)
            pageDice.addChild(b)
        }

        addPreset("Green t0: post-lap @ start (lap 52)", name: "dbgPresetGreenStart", y: sheetH * 0.5 - 154)
        addPreset("Green t0: on fork (lap 54)", name: "dbgPresetGreenFork", y: sheetH * 0.5 - 186)
        addPreset("Green t0: home step 4", name: "dbgPresetGreenHome4", y: sheetH * 0.5 - 218)
        addPreset("Rotate current seat", name: "dbgNextSeat", y: sheetH * 0.5 - 250)
        addPreset("Clear staged die", name: "dbgClearDie", y: sheetH * 0.5 - 282)

        let status = SKLabelNode(fontNamed: "Menlo-Regular")
        status.fontSize = 9
        status.fontColor = SKColor(white: 0.72, alpha: 0.95)
        status.verticalAlignmentMode = .top
        status.horizontalAlignmentMode = .left
        status.numberOfLines = 0
        status.preferredMaxLayoutWidth = sheetW - 28
        status.position = CGPoint(x: -sheetW * 0.5 + 14, y: -sheetH * 0.5 + 118)
        status.text = ""
        pageDice.addChild(status)
        debugStatusLabel = status

        let pagePwr = SKNode()
        pagePwr.name = "dbgPagePowerups"
        pagePwr.isHidden = true
        pagePwr.zPosition = 2
        sheet.addChild(pagePwr)
        debugPagePowerups = pagePwr

        let pwrHint = SKLabelNode(fontNamed: "AvenirNext-Medium")
        pwrHint.text = "Pick powerup, seat, token — then apply or arm board tap"
        pwrHint.fontSize = 11
        pwrHint.fontColor = SKColor(white: 0.7, alpha: 0.9)
        pwrHint.verticalAlignmentMode = .center
        pwrHint.horizontalAlignmentMode = .center
        pwrHint.preferredMaxLayoutWidth = sheetW - 32
        pwrHint.numberOfLines = 2
        pwrHint.position = CGPoint(x: 0, y: sheetH * 0.5 - 88)
        pagePwr.addChild(pwrHint)

        let pickY = sheetH * 0.5 - 128
        let pickGap: CGFloat = 8
        let pickW: CGFloat = (sheetW - 48) / CGFloat(LudoPowerup.allCases.count) - pickGap
        var pickX = -sheetW * 0.5 + 24 + pickW * 0.5
        for p in LudoPowerup.catalogSortedByRarity {
            let btn = makeDebugButton(title: p.displayName, name: "dbgPwrPick_\(p.rawValue)", width: pickW, height: 44)
            btn.position = CGPoint(x: pickX, y: pickY)
            pagePwr.addChild(btn)
            let icon = LudoPowerupIcon.makeIcon(for: p, size: 28)
            icon.position = CGPoint(x: 0, y: 10)
            btn.addChild(icon)
            pickX += pickW + pickGap
        }

        let seatLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        seatLabel.text = "Seat"
        seatLabel.fontSize = 11
        seatLabel.fontColor = SKColor(white: 0.65, alpha: 0.9)
        seatLabel.verticalAlignmentMode = .center
        seatLabel.horizontalAlignmentMode = .left
        seatLabel.position = CGPoint(x: -sheetW * 0.5 + 18, y: sheetH * 0.5 - 168)
        pagePwr.addChild(seatLabel)

        let seatW: CGFloat = min(72, (sheetW - 80) / 4) - 6
        var seatX = -sheetW * 0.5 + 24 + seatW * 0.5
        let seatY = sheetH * 0.5 - 194
        for s in LudoSeat.allCases {
            let b = makeDebugButton(title: s.displayName, name: "dbgPwrSeat_\(s.rawValue)", width: seatW, height: 28)
            b.position = CGPoint(x: seatX, y: seatY)
            pagePwr.addChild(b)
            seatX += seatW + 6
        }

        let tokLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        tokLabel.text = "Token"
        tokLabel.fontSize = 11
        tokLabel.fontColor = SKColor(white: 0.65, alpha: 0.9)
        tokLabel.verticalAlignmentMode = .center
        tokLabel.horizontalAlignmentMode = .left
        tokLabel.position = CGPoint(x: -sheetW * 0.5 + 18, y: sheetH * 0.5 - 224)
        pagePwr.addChild(tokLabel)

        let tokW: CGFloat = 56
        var tokX = -sheetW * 0.5 + 24 + tokW * 0.5
        let tokY = sheetH * 0.5 - 250
        for t in 0..<4 {
            let b = makeDebugButton(title: "\(t + 1)", name: "dbgPwrTok_\(t)", width: tokW, height: 28)
            b.position = CGPoint(x: tokX, y: tokY)
            pagePwr.addChild(b)
            tokX += tokW + 6
        }

        let applyBtn = makeDebugButton(title: "Apply + show banner", name: "dbgPwrApply", width: sheetW - 36, height: 34)
        applyBtn.position = CGPoint(x: 0, y: sheetH * 0.5 - 296)
        pagePwr.addChild(applyBtn)

        let armBtn = makeDebugButton(title: "Arm: tap token on board", name: "dbgPwrArm", width: sheetW - 36, height: 34)
        armBtn.position = CGPoint(x: 0, y: sheetH * 0.5 - 336)
        pagePwr.addChild(armBtn)

        let pwrStatus = SKLabelNode(fontNamed: "Menlo-Regular")
        pwrStatus.fontSize = 9
        pwrStatus.fontColor = SKColor(white: 0.72, alpha: 0.95)
        pwrStatus.verticalAlignmentMode = .top
        pwrStatus.horizontalAlignmentMode = .left
        pwrStatus.numberOfLines = 0
        pwrStatus.preferredMaxLayoutWidth = sheetW - 28
        pwrStatus.position = CGPoint(x: -sheetW * 0.5 + 14, y: -sheetH * 0.5 + 118)
        pwrStatus.text = ""
        pagePwr.addChild(pwrStatus)
        debugPwrStatusLabel = pwrStatus

        let close = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        close.text = "Close"
        close.fontSize = 15
        close.fontColor = SKColor(red: 0.55, green: 0.85, blue: 1, alpha: 1)
        close.verticalAlignmentMode = .center
        close.horizontalAlignmentMode = .center
        close.position = CGPoint(x: 0, y: -sheetH * 0.5 + 22)
        close.name = "debugPanelDismiss"
        sheet.addChild(close)

        addChild(root)
        debugPanelRoot = root
        updateDebugSubTabUI()
        refreshDebugPanel()
    }

    private func updateDebugSubTabUI() {
        debugPageDice?.isHidden = debugSubTab != .dice
        debugPagePowerups?.isHidden = debugSubTab != .powerups
        guard let sheet = debugSheet else { return }
        let on = SKColor(red: 0.35, green: 0.55, blue: 0.38, alpha: 0.95)
        let off = SKColor(white: 0.22, alpha: 0.95)
        if let diceBtn = sheet.childNode(withName: "dbgSubDice")?.children.first as? SKShapeNode {
            diceBtn.fillColor = debugSubTab == .dice ? on : off
        }
        if let pwrBtn = sheet.childNode(withName: "dbgSubPowerups")?.children.first as? SKShapeNode {
            pwrBtn.fillColor = debugSubTab == .powerups ? on : off
        }
        for p in LudoPowerup.allCases {
            let sel = p == debugSelectedPowerup
            if let btn = debugPagePowerups?.childNode(withName: "dbgPwrPick_\(p.rawValue)")?.children.first as? SKShapeNode {
                btn.fillColor = sel ? SKColor(red: 0.2, green: 0.45, blue: 0.35, alpha: 1) : off
                btn.strokeColor = sel ? SKColor(red: 0.5, green: 1, blue: 0.7, alpha: 1) : SKColor(white: 0.5, alpha: 0.85)
            }
        }
        for s in LudoSeat.allCases {
            let sel = s == debugTargetSeat
            if let btn = debugPagePowerups?.childNode(withName: "dbgPwrSeat_\(s.rawValue)")?.children.first as? SKShapeNode {
                btn.fillColor = sel ? SKColor(red: 0.25, green: 0.35, blue: 0.55, alpha: 1) : off
            }
        }
        for t in 0..<4 {
            let sel = t == debugTargetTokenId
            if let btn = debugPagePowerups?.childNode(withName: "dbgPwrTok_\(t)")?.children.first as? SKShapeNode {
                btn.fillColor = sel ? SKColor(red: 0.25, green: 0.35, blue: 0.55, alpha: 1) : off
            }
        }
        if let armBtn = debugPagePowerups?.childNode(withName: "dbgPwrArm")?.children.first as? SKShapeNode {
            armBtn.fillColor = debugPowerupArmTap
                ? SKColor(red: 0.55, green: 0.22, blue: 0.18, alpha: 1)
                : off
        }
    }

    private func makeDebugButton(title: String, name: String, width: CGFloat, height: CGFloat) -> SKNode {
        let n = SKNode()
        n.name = name
        let bg = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 8)
        bg.name = name
        bg.fillColor = SKColor(white: 0.22, alpha: 0.95)
        bg.strokeColor = SKColor(white: 0.5, alpha: 0.85)
        bg.lineWidth = 1
        n.addChild(bg)
        let l = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        l.text = title
        l.fontSize = min(11, max(8, width * 0.09))
        l.fontColor = SKColor(white: 1, alpha: 0.92)
        l.verticalAlignmentMode = .center
        l.horizontalAlignmentMode = .center
        n.addChild(l)
        return n
    }

    /// Same flow as mystery pickup: `applyPowerup` then trap tile / freeze·shield token / immediate dash·swap.
    private func debugStartSelectedPowerup() {
        guard gameOverLayer == nil else { return }
        let applier = debugPowerupApplierSeat()
        let applierToken = debugTargetTokenId

        switch debugSelectedPowerup {
        case .trap:
            let outcome = engine.applyPowerup(.trap, seat: applier, tokenId: applierToken)
            handleTrapPowerupOfferOutcome(outcome, seat: applier, tokenId: applierToken, showBanner: true)
        case .blackhole:
            let outcome = engine.applyPowerup(.blackhole, seat: applier, tokenId: applierToken)
            handleBlackholePowerupOfferOutcome(outcome, seat: applier, tokenId: applierToken, showBanner: true)
        case .freezeToken:
            let outcome = engine.applyPowerup(.freezeToken, seat: applier, tokenId: applierToken)
            handleFreezePowerupOfferOutcome(outcome, applierSeat: applier, applierTokenId: applierToken, showBanner: true)
        case .smallShield:
            let outcome = engine.applyPowerup(.smallShield, seat: applier, tokenId: applierToken)
            handleSmallShieldPowerupOfferOutcome(outcome, applierSeat: applier, applierTokenId: applierToken, showBanner: true)
        default:
            runPowerupTest(debugSelectedPowerup, seat: applier, tokenId: applierToken, showBanner: true)
            hintLabel?.text = "\(engine.currentSeat.displayName)'s turn — tap die."
        }
        refreshTokenVisuals()
        refreshDebugPanel()
    }

    private var debugAllowsBoardTouchesWhilePanelOpen: Bool {
        trapPlacementContext != nil
            || blackholePlacementContext != nil
            || freezeSelectionContext != nil
            || shieldSelectionContext != nil
    }

    private func applyDebugRoll(_ value: Int) {
        guard canAcceptGameplayRoll(allowWhileDebugPanelOpen: true) else {
            debugStagedLabel?.text = "Can't roll — finish token choice, wait for turn, or close other overlays."
            return
        }
        debugStagedRoll = value
        lastRollLabel?.text = "Rolled \(value) (debug)"
        setupDiceIfNeeded()
        diceNode?.revealRoll(to: value) { [weak self] in
            self?.refreshDebugPanel()
        }
        handleGameplayRoll(value)
        debugStagedRoll = nil
    }

    private func refreshDebugPanel() {
        guard debugPanelRoot != nil else { return }
        if let s = debugStagedRoll {
            debugStagedLabel?.text = "Staged \(s) — tap die or pick another value"
        } else {
            debugStagedLabel?.text = "Tap 1–6 to roll immediately"
        }
        var lines: [String] = []
        lines.append("Turn: \(engine.currentSeat.displayName)")
        lines.append("Finish: \(engine.finishOrder.map(\.displayName).joined(separator: ", "))")
        for seat in LudoSeat.allCases where LudoSeat.activeSeats(forPlayerCount: playerCount).contains(seat) {
            if let sp = engine.spot(for: seat, tokenId: debugTargetTokenId) {
                lines.append("\(seat.displayName) t\(debugTargetTokenId): \(debugSpotSummary(sp))")
            }
        }
        debugStatusLabel?.text = lines.joined(separator: "\n")

        var pwrLines: [String] = []
        pwrLines.append("Selected: \(debugSelectedPowerup.displayName) (\(debugSelectedPowerup.rarity.displayTitle))")
        pwrLines.append("Target: \(debugTargetSeat.displayName) token \(debugTargetTokenId + 1)")
        if debugPowerupArmTap {
            if debugArmAwaitingMysteryToken {
                pwrLines.append("ARMED — tap YOUR \(debugPowerupApplierSeat().displayName) token (mystery lander)")
            } else {
                pwrLines.append("ARMED — tap a highlighted token on the board")
            }
        } else if trapPlacementContext != nil {
            pwrLines.append("Placing trap — tap a highlighted tile")
        } else if blackholePlacementContext != nil {
            pwrLines.append("Placing blackhole — tap a highlighted tile")
        } else if freezeSelectionContext != nil {
            pwrLines.append("Freeze — tap an opponent on the track")
        } else if shieldSelectionContext != nil {
            pwrLines.append("Shield — tap your token on track/home")
        }
        if let sp = engine.spot(for: debugTargetSeat, tokenId: debugTargetTokenId) {
            pwrLines.append("Spot: \(debugSpotSummary(sp))")
        }
        debugPwrStatusLabel?.text = pwrLines.joined(separator: "\n")
        updateDebugSubTabUI()
    }

    private func debugSpotSummary(_ spot: LudoTokenSpot) -> String {
        switch spot {
        case .yard: return "yard"
        case .track(let p, let lap): return "track idx=\(p) lap=\(lap)"
        case .home(let s): return "home step=\(s)"
        case .finished: return "finished"
        }
    }

    /// Prefer the innermost named debug control (avoids matching `dbgPagePowerups` instead of `dbgPwrArm`).
    private func resolveDebugControlName(from hits: [SKNode]) -> String? {
        let priorityButtons: Set<String> = [
            "dbgPwrArm", "dbgPwrApply", "debugPanelDismiss",
            "dbgSubDice", "dbgSubPowerups",
        ]
        var best: (name: String, level: Int)?
        func recordCandidate(_ name: String, _ level: Int) {
            if best == nil || level < best!.level { best = (name, level) }
        }
        for node in hits {
            var c: SKNode? = node
            var level = 0
            while let x = c {
                if let n = x.name {
                    if priorityButtons.contains(n) { recordCandidate(n, level) }
                    else if n.hasPrefix("dbgPwrPick_") { recordCandidate(n, level) }
                    else if n.hasPrefix("dbgPwrSeat_") { recordCandidate(n, level) }
                    else if n.hasPrefix("dbgPwrTok_") { recordCandidate(n, level) }
                    else if n.hasPrefix("dbgDie") { recordCandidate(n, level) }
                    else if n == "dbgNextSeat" || n == "dbgClearDie" || n.hasPrefix("dbgPreset") {
                        recordCandidate(n, level)
                    }
                }
                c = x.parent
                level += 1
            }
        }
        return best?.name
    }

    @discardableResult
    private func handleDebugTouch(_ touch: UITouch) -> Bool {
        guard let root = debugPanelRoot else { return false }
        let loc = touch.location(in: root)
        let hits = root.nodes(at: loc)
        guard !hits.isEmpty else { return false }
        guard let name = resolveDebugControlName(from: hits) else { return false }

        if name == "debugPanelDismiss" {
            dismissDebugPanel()
            return true
        }

        if name == "dbgSubDice" {
            debugSubTab = .dice
            refreshDebugPanel()
            return true
        }
        if name == "dbgSubPowerups" {
            debugSubTab = .powerups
            refreshDebugPanel()
            return true
        }

        if name.hasPrefix("dbgPwrPick_"), let raw = name.split(separator: "_").last,
           let p = LudoPowerup(rawValue: String(raw)) {
            debugSelectedPowerup = p
            refreshDebugPanel()
            return true
        }

        if name.hasPrefix("dbgPwrSeat_"), let raw = name.split(separator: "_").last,
           let v = Int(raw), let s = LudoSeat(rawValue: v) {
            debugTargetSeat = s
            refreshDebugPanel()
            return true
        }

        if name.hasPrefix("dbgPwrTok_"), let raw = name.split(separator: "_").last,
           let t = Int(raw), (0..<4).contains(t) {
            debugTargetTokenId = t
            refreshDebugPanel()
            return true
        }

        if name == "dbgPwrApply" {
            debugStartSelectedPowerup()
            return true
        }

        if name == "dbgPwrArm" {
            guard debugSubTab == .powerups else {
                turnLabel?.text = "Switch to the Powerups tab to arm a token."
                return true
            }
            dismissTrapPlacementMode()
            dismissBlackholePlacementMode()
            dismissFreezeSelectionMode()
            dismissShieldSelectionMode()
            dismissDebugPanel()
            debugPowerupArmTap = true
            switch debugSelectedPowerup {
            case .freezeToken, .smallShield:
                debugArmAwaitingMysteryToken = true
            default:
                debugArmAwaitingMysteryToken = false
            }
            let validKeys = debugValidArmTokenKeys()
            if validKeys.isEmpty {
                cancelDebugArmMode()
                turnLabel?.text = "Debug: no valid tile/token for \(debugSelectedPowerup.displayName) right now."
                return true
            }
            switch debugSelectedPowerup {
            case .freezeToken, .smallShield:
                let applier = debugPowerupApplierSeat()
                hintLabel?.text = "Debug: tap your \(applier.displayName) token (token \(debugTargetTokenId + 1) or any of yours). Tap Debug to cancel."
            default:
                hintLabel?.text = "Debug: tap a highlighted token (\(debugSelectedPowerup.displayName)). Tap Debug to cancel."
            }
            refreshTokenVisuals()
            return true
        }

        if debugSubTab == .powerups { return false }

        if name.hasPrefix("dbgDie"), name.count == 7, let v = Int(String(name.dropFirst(6))), (1...6).contains(v) {
            applyDebugRoll(v)
            refreshDebugPanel()
            return true
        }

        switch name {
        case "dbgPresetGreenStart":
            let e = LudoBoardPath.publicPathEntryIndex(for: .green)
            engine.debugSetToken(for: .green, tokenId: 0, spot: .track(pathIndex: e, lapProgress: 52))
        case "dbgPresetGreenFork":
            let f = LudoBoardPath.publicPathForkIndexBeforeHomeColumn(for: .green)
            engine.debugSetToken(for: .green, tokenId: 0, spot: .track(pathIndex: f, lapProgress: 54))
        case "dbgPresetGreenHome4":
            engine.debugSetToken(for: .green, tokenId: 0, spot: .home(step: 4))
        case "dbgNextSeat":
            engine.debugRotateCurrentSeat()
            debugTargetSeat = engine.currentSeat
        case "dbgClearDie":
            debugStagedRoll = nil
        default:
            return false
        }

        syncTokenPositionsFromEngine()
        refreshTokenVisuals()
        refreshStrengthHud()
        refreshDebugPanel()
        return true
    }

    #endif
}
