//
//  LudoPassAndPlayEngine.swift
//  ludo
//
//  Pass-and-play: green starts, clockwise on the loop, six to leave yard, six or a capture earns another roll,
//  landing on a non-safe track cell sends any opponent pieces there back to their yard (six again to leave),
//  after enough steps on the loop to reach the white fork square (50 steps from the coloured start along the track) a piece may turn up its home column from that fork (two track steps before its star) without visiting the star first;
//  hub entry cannot overshoot (exact roll to HOME). The game ends when `playerCount - 1` seats have finished (one seat left); fully finished seats are skipped in turn order.
//

import Foundation

/// Token location: yard, main loop (with lap distance), coloured home stretch, or finished in the hub.
enum LudoTokenSpot: Equatable, Sendable {
    case yard
    /// `pathIndex` on the shared loop; `lapProgress` mirrors `LudoBoardPath.trackLapProgressForPosition` for that owner (steps from coloured start to this cell).
    case track(pathIndex: Int, lapProgress: Int)
    /// Steps 0…4 along the coloured column (`homeColumn` / `homeStretchCellsInGoalOrder`); step 5 = HOME (`finished`).
    case home(step: Int)
    case finished
}

/// Shown once at game start (no random first player).
struct LudoOpeningOutcome: Sendable {
    struct Round: Sendable {
        let rolls: [(seat: LudoSeat, value: Int)]
    }

    let rounds: [Round]
    let firstPlayer: LudoSeat
}

enum LudoGameplayRollOutcome: Equatable, Sendable {
    case passedNoMove(String)
    case needsTokenChoice(roll: Int, legalYard: Set<Int>, legalTrack: Set<Int>, legalHome: Set<Int>)
    /// `grantsExtraRoll` is true after rolling a six or after capturing an opponent on the shared track.
    case autoApplied(String, grantsExtraRoll: Bool)
    /// Game ended: enough players have finished (`n - 1` in an `n`-player game). `summary` is the last action message when present.
    case gameOver(placementLines: [String], summary: String)
}

/// Result of applying a token choice after a roll.
enum LudoTokenApplyOutcome: Equatable, Sendable {
    case applied(message: String, grantsExtraRoll: Bool)
    case gameOver(placementLines: [String], message: String)
}

/// Result of applying a mystery-tile powerup to the token that landed there.
enum LudoPowerupApplyOutcome: Equatable, Sendable {
    case applied(message: String)
    case noEffect(message: String)
    case gameOver(placementLines: [String], message: String)
    /// Trap (and similar): pick a board cell before the effect resolves.
    case awaitingTrapPlacement(message: String)
    /// Blackhole: pick a board cell before the effect resolves.
    case awaitingBlackholePlacement(message: String)
    /// Freeze Token: pick an opponent’s token on the track.
    case awaitingFreezeTarget(message: String)
    /// Small Shield: pick one of your own tokens on the track or home stretch.
    case awaitingSmallShieldTarget(message: String)
}

@MainActor
final class LudoPassAndPlayEngine {

    let playerCount: Int
    private(set) var activeSeatsOrdered: [LudoSeat]
    private(set) var currentSeatIndex: Int
    private(set) var tokens: [LudoSeat: [LudoTokenSpot]]
    private(set) var pendingChoice: (roll: Int, legalYard: Set<Int>, legalTrack: Set<Int>, legalHome: Set<Int>)?
    /// Seats that have brought all four tokens to HOME, in order (1st, 2nd, …) for pass-and-play placement.
    private(set) var finishOrder: [LudoSeat] = []

    /// Traps on the shared track (visible to all).
    private(set) var activeTraps: [LudoActiveTrap] = []
    /// Blackholes on the shared track (visible to all; persist after triggering).
    private(set) var activeBlackholes: [LudoActiveBlackhole] = []
    /// Placeholder hazard cells — blocks placement until a hazard powerup exists.
    private(set) var activeHazardCells: Set<GridCoord> = []
    private(set) var frozenTokens: [LudoFrozenToken] = []
    private(set) var activeShields: [LudoActiveShield] = []
    /// While set, the placer must pick a board cell via `placeTrap(at:placedBy:)`.
    private(set) var pendingTrapPlacement: (placedBy: LudoSeat, tokenId: Int)?
    /// While set, the placer must pick a board cell via `placeBlackhole(at:placedBy:)`.
    private(set) var pendingBlackholePlacement: (placedBy: LudoSeat, tokenId: Int)?
    /// While set, the applier must pick an opponent token via `applyFreeze(to:tokenId:appliedBy:)`.
    private(set) var pendingFreezeApplication: (appliedBy: LudoSeat, tokenId: Int)?
    /// While set, the applier must pick an own token via `applySmallShield(to:tokenId:appliedBy:)`.
    private(set) var pendingSmallShieldApplication: (appliedBy: LudoSeat, tokenId: Int)?
    /// Last token moved by `applyMove`; consumed by UI (e.g. mystery tile) after animations.
    private(set) var lastAppliedMove: (seat: LudoSeat, tokenId: Int)?

    /// Track square where a token landed before a trap sent it to the yard (for fade-out VFX).
    struct TrapKillVisualInfo: Equatable {
        let seat: LudoSeat
        let tokenId: Int
        let landingSpot: LudoTokenSpot
    }

    private(set) var pendingTrapKillVisual: TrapKillVisualInfo?

    var randomProvider: () -> Int = { Int.random(in: 1...6) }

    func consumeLastAppliedMove() -> (seat: LudoSeat, tokenId: Int)? {
        defer {
            lastAppliedMove = nil
            pendingTrapKillVisual = nil
        }
        return lastAppliedMove
    }

    func syncCurrentSeatSkippingFinishedPlayers() {
        skipFullyFinishedCurrentSeatIfNeeded()
    }

    init(playerCount: Int) {
        let n = min(4, max(2, playerCount))
        self.playerCount = n
        let active = LudoSeat.activeSeats(forPlayerCount: n)
        self.activeSeatsOrdered = LudoSeat.allCases.filter { active.contains($0) }
        self.tokens = [:]
        for s in activeSeatsOrdered {
            self.tokens[s] = Array(repeating: .yard, count: 4)
        }
        self.currentSeatIndex = Self.indexOfGreen(in: activeSeatsOrdered) ?? 0
        self.pendingChoice = nil
    }

    /// `true` once `playerCount - 1` different seats have brought all four tokens HOME (one seat still in play).
    var isGameOver: Bool {
        guard activeSeatsOrdered.count > 1 else { return false }
        return finishOrder.count >= activeSeatsOrdered.count - 1
    }

    /// Finish order (1st, 2nd, …) followed by any seat that did not finish (last place), for display.
    func finalStandingsOrdered() -> [LudoSeat] {
        var list = finishOrder
        for s in activeSeatsOrdered where !finishOrder.contains(s) {
            list.append(s)
        }
        return list
    }

    var currentSeat: LudoSeat {
        activeSeatsOrdered[currentSeatIndex]
    }

    /// **Green** always opens; returns an empty `rounds` array (no opening dice).
    func resolveOpening() -> LudoOpeningOutcome {
        pendingChoice = nil
        if let g = activeSeatsOrdered.first(where: { $0 == .green }) {
            currentSeatIndex = activeSeatsOrdered.firstIndex(of: g) ?? 0
        }
        return LudoOpeningOutcome(rounds: [], firstPlayer: .green)
    }

    func applyGameplayRoll(_ value: Int) -> LudoGameplayRollOutcome {
        let v = min(6, max(1, value))
        skipFullyFinishedCurrentSeatIfNeeded()
        if isGameOver {
            return .gameOver(placementLines: gameOverSummaryLines(), summary: "Game over.")
        }
        if activeSeatsOrdered.allSatisfy({ allTokensFinished(for: $0) }) {
            return .gameOver(placementLines: gameOverSummaryLines(), summary: "All players have finished.")
        }
        let seat = currentSeat
        guard let mine = tokens[seat] else {
            return .passedNoMove("Invalid state.")
        }

        let yardIds = Set((0..<4).filter { mine[$0] == .yard })
        let trackIds = Set((0..<4).filter {
            if case .track = mine[$0] { return true }
            return false
        })
        let homeIds = Set((0..<4).filter {
            if case .home = mine[$0] { return true }
            return false
        })

        let hasYard = !yardIds.isEmpty
        let hasTrackOrHome = !trackIds.isEmpty || !homeIds.isEmpty

        if !hasTrackOrHome && hasYard && v != 6 {
            advanceToNextSeat(afterRolling: v)
            return .passedNoMove("\(seat.displayName) rolled \(v) — need a 6 to start. Next player.")
        }

        var legalYard: Set<Int> = []
        var legalTrack: Set<Int> = []
        var legalHome: Set<Int> = []

        if v == 6, hasYard {
            legalYard = yardIds.filter { !isTokenFrozen(owner: seat, tokenId: $0) }
        }

        for i in trackIds {
            if isTokenFrozen(owner: seat, tokenId: i) { continue }
            if canApplyMove(seat: seat, from: mine[i], roll: v) != nil {
                legalTrack.insert(i)
            }
        }
        for i in homeIds {
            if isTokenFrozen(owner: seat, tokenId: i) { continue }
            if canApplyMove(seat: seat, from: mine[i], roll: v) != nil {
                legalHome.insert(i)
            }
        }

        let legal = legalYard.union(legalTrack).union(legalHome)
        if legal.isEmpty {
            advanceToNextSeat(afterRolling: v)
            return .passedNoMove("\(seat.displayName) rolled \(v). Next player.")
        }

        if legal.count == 1, let only = legal.first {
            let fromYard = legalYard.contains(only)
            let extra = applyMove(seat: seat, tokenId: only, roll: v, fromYard: fromYard)
            if isGameOver {
                return .gameOver(placementLines: gameOverSummaryLines(), summary: extra.message)
            }
            return .autoApplied(extra.message, grantsExtraRoll: extra.extraTurn)
        }

        pendingChoice = (roll: v, legalYard: legalYard, legalTrack: legalTrack, legalHome: legalHome)
        return .needsTokenChoice(roll: v, legalYard: legalYard, legalTrack: legalTrack, legalHome: legalHome)
    }

    func applyTokenChoice(seat: LudoSeat, tokenId: Int) -> LudoTokenApplyOutcome? {
        guard seat == currentSeat, let p = pendingChoice, tokens[seat] != nil else { return nil }
        guard (0..<4).contains(tokenId) else { return nil }
        let fromYard = p.legalYard.contains(tokenId)
        let fromTrack = p.legalTrack.contains(tokenId)
        let fromHome = p.legalHome.contains(tokenId)
        guard fromYard || fromTrack || fromHome else { return nil }
        if fromYard { guard p.roll == 6 else { return nil } }

        pendingChoice = nil
        let extra = applyMove(seat: seat, tokenId: tokenId, roll: p.roll, fromYard: fromYard)
        if isGameOver {
            return .gameOver(placementLines: gameOverSummaryLines(), message: extra.message)
        }
        return .applied(message: extra.message, grantsExtraRoll: extra.extraTurn)
    }

    func hasPendingChoice(for seat: LudoSeat) -> Bool {
        seat == currentSeat && pendingChoice != nil
    }

    private struct MoveResult {
        let message: String
        let extraTurn: Bool
    }

    private func applyMove(seat: LudoSeat, tokenId: Int, roll: Int, fromYard: Bool) -> MoveResult {
        pendingTrapKillVisual = nil
        guard var mine = tokens[seat] else {
            return MoveResult(message: "Error.", extraTurn: false)
        }

        if fromYard {
            let entry = LudoBoardPath.publicPathEntryIndex(for: seat)
            let entrySpot: LudoTokenSpot = .track(pathIndex: entry, lapProgress: 0)
            if let bh = resolveBlackholeOnLand(moverSeat: seat, tokenId: tokenId, landingSpot: entrySpot) {
                mine[tokenId] = bh.finalSpot
                tokens[seat] = mine
                if case .yard = bh.finalSpot {
                    clearFreeze(owner: seat, tokenId: tokenId)
                    clearShield(owner: seat, tokenId: tokenId)
                }
                let extra = roll == 6
                if !isGameOver, !extra { advanceToNextSeat(afterRolling: roll) }
                var msg = "\(seat.displayName) brought a token out onto the start square."
                if let bhMsg = bh.hazardSummary { msg += " \(bhMsg)" }
                lastAppliedMove = (seat, tokenId)
                return MoveResult(message: msg, extraTurn: extra)
            }
            mine[tokenId] = entrySpot
            tokens[seat] = mine
            let capture = captureOpponentsOnPublicTrackIfAllowed(moverSeat: seat, publicPathIndex: entry)
            let extra = roll == 6 || capture.didSendAnyoneToYard
            if !isGameOver, !extra { advanceToNextSeat(afterRolling: roll) }
            var msg = "\(seat.displayName) brought a token out onto the start square."
            if let c = capture.summary {
                msg += " \(c)"
            }
            lastAppliedMove = (seat, tokenId)
            return MoveResult(message: msg, extraTurn: extra)
        }

        let from = mine[tokenId]
        if let bh = resolveBlackholeAlongPath(moverSeat: seat, tokenId: tokenId, from: from, roll: roll) {
            mine[tokenId] = bh.finalSpot
            tokens[seat] = mine
            if case .yard = bh.finalSpot {
                clearFreeze(owner: seat, tokenId: tokenId)
                clearShield(owner: seat, tokenId: tokenId)
            }
            if case .finished = bh.finalSpot {
                clearShield(owner: seat, tokenId: tokenId)
                recordFinishPlacementIfSeatCompleted(seat)
            }
            let reachedHome = if case .finished = bh.finalSpot { true } else { false }
            let extra = roll == 6 || reachedHome
            if !isGameOver, !extra { advanceToNextSeat(afterRolling: roll) }
            var msg: String
            switch bh.finalSpot {
            case .finished:
                let place = finishOrder.firstIndex(of: seat).map { $0 + 1 }
                let suffix = place.map { " (\(ordinal($0)) place)." } ?? "."
                msg = "\(seat.displayName) reached HOME\(suffix)"
            case .home:
                msg = "\(seat.displayName) moved on the home stretch."
            case .track:
                msg = "\(seat.displayName) stopped on the track (blackhole)."
            case .yard:
                msg = "\(seat.displayName) was sucked into a blackhole."
            }
            if let h = bh.hazardSummary { msg += " \(h)" }
            lastAppliedMove = (seat, tokenId)
            return MoveResult(message: msg, extraTurn: extra)
        }

        guard let newSpot = canApplyMove(seat: seat, from: from, roll: roll) else {
            return MoveResult(message: "Illegal move.", extraTurn: false)
        }

        let landing = resolveTokenLanding(moverSeat: seat, tokenId: tokenId, landingSpot: newSpot)
        mine[tokenId] = landing.finalSpot
        tokens[seat] = mine
        if case .yard = landing.finalSpot {
            clearFreeze(owner: seat, tokenId: tokenId)
            clearShield(owner: seat, tokenId: tokenId)
        }

        if case .finished = landing.finalSpot {
            clearShield(owner: seat, tokenId: tokenId)
            recordFinishPlacementIfSeatCompleted(seat)
        }

        let capturedSummary = landing.captureSummary
        let reachedHome = if case .finished = landing.finalSpot { true } else { false }

        let extra = roll == 6 || landing.didCaptureToYard || reachedHome
        if !isGameOver, !extra { advanceToNextSeat(afterRolling: roll) }

        var msg: String
        switch landing.finalSpot {
        case .finished:
            let place = finishOrder.firstIndex(of: seat).map { $0 + 1 }
            let suffix = place.map { " (\(ordinal($0)) place)." } ?? "."
            msg = "\(seat.displayName) reached HOME\(suffix)"
        case .home:
            msg = "\(seat.displayName) moved on the home stretch."
        case .track:
            msg = "\(seat.displayName) moved \(roll) steps clockwise on the track."
        case .yard:
            msg = "\(seat.displayName) moved."
        }
        if let trap = landing.trapSummary {
            msg += " \(trap)"
        }
        if let c = capturedSummary {
            msg += " \(c)"
        }
        lastAppliedMove = (seat, tokenId)
        return MoveResult(message: msg, extraTurn: extra)
    }

    private struct CaptureOnLandResult {
        var summary: String?
        var didSendAnyoneToYard: Bool
    }

    private struct LandingResolution {
        var finalSpot: LudoTokenSpot
        var captureSummary: String?
        var trapSummary: String?
        var didCaptureToYard: Bool
    }

    private struct HazardLandingResolution {
        var finalSpot: LudoTokenSpot
        var hazardSummary: String?
    }

    private func blackholeAt(cell: GridCoord) -> Bool {
        activeBlackholes.contains { $0.cell == cell }
    }

    /// Each intermediate spot when moving `roll` steps (inclusive of each step landing).
    private func steppedSpotsAlongMove(seat: LudoSeat, from: LudoTokenSpot, roll: Int) -> [LudoTokenSpot]? {
        var current = from
        var steps: [LudoTokenSpot] = []
        for _ in 0..<roll {
            guard let next = canApplyMove(seat: seat, from: current, roll: 1) else { return nil }
            steps.append(next)
            current = next
        }
        return steps
    }

    /// First blackhole on the movement path (pass-through or landing).
    private func resolveBlackholeAlongPath(
        moverSeat: LudoSeat,
        tokenId: Int,
        from: LudoTokenSpot,
        roll: Int
    ) -> HazardLandingResolution? {
        guard let steps = steppedSpotsAlongMove(seat: moverSeat, from: from, roll: roll) else { return nil }
        for spot in steps {
            guard let coord = LudoBoardPath.gridCoord(for: moverSeat, tokenId: tokenId, spot: spot),
                  blackholeAt(cell: coord) else { continue }
            return resolveBlackholeHit(moverSeat: moverSeat, tokenId: tokenId, at: spot)
        }
        return nil
    }

    private func resolveBlackholeOnLand(
        moverSeat: LudoSeat,
        tokenId: Int,
        landingSpot: LudoTokenSpot
    ) -> HazardLandingResolution? {
        guard let coord = LudoBoardPath.gridCoord(for: moverSeat, tokenId: tokenId, spot: landingSpot),
              blackholeAt(cell: coord) else { return nil }
        return resolveBlackholeHit(moverSeat: moverSeat, tokenId: tokenId, at: landingSpot)
    }

    private func resolveBlackholeHit(
        moverSeat: LudoSeat,
        tokenId: Int,
        at spot: LudoTokenSpot
    ) -> HazardLandingResolution {
        let shieldLabel = activeShields.first(where: { $0.owner == moverSeat && $0.tokenId == tokenId })
            .map { $0.kind == .small ? "Small Shield" : "Big Shield" }
        if consumeShieldBlockingHarm(owner: moverSeat, tokenId: tokenId, effectName: "blackhole") {
            let kindLabel = shieldLabel ?? "shield"
            return HazardLandingResolution(
                finalSpot: spot,
                hazardSummary: "Blackhole — \(moverSeat.displayName)'s token was protected (\(kindLabel)); stopped on the tile."
            )
        }
        pendingTrapKillVisual = TrapKillVisualInfo(seat: moverSeat, tokenId: tokenId, landingSpot: spot)
        return HazardLandingResolution(
            finalSpot: .yard,
            hazardSummary: "Blackhole — \(moverSeat.displayName)'s token was sucked in and sent to the yard."
        )
    }

    private struct TrapTriggerResult {
        let message: String
        let sentToYard: Bool
        let trackPathIndex: Int?
    }

    /// Trap is checked before capture; a trap kill skips capture on that square.
    private func resolveTokenLanding(
        moverSeat: LudoSeat,
        tokenId: Int,
        landingSpot: LudoTokenSpot
    ) -> LandingResolution {
        if let trapMsg = applyTrapTriggerIfNeeded(moverSeat: moverSeat, tokenId: tokenId, landingSpot: landingSpot) {
            if trapMsg.sentToYard {
                pendingTrapKillVisual = TrapKillVisualInfo(
                    seat: moverSeat,
                    tokenId: tokenId,
                    landingSpot: landingSpot
                )
                return LandingResolution(
                    finalSpot: .yard,
                    captureSummary: nil,
                    trapSummary: trapMsg.message,
                    didCaptureToYard: false
                )
            }
            if let pathIndex = trapMsg.trackPathIndex {
                let capture = captureOpponentsOnPublicTrackIfAllowed(moverSeat: moverSeat, publicPathIndex: pathIndex)
                return LandingResolution(
                    finalSpot: landingSpot,
                    captureSummary: capture.summary,
                    trapSummary: trapMsg.message,
                    didCaptureToYard: capture.didSendAnyoneToYard
                )
            }
        }

        var capture: CaptureOnLandResult?
        if case .track(let pathIndex, _) = landingSpot {
            capture = captureOpponentsOnPublicTrackIfAllowed(moverSeat: moverSeat, publicPathIndex: pathIndex)
        }
        return LandingResolution(
            finalSpot: landingSpot,
            captureSummary: capture?.summary,
            trapSummary: nil,
            didCaptureToYard: capture?.didSendAnyoneToYard ?? false
        )
    }

    private func applyTrapTriggerIfNeeded(
        moverSeat: LudoSeat,
        tokenId: Int,
        landingSpot: LudoTokenSpot
    ) -> TrapTriggerResult? {
        guard let landingCoord = LudoBoardPath.gridCoord(for: moverSeat, tokenId: tokenId, spot: landingSpot),
              let trapIndex = activeTraps.firstIndex(where: { $0.cell == landingCoord }) else { return nil }

        activeTraps.remove(at: trapIndex)
        let shieldLabel = activeShields.first(where: { $0.owner == moverSeat && $0.tokenId == tokenId })
            .map { $0.kind == .small ? "Small Shield" : "Big Shield" }
        if consumeShieldBlockingHarm(owner: moverSeat, tokenId: tokenId, effectName: "trap") {
            let trackPathIndex: Int? = if case .track(let pathIndex, _) = landingSpot { pathIndex } else { nil }
            let kindLabel = shieldLabel ?? "shield"
            return TrapTriggerResult(
                message: "Trap triggered — \(moverSeat.displayName)'s token was protected (\(kindLabel)); trap removed.",
                sentToYard: false,
                trackPathIndex: trackPathIndex
            )
        }
        return TrapTriggerResult(
            message: "Trap triggered — \(moverSeat.displayName)'s token sent to the yard; trap removed.",
            sentToYard: true,
            trackPathIndex: nil
        )
    }

    /// Blocks one harmful hit (trap, capture, freeze, etc.) and removes the shield.
    private func consumeShieldBlockingHarm(owner: LudoSeat, tokenId: Int, effectName _: String) -> Bool {
        guard let index = activeShields.firstIndex(where: { $0.owner == owner && $0.tokenId == tokenId }) else {
            return false
        }
        activeShields.remove(at: index)
        return true
    }

    func isTokenShielded(owner: LudoSeat, tokenId: Int) -> Bool {
        activeShields.contains { $0.owner == owner && $0.tokenId == tokenId }
    }

    func shieldKind(for owner: LudoSeat, tokenId: Int) -> LudoShieldKind? {
        activeShields.first(where: { $0.owner == owner && $0.tokenId == tokenId })?.kind
    }

    private func clearShield(owner: LudoSeat, tokenId: Int) {
        activeShields.removeAll { $0.owner == owner && $0.tokenId == tokenId }
    }

    private func clearShieldsForOwnerAfterTurnEnded(_ owner: LudoSeat) {
        activeShields.removeAll { $0.owner == owner }
    }

    /// Returns capture summary and whether anyone was sent to the yard (drives extra-roll rules).
    private func captureOpponentsOnPublicTrackIfAllowed(
        moverSeat: LudoSeat,
        publicPathIndex: Int
    ) -> CaptureOnLandResult {
        let idx = (publicPathIndex % 52 + 52) % 52
        guard LudoBoardPath.isCaptureAllowed(onPublicPathIndex: idx) else {
            return CaptureOnLandResult(summary: nil, didSendAnyoneToYard: false)
        }

        var victims: [(seat: LudoSeat, count: Int)] = []
        var shieldBlocks: [String] = []
        for other in activeSeatsOrdered where other != moverSeat {
            guard var row = tokens[other] else { continue }
            var sent = 0
            for tid in 0..<4 {
                guard case .track(let p, _) = row[tid], (p % 52 + 52) % 52 == idx else { continue }
                let shieldKind = activeShields.first(where: { $0.owner == other && $0.tokenId == tid })?.kind
                if consumeShieldBlockingHarm(owner: other, tokenId: tid, effectName: "capture") {
                    let label = shieldKind == .big ? "Big Shield" : "Small Shield"
                    shieldBlocks.append("\(other.displayName)'s token (\(label))")
                    continue
                }
                row[tid] = .yard
                clearFreeze(owner: other, tokenId: tid)
                clearShield(owner: other, tokenId: tid)
                sent += 1
            }
            if sent > 0 {
                tokens[other] = row
                victims.append((other, sent))
            }
        }

        var parts: [String] = []
        if !victims.isEmpty {
            let captureParts = victims.map { v in
                v.count == 1
                    ? "sent \(v.seat.displayName)'s token to the yard"
                    : "sent \(v.count) of \(v.seat.displayName)'s tokens to the yard"
            }
            parts.append("Captured — " + captureParts.joined(separator: "; ") + ".")
        }
        if !shieldBlocks.isEmpty {
            parts.append("Shield blocked capture — " + shieldBlocks.joined(separator: "; ") + ".")
        }
        let summary = parts.isEmpty ? nil : parts.joined(separator: " ")
        return CaptureOnLandResult(summary: summary, didSendAnyoneToYard: !victims.isEmpty)
    }

    func gameOverSummaryLines() -> [String] {
        var lines: [String] = []
        var place = 1
        for s in finishOrder {
            lines.append("\(place). \(s.displayName)")
            place += 1
        }
        for s in activeSeatsOrdered where !finishOrder.contains(s) {
            lines.append("\(place). \(s.displayName) — did not finish")
            place += 1
        }
        return lines
    }

    private func advanceToNextSeat(afterRolling _: Int) {
        pendingChoice = nil
        let ownerWhoFinished = currentSeat
        clearFreezeForOwnerAfterTurnEnded(ownerWhoFinished)
        clearShieldsForOwnerAfterTurnEnded(ownerWhoFinished)
        let finishedIdx = currentSeatIndex
        let n = activeSeatsOrdered.count
        guard n > 0 else { return }
        var idx = currentSeatIndex
        for _ in 0..<n {
            idx = (idx + 1) % n
            let next = activeSeatsOrdered[idx]
            if !allTokensFinished(for: next) {
                currentSeatIndex = idx
                if idx < finishedIdx {
                    tickHazardRoundsAfterFullPassAndPlayRound()
                }
                return
            }
        }
        currentSeatIndex = idx % n
        if currentSeatIndex < finishedIdx {
            tickHazardRoundsAfterFullPassAndPlayRound()
        }
    }

    /// One full round = every active seat has taken a turn (same wrap rule as mystery-tile shuffle).
    private func tickHazardRoundsAfterFullPassAndPlayRound() {
        if !activeTraps.isEmpty {
            activeTraps = activeTraps.compactMap { trap in
                var t = trap
                t.fullRoundsRemaining -= 1
                return t.fullRoundsRemaining > 0 ? t : nil
            }
        }
        if !activeBlackholes.isEmpty {
            activeBlackholes = activeBlackholes.compactMap { hole in
                var h = hole
                h.fullRoundsRemaining -= 1
                return h.fullRoundsRemaining > 0 ? h : nil
            }
        }
    }

    private func extraHazardCellsForPlacement() -> Set<GridCoord> {
        activeHazardCells
    }

    private func allTokensFinished(for seat: LudoSeat) -> Bool {
        guard let row = tokens[seat] else { return false }
        return row.allSatisfy { if case .finished = $0 { return true }; return false }
    }

    private func recordFinishPlacementIfSeatCompleted(_ seat: LudoSeat) {
        guard allTokensFinished(for: seat), !finishOrder.contains(seat) else { return }
        finishOrder.append(seat)
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }

    /// If the current seat has already placed all tokens in the hub, advance until someone still has work (or all are done).
    private func skipFullyFinishedCurrentSeatIfNeeded() {
        let n = activeSeatsOrdered.count
        guard n > 0 else { return }
        var hops = 0
        while hops < n, allTokensFinished(for: currentSeat) {
            pendingChoice = nil
            currentSeatIndex = (currentSeatIndex + 1) % n
            hops += 1
        }
    }

    func spot(for seat: LudoSeat, tokenId: Int) -> LudoTokenSpot? {
        guard let row = tokens[seat], (0..<4).contains(tokenId) else { return nil }
        return row[tokenId]
    }

    /// Applies a mystery powerup to the token that triggered it. Does not change whose turn it is.
    func applyPowerup(_ powerup: LudoPowerup, seat: LudoSeat, tokenId: Int) -> LudoPowerupApplyOutcome {
        guard powerup.isImplemented else {
            return .noEffect(message: "\(powerup.displayName) is not available yet.")
        }
        switch powerup {
        case .dash:
            return applyForwardPowerup(seat: seat, tokenId: tokenId, steps: 3, powerupName: powerup.displayName)
        case .trap:
            return beginTrapPlacement(seat: seat, tokenId: tokenId)
        case .blackhole:
            return beginBlackholePlacement(seat: seat, tokenId: tokenId)
        case .freezeToken:
            return beginFreezeTargetSelection(seat: seat, tokenId: tokenId)
        case .swap:
            return applySwapPowerup(seat: seat, tokenId: tokenId)
        case .smallShield:
            return beginSmallShieldTargetSelection(seat: seat, tokenId: tokenId)
        case .bigShield:
            return .noEffect(message: "\(powerup.displayName) is not available yet.")
        }
    }

    func validTrapPlacementCells() -> [GridCoord] {
        LudoTrapPlacement.validPlacementCells(
            activeSeats: activeSeatsOrdered,
            tokens: tokens,
            activeTraps: activeTraps,
            hazardCells: activeHazardCells.union(LudoBlackholePlacement.blackholeCells(from: activeBlackholes))
        )
    }

    func validBlackholePlacementCells() -> [GridCoord] {
        LudoBlackholePlacement.validPlacementCells(
            activeSeats: activeSeatsOrdered,
            tokens: tokens,
            activeTraps: activeTraps,
            activeBlackholes: activeBlackholes,
            extraHazardCells: extraHazardCellsForPlacement()
        )
    }

    func cancelBlackholePlacement() {
        pendingBlackholePlacement = nil
    }

    func placeBlackhole(at cell: GridCoord, placedBy: LudoSeat) -> LudoPowerupApplyOutcome {
        let powerupName = LudoPowerup.blackhole.displayName
        guard let pending = pendingBlackholePlacement, pending.placedBy == placedBy else {
            return .noEffect(message: "\(powerupName) — no blackhole placement in progress.")
        }
        guard LudoBlackholePlacement.canPlaceBlackhole(
            at: cell,
            activeSeats: activeSeatsOrdered,
            tokens: tokens,
            trapCells: LudoTrapPlacement.trapCells(from: activeTraps),
            blackholeCells: LudoBlackholePlacement.blackholeCells(from: activeBlackholes),
            occupiedCells: LudoBlackholePlacement.occupiedTrackCells(tokens: tokens),
            bufferCells: LudoBlackholePlacement.placementBufferCells(),
            extraHazardCells: extraHazardCellsForPlacement()
        ) else {
            return .noEffect(message: "\(powerupName) — that tile is not valid.")
        }
        pendingBlackholePlacement = nil
        activeBlackholes.append(LudoActiveBlackhole(
            cell: cell,
            placedBy: placedBy,
            fullRoundsRemaining: LudoActiveBlackhole.maxFullRounds
        ))
        let msg = "\(placedBy.displayName) — \(powerupName): placed on track (visible to all, \(LudoActiveBlackhole.maxFullRounds) full rounds)."
        if isGameOver {
            return .gameOver(placementLines: gameOverSummaryLines(), message: msg)
        }
        return .applied(message: msg)
    }

    func cancelTrapPlacement() {
        pendingTrapPlacement = nil
    }

    func placeTrap(at cell: GridCoord, placedBy: LudoSeat) -> LudoPowerupApplyOutcome {
        let powerupName = LudoPowerup.trap.displayName
        guard let pending = pendingTrapPlacement, pending.placedBy == placedBy else {
            return .noEffect(message: "\(powerupName) — no trap placement in progress.")
        }
        let trapCells = LudoTrapPlacement.trapCells(from: activeTraps)
        guard LudoTrapPlacement.canPlaceTrap(
            at: cell,
            activeSeats: activeSeatsOrdered,
            tokens: tokens,
            occupiedTrapCells: trapCells,
            hazardCells: activeHazardCells.union(LudoBlackholePlacement.blackholeCells(from: activeBlackholes))
        ) else {
            return .noEffect(message: "\(powerupName) — that tile is not valid.")
        }
        pendingTrapPlacement = nil
        activeTraps.append(LudoActiveTrap(
            cell: cell,
            placedBy: placedBy,
            fullRoundsRemaining: LudoActiveTrap.maxFullRounds
        ))
        let msg = "\(placedBy.displayName) — \(powerupName): placed on track (visible to all, \(LudoActiveTrap.maxFullRounds) full rounds)."
        if isGameOver {
            return .gameOver(placementLines: gameOverSummaryLines(), message: msg)
        }
        return .applied(message: msg)
    }

    func isTokenFrozen(owner: LudoSeat, tokenId: Int) -> Bool {
        frozenTokens.contains { $0.owner == owner && $0.tokenId == tokenId }
    }

    private var shieldedTokenKeys: Set<LudoTokenShieldKey> {
        Set(activeShields.map { LudoTokenShieldKey($0.owner, $0.tokenId) })
    }

    func validFreezeTargets(for applier: LudoSeat) -> [(seat: LudoSeat, tokenId: Int)] {
        LudoFreezeTargetRules.validTargets(
            applier: applier,
            activeSeats: activeSeatsOrdered,
            tokens: tokens,
            frozen: frozenTokens,
            shieldedTokenKeys: shieldedTokenKeys
        )
    }

    func cancelFreezeSelection() {
        pendingFreezeApplication = nil
    }

    func applyFreeze(to owner: LudoSeat, tokenId: Int, appliedBy: LudoSeat) -> LudoPowerupApplyOutcome {
        let powerupName = LudoPowerup.freezeToken.displayName
        guard let pending = pendingFreezeApplication, pending.appliedBy == appliedBy else {
            return .noEffect(message: "\(powerupName) — no freeze selection in progress.")
        }
        if isTokenShielded(owner: owner, tokenId: tokenId) {
            let label = shieldKind(for: owner, tokenId: tokenId).map { $0 == .small ? "Small Shield" : "Big Shield" } ?? "shield"
            _ = consumeShieldBlockingHarm(owner: owner, tokenId: tokenId, effectName: "freeze")
            pendingFreezeApplication = nil
            let msg = "\(appliedBy.displayName) — \(powerupName): \(owner.displayName)'s token was protected (\(label)); not frozen."
            if isGameOver {
                return .gameOver(placementLines: gameOverSummaryLines(), message: msg)
            }
            return .applied(message: msg)
        }
        guard LudoFreezeTargetRules.canFreeze(
            owner: owner,
            tokenId: tokenId,
            applier: appliedBy,
            activeSeats: activeSeatsOrdered,
            tokens: tokens,
            frozen: frozenTokens,
            shieldedTokenKeys: shieldedTokenKeys
        ) else {
            return .noEffect(message: "\(powerupName) — that token cannot be frozen.")
        }
        pendingFreezeApplication = nil
        frozenTokens.append(LudoFrozenToken(owner: owner, tokenId: tokenId, frozenBy: appliedBy))
        let msg = "\(appliedBy.displayName) — \(powerupName): froze \(owner.displayName)'s token \(tokenId + 1) (visible to all; can't move next turn)."
        if isGameOver {
            return .gameOver(placementLines: gameOverSummaryLines(), message: msg)
        }
        return .applied(message: msg)
    }

    private func beginFreezeTargetSelection(seat: LudoSeat, tokenId: Int) -> LudoPowerupApplyOutcome {
        let powerupName = LudoPowerup.freezeToken.displayName
        if isGameOver {
            return .noEffect(message: "Game over.")
        }
        guard spot(for: seat, tokenId: tokenId) != nil else {
            return .noEffect(message: "\(powerupName) — invalid token.")
        }
        let valid = validFreezeTargets(for: seat)
        if valid.isEmpty {
            return .noEffect(message: "\(powerupName) — no valid opponent token on the track to freeze.")
        }
        pendingFreezeApplication = (appliedBy: seat, tokenId: tokenId)
        return .awaitingFreezeTarget(message: "\(seat.displayName) — tap an opponent's token on the track to freeze.")
    }

    private func clearFreeze(owner: LudoSeat, tokenId: Int) {
        frozenTokens.removeAll { $0.owner == owner && $0.tokenId == tokenId }
    }

    private func clearFreezeForOwnerAfterTurnEnded(_ owner: LudoSeat) {
        frozenTokens.removeAll { $0.owner == owner }
    }

    func validSmallShieldTargets(for applier: LudoSeat) -> [(seat: LudoSeat, tokenId: Int)] {
        LudoSmallShieldTargetRules.validTargets(
            applier: applier,
            tokens: tokens,
            shields: activeShields
        )
    }

    func cancelSmallShieldSelection() {
        pendingSmallShieldApplication = nil
    }

    func applySmallShield(to owner: LudoSeat, tokenId: Int, appliedBy: LudoSeat) -> LudoPowerupApplyOutcome {
        let powerupName = LudoPowerup.smallShield.displayName
        guard let pending = pendingSmallShieldApplication, pending.appliedBy == appliedBy else {
            return .noEffect(message: "\(powerupName) — no shield selection in progress.")
        }
        guard LudoSmallShieldTargetRules.canApply(
            owner: owner,
            tokenId: tokenId,
            applier: appliedBy,
            tokens: tokens,
            shields: activeShields
        ) else {
            return .noEffect(message: "\(powerupName) — that token cannot be shielded.")
        }
        pendingSmallShieldApplication = nil
        activeShields.append(LudoActiveShield(
            owner: owner,
            tokenId: tokenId,
            kind: .small,
            appliedBy: appliedBy
        ))
        let msg = "\(appliedBy.displayName) — \(powerupName): token \(tokenId + 1) has a 1-hit shield (visible to all; expires after your next turn)."
        if isGameOver {
            return .gameOver(placementLines: gameOverSummaryLines(), message: msg)
        }
        return .applied(message: msg)
    }

    private func beginSmallShieldTargetSelection(seat: LudoSeat, tokenId: Int) -> LudoPowerupApplyOutcome {
        let powerupName = LudoPowerup.smallShield.displayName
        if isGameOver {
            return .noEffect(message: "Game over.")
        }
        guard spot(for: seat, tokenId: tokenId) != nil else {
            return .noEffect(message: "\(powerupName) — invalid token.")
        }
        let valid = validSmallShieldTargets(for: seat)
        if valid.isEmpty {
            return .noEffect(message: "\(powerupName) — no valid token on the track or home stretch to shield.")
        }
        pendingSmallShieldApplication = (appliedBy: seat, tokenId: tokenId)
        return .awaitingSmallShieldTarget(message: "\(seat.displayName) — tap one of your tokens on the track or home stretch.")
    }

    private func beginTrapPlacement(seat: LudoSeat, tokenId: Int) -> LudoPowerupApplyOutcome {
        let powerupName = LudoPowerup.trap.displayName
        if isGameOver {
            return .noEffect(message: "Game over.")
        }
        guard spot(for: seat, tokenId: tokenId) != nil else {
            return .noEffect(message: "\(powerupName) — invalid token.")
        }
        let valid = validTrapPlacementCells()
        if valid.isEmpty {
            return .noEffect(message: "\(powerupName) — no valid tile to place a trap.")
        }
        pendingTrapPlacement = (placedBy: seat, tokenId: tokenId)
        return .awaitingTrapPlacement(message: "\(seat.displayName) — tap a white track tile to place \(powerupName).")
    }

    private func beginBlackholePlacement(seat: LudoSeat, tokenId: Int) -> LudoPowerupApplyOutcome {
        let powerupName = LudoPowerup.blackhole.displayName
        if isGameOver {
            return .noEffect(message: "Game over.")
        }
        guard spot(for: seat, tokenId: tokenId) != nil else {
            return .noEffect(message: "\(powerupName) — invalid token.")
        }
        let valid = validBlackholePlacementCells()
        if valid.isEmpty {
            return .noEffect(message: "\(powerupName) — no valid tile to place a blackhole.")
        }
        pendingBlackholePlacement = (placedBy: seat, tokenId: tokenId)
        return .awaitingBlackholePlacement(message: "\(seat.displayName) — tap a highlighted track tile to place \(powerupName).")
    }

    private func applySwapPowerup(seat: LudoSeat, tokenId: Int) -> LudoPowerupApplyOutcome {
        let powerupName = LudoPowerup.swap.displayName
        let searchSteps = LudoPowerup.swapSearchSteps
        if isGameOver {
            return .noEffect(message: "Game over.")
        }
        guard let from = spot(for: seat, tokenId: tokenId) else {
            return .noEffect(message: "\(powerupName) — invalid token.")
        }
        switch from {
        case .yard, .finished:
            return .noEffect(message: "\(seat.displayName): \(powerupName) only works on the track or home stretch.")
        case .home, .track:
            break
        }
        guard let found = firstSwapTargetClockwise(
            moverSeat: seat,
            moverTokenId: tokenId,
            from: from,
            maxSteps: searchSteps
        ) else {
            return .noEffect(
                message: "\(seat.displayName): \(powerupName) — no opponent token within \(searchSteps) spaces clockwise."
            )
        }
        let target = found.target
        guard var moverRow = tokens[seat], var targetRow = tokens[target.seat] else {
            return .noEffect(message: "\(powerupName) — invalid state.")
        }
        let moverSpot = moverRow[tokenId]
        let targetSpot = targetRow[target.tokenId]
        let (moverNew, targetNew) = spotsAfterSwap(
            moverSeat: seat,
            targetSeat: target.seat,
            moverSpot: moverSpot,
            targetSpot: targetSpot
        )
        moverRow[tokenId] = moverNew
        targetRow[target.tokenId] = targetNew
        tokens[seat] = moverRow
        tokens[target.seat] = targetRow

        var extraParts: [String] = []
        if let bh = resolveBlackholeOnLand(moverSeat: seat, tokenId: tokenId, landingSpot: moverNew) {
            moverRow[tokenId] = bh.finalSpot
            tokens[seat] = moverRow
            if case .yard = bh.finalSpot {
                clearFreeze(owner: seat, tokenId: tokenId)
                clearShield(owner: seat, tokenId: tokenId)
            }
            if let s = bh.hazardSummary { extraParts.append(s) }
        }
        if let bh = resolveBlackholeOnLand(moverSeat: target.seat, tokenId: target.tokenId, landingSpot: targetNew) {
            targetRow[target.tokenId] = bh.finalSpot
            tokens[target.seat] = targetRow
            if case .yard = bh.finalSpot {
                clearFreeze(owner: target.seat, tokenId: target.tokenId)
                clearShield(owner: target.seat, tokenId: target.tokenId)
            }
            if let s = bh.hazardSummary { extraParts.append(s) }
        }

        let targetDesc = "\(target.seat.displayName)'s token"
        let stepsPhrase = found.stepsAhead == 1 ? "1 space ahead" : "\(found.stepsAhead) spaces ahead"
        var msg = "\(seat.displayName) — \(powerupName): swapped with \(targetDesc) (\(stepsPhrase))."
        if !extraParts.isEmpty {
            msg += " " + extraParts.joined(separator: " ")
        }
        if isGameOver {
            return .gameOver(placementLines: gameOverSummaryLines(), message: msg)
        }
        return .applied(message: msg)
    }

    /// Exchange board positions; track `lapProgress` is derived from each token owner’s new path index.
    private func spotsAfterSwap(
        moverSeat: LudoSeat,
        targetSeat: LudoSeat,
        moverSpot: LudoTokenSpot,
        targetSpot: LudoTokenSpot
    ) -> (mover: LudoTokenSpot, target: LudoTokenSpot) {
        switch (moverSpot, targetSpot) {
        case (.track(let moverPath, _), .track(let targetPath, _)):
            return (
                .track(
                    pathIndex: targetPath,
                    lapProgress: LudoBoardPath.trackLapProgressForPosition(seat: moverSeat, pathIndex: targetPath)
                ),
                .track(
                    pathIndex: moverPath,
                    lapProgress: LudoBoardPath.trackLapProgressForPosition(seat: targetSeat, pathIndex: moverPath)
                )
            )
        case (.home(let moverStep), .home(let targetStep)):
            return (.home(step: targetStep), .home(step: moverStep))
        case (.track(let moverPath, _), .home(let targetStep)):
            return (
                .home(step: targetStep),
                .track(
                    pathIndex: moverPath,
                    lapProgress: LudoBoardPath.trackLapProgressForPosition(seat: targetSeat, pathIndex: moverPath)
                )
            )
        case (.home(let moverStep), .track(let targetPath, _)):
            return (
                .track(
                    pathIndex: targetPath,
                    lapProgress: LudoBoardPath.trackLapProgressForPosition(seat: moverSeat, pathIndex: targetPath)
                ),
                .home(step: moverStep)
            )
        default:
            return (targetSpot, moverSpot)
        }
    }

    /// First **opponent** token on the mover’s clockwise path within `maxSteps` (own tokens are ignored).
    private func firstSwapTargetClockwise(
        moverSeat: LudoSeat,
        moverTokenId: Int,
        from: LudoTokenSpot,
        maxSteps: Int
    ) -> (target: (seat: LudoSeat, tokenId: Int), stepsAhead: Int)? {
        var walk = from
        for step in 1...max(0, maxSteps) {
            guard let next = canApplyMove(seat: moverSeat, from: walk, roll: 1),
                  let coord = LudoBoardPath.gridCoord(for: moverSeat, tokenId: moverTokenId, spot: next) else { break }
            walk = next

            for otherSeat in activeSeatsOrdered where otherSeat != moverSeat {
                guard let row = tokens[otherSeat] else { continue }
                for tid in 0..<4 {
                    let otherSpot = row[tid]
                    guard let g = LudoBoardPath.gridCoord(for: otherSeat, tokenId: tid, spot: otherSpot),
                          g == coord else { continue }
                    if case .home = otherSpot { continue }
                    return ((otherSeat, tid), step)
                }
            }
        }
        return nil
    }

    private func applyForwardPowerup(seat: LudoSeat, tokenId: Int, steps: Int, powerupName: String) -> LudoPowerupApplyOutcome {
        if isGameOver {
            return .noEffect(message: "Game over.")
        }
        guard let from = spot(for: seat, tokenId: tokenId) else {
            return .noEffect(message: "\(powerupName) — invalid token.")
        }
        switch from {
        case .yard, .finished:
            return .noEffect(message: "\(seat.displayName): \(powerupName) only works on the track or home stretch.")
        case .home, .track:
            break
        }

        guard var mine = tokens[seat] else {
            return .noEffect(message: "\(powerupName) — invalid state.")
        }

        if let bh = resolveBlackholeAlongPath(moverSeat: seat, tokenId: tokenId, from: from, roll: steps) {
            mine[tokenId] = bh.finalSpot
            tokens[seat] = mine
            if case .yard = bh.finalSpot {
                clearFreeze(owner: seat, tokenId: tokenId)
                clearShield(owner: seat, tokenId: tokenId)
            }
            if case .finished = bh.finalSpot {
                clearShield(owner: seat, tokenId: tokenId)
                recordFinishPlacementIfSeatCompleted(seat)
            }
            var msg = "\(seat.displayName) — \(powerupName) applied."
            if let h = bh.hazardSummary { msg += " \(h)" }
            if isGameOver {
                return .gameOver(placementLines: gameOverSummaryLines(), message: msg)
            }
            return .applied(message: msg)
        }

        guard let newSpot = canApplyMove(seat: seat, from: from, roll: steps) else {
            return .noEffect(message: "\(seat.displayName): \(powerupName) can't move \(steps) (would overshoot HOME or is blocked).")
        }

        let landing = resolveTokenLanding(moverSeat: seat, tokenId: tokenId, landingSpot: newSpot)
        mine[tokenId] = landing.finalSpot
        tokens[seat] = mine
        if case .yard = landing.finalSpot {
            clearFreeze(owner: seat, tokenId: tokenId)
            clearShield(owner: seat, tokenId: tokenId)
        }

        if case .finished = landing.finalSpot {
            clearShield(owner: seat, tokenId: tokenId)
            recordFinishPlacementIfSeatCompleted(seat)
        }

        let capturedSummary = landing.captureSummary

        var msg: String
        switch landing.finalSpot {
        case .finished:
            let place = finishOrder.firstIndex(of: seat).map { $0 + 1 }
            let suffix = place.map { " (\(ordinal($0)) place)." } ?? "."
            msg = "\(seat.displayName) — \(powerupName): reached HOME\(suffix)"
        case .home:
            msg = "\(seat.displayName) — \(powerupName): moved \(steps) on the home stretch."
        case .track:
            msg = "\(seat.displayName) — \(powerupName): moved \(steps) steps clockwise."
        case .yard:
            msg = "\(seat.displayName) — \(powerupName) applied."
        }
        if let trap = landing.trapSummary {
            msg += " \(trap)"
        }
        if let c = capturedSummary {
            msg += " \(c)"
        }

        if isGameOver {
            return .gameOver(placementLines: gameOverSummaryLines(), message: msg)
        }
        return .applied(message: msg)
    }

    func __unit_setToken(for seat: LudoSeat, tokenId: Int, spot: LudoTokenSpot) {
        guard var row = tokens[seat], (0..<4).contains(tokenId) else { return }
        row[tokenId] = spot
        tokens[seat] = row
    }

    func __unit_setActiveTraps(_ traps: [LudoActiveTrap]) {
        activeTraps = traps
    }

    func __unit_setShield(owner: LudoSeat, tokenId: Int, kind: LudoShieldKind, appliedBy: LudoSeat) {
        activeShields.removeAll { $0.owner == owner && $0.tokenId == tokenId }
        activeShields.append(LudoActiveShield(owner: owner, tokenId: tokenId, kind: kind, appliedBy: appliedBy))
    }

    func __unit_advanceFullRoundForTrapExpiry() {
        tickHazardRoundsAfterFullPassAndPlayRound()
    }

    func __unit_setActiveBlackholes(_ blackholes: [LudoActiveBlackhole]) {
        activeBlackholes = blackholes
    }

    func __unit_setFrozenTokens(_ list: [LudoFrozenToken]) {
        frozenTokens = list
    }

    func __unit_setCurrentSeat(_ seat: LudoSeat) {
        guard let idx = activeSeatsOrdered.firstIndex(of: seat) else { return }
        currentSeatIndex = idx
    }

    func __unit_endTurnForSeat(_ seat: LudoSeat) {
        guard currentSeat == seat else { return }
        advanceToNextSeat(afterRolling: 0)
    }

    private static func indexOfGreen(in seats: [LudoSeat]) -> Int? {
        seats.firstIndex(of: .green)
    }

    /// Returns the new spot after applying `roll`, or `nil` if illegal.
    private func canApplyMove(seat: LudoSeat, from spot: LudoTokenSpot, roll: Int) -> LudoTokenSpot? {
        switch spot {
        case .yard, .finished:
            return nil
        case .home(let step):
            guard LudoBoardPath.isLegalHomeStretchMove(from: step, roll: roll) else { return nil }
            let next = step + roll
            return next == LudoBoardPath.homeGoalStepIndex ? .finished : .home(step: next)
        case .track(let pathIndex, let lapProgress):
            return Self.simulateTrackAndHome(seat: seat, pathIndex: pathIndex, lapProgress: lapProgress, roll: roll)
        }
    }

    /// Walk up to `roll` steps on the track; may enter the home column from the white fork `(entry + 2) % 52` once `lapProgress` is at least `trackStepsFromEntryToHomeFork` (50) — the first time a token can stand on that fork after leaving the yard.
    private static func simulateTrackAndHome(seat: LudoSeat, pathIndex: Int, lapProgress: Int, roll: Int) -> LudoTokenSpot? {
        var i = (pathIndex % 52 + 52) % 52
        var lap = lapProgress
        var stepsLeft = roll
        let fork = LudoBoardPath.publicPathForkIndexBeforeHomeColumn(for: seat)
        let minLapForHomeFork = LudoBoardPath.trackStepsFromEntryToHomeFork

        while stepsLeft > 0 {
            if lap >= minLapForHomeFork && i == fork {
                let homeStart = -1
                let after = homeStart + stepsLeft
                if after > LudoBoardPath.homeGoalStepIndex { return nil }
                if after == LudoBoardPath.homeGoalStepIndex { return .finished }
                return .home(step: after)
            }

            i = LudoBoardPath.clockwiseNextPathIndex(from: i)
            lap += 1
            stepsLeft -= 1
        }

        return .track(pathIndex: i, lapProgress: lap)
    }
}

#if DEBUG
extension LudoPassAndPlayEngine {

    func debugSetToken(for seat: LudoSeat, tokenId: Int, spot: LudoTokenSpot) {
        __unit_setToken(for: seat, tokenId: tokenId, spot: spot)
    }

    /// Ensures a seat has four tokens in engine state (for debug powerup tests on inactive corners).
    func debugEnsureSeatTokensInYard(_ seat: LudoSeat) {
        if tokens[seat] != nil { return }
        tokens[seat] = Array(repeating: .yard, count: 4)
    }

    func debugRotateCurrentSeat() {
        currentSeatIndex = (currentSeatIndex + 1) % activeSeatsOrdered.count
    }
}
#endif
