//
//  ludoTests.swift
//  ludoTests
//
//  Created by Hardit Sabharwal on 2026-05-14.
//

import Testing
@testable import ludo

struct LudoBoardPathTests {

    @Test func publicTrackHas52UniqueCells() {
        #expect(LudoBoardPath.publicTrack.count == 52)
        #expect(Set(LudoBoardPath.publicTrack).count == 52)
    }

    @Test func publicTrackIsClosedLoop() {
        let p = LudoBoardPath.publicTrack
        func manhattan(_ a: GridCoord, _ b: GridCoord) -> Int {
            abs(a.row - b.row) + abs(a.col - b.col)
        }
        for i in 0..<52 {
            let a = p[i]
            let b = p[(i + 1) % 52]
            let d = manhattan(a, b)
            #expect(d == 1 || d == 2)
            if d == 2 {
                #expect(abs(a.row - b.row) == 1 && abs(a.col - b.col) == 1)
            }
        }
    }

    @Test func entryIndicesMatchColouredStarts() {
        #expect(LudoBoardPath.publicTrack[LudoBoardPath.publicPathEntryIndex(for: .green)] == GridCoord(row: 1, col: 6))
        #expect(LudoBoardPath.publicTrack[LudoBoardPath.publicPathEntryIndex(for: .yellow)] == GridCoord(row: 6, col: 13))
        #expect(LudoBoardPath.publicTrack[LudoBoardPath.publicPathEntryIndex(for: .red)] == GridCoord(row: 13, col: 8))
        #expect(LudoBoardPath.publicTrack[LudoBoardPath.publicPathEntryIndex(for: .blue)] == GridCoord(row: 8, col: 1))
    }

    @Test func eachSeatHasFourYardCells() {
        for s in LudoSeat.allCases {
            #expect(LudoBoardPath.yardCells(for: s).count == 4)
        }
    }

    @Test func eachSeatHasFiveHomeCells() {
        for s in LudoSeat.allCases {
            #expect(LudoBoardPath.homeColumn(for: s).count == 5)
        }
    }

    @Test func clockwiseFourStepsFromGreenEntry() {
        let entry = LudoBoardPath.publicPathEntryIndex(for: .green)
        #expect(entry == 0)
        let after = LudoBoardPath.advanceClockwise(from: entry, steps: 4)
        #expect(after == 48)
    }
}

struct LudoSeatSelectionTests {

    @Test func twoPlayerGameUsesGreenAndRed() {
        #expect(LudoSeat.activeSeats(forPlayerCount: 2) == Set([LudoSeat.green, .red]))
    }

    @Test func threePlayerGameUsesFirstThreeClockwise() {
        #expect(LudoSeat.activeSeats(forPlayerCount: 3) == Set([LudoSeat.green, .yellow, .red]))
    }

    @Test func fourPlayerGameUsesAllSeats() {
        #expect(LudoSeat.activeSeats(forPlayerCount: 4) == Set(LudoSeat.allCases))
    }
}

@MainActor
struct LudoPassAndPlayEngineTests {

    @Test func greenAlwaysStartsWithNoOpeningDice() {
        let engine = LudoPassAndPlayEngine(playerCount: 4)
        let outcome = engine.resolveOpening()
        #expect(outcome.firstPlayer == .green)
        #expect(outcome.rounds.isEmpty)
        #expect(engine.currentSeat == .green)
    }

    @Test func rollThreeWithAllTokensInYardPassesTurn() {
        let engine = LudoPassAndPlayEngine(playerCount: 2)
        _ = engine.resolveOpening()
        let before = engine.currentSeat
        let result = engine.applyGameplayRoll(3)
        guard case .passedNoMove = result else {
            Issue.record("Expected pass")
            return
        }
        #expect(engine.currentSeat != before)
    }

    @Test func rollSixWithAllInYardRequiresTokenChoice() {
        let engine = LudoPassAndPlayEngine(playerCount: 2)
        _ = engine.resolveOpening()
        let seat = engine.currentSeat
        let entry = LudoBoardPath.publicPathEntryIndex(for: seat)
        let result = engine.applyGameplayRoll(6)
        guard case .needsTokenChoice(let roll, let yard, let track, let home) = result else {
            Issue.record("Expected token choice")
            return
        }
        #expect(roll == 6)
        #expect(yard.count == 4)
        #expect(track.isEmpty)
        #expect(home.isEmpty)
        let applied = engine.applyTokenChoice(seat: seat, tokenId: 2)
        #expect(applied != nil)
        guard case .track(let idx, _) = engine.spot(for: seat, tokenId: 2)! else {
            Issue.record("Expected track")
            return
        }
        #expect(idx == entry)
    }

    @Test func rollFourMovesClockwiseAlongTrack() {
        let engine = LudoPassAndPlayEngine(playerCount: 2)
        _ = engine.resolveOpening()
        let seat = engine.currentSeat
        let entry = LudoBoardPath.publicPathEntryIndex(for: seat)
        engine.__unit_setToken(for: seat, tokenId: 0, spot: .track(pathIndex: entry, lapProgress: 0))
        let result = engine.applyGameplayRoll(4)
        guard case .autoApplied = result else {
            Issue.record("Expected auto move")
            return
        }
        guard case .track(let idx, _) = engine.spot(for: seat, tokenId: 0)! else {
            Issue.record("Expected track")
            return
        }
        #expect(idx == LudoBoardPath.advanceClockwise(from: entry, steps: 4))
    }

    @Test func trapTicksDownWhenPassAndPlayRoundWraps() {
        let engine = LudoPassAndPlayEngine(playerCount: 2)
        _ = engine.resolveOpening()
        let cell = LudoBoardPath.publicTrack[20]
        engine.__unit_setActiveTraps([
            LudoActiveTrap(cell: cell, placedBy: .green, fullRoundsRemaining: 3),
        ])
        engine.__unit_endTurnForSeat(.green)
        #expect(engine.activeTraps.first?.fullRoundsRemaining == 3)
        engine.__unit_endTurnForSeat(.red)
        #expect(engine.activeTraps.first?.fullRoundsRemaining == 2)
    }

    @Test func trapExpiresAfterThreeFullRoundsWithoutTrigger() {
        let engine = LudoPassAndPlayEngine(playerCount: 2)
        _ = engine.resolveOpening()
        let cell = LudoBoardPath.publicTrack[20]
        engine.__unit_setActiveTraps([
            LudoActiveTrap(cell: cell, placedBy: .green, fullRoundsRemaining: 3),
        ])
        #expect(engine.activeTraps.first?.fullRoundsRemaining == 3)
        for _ in 0..<3 {
            engine.__unit_advanceFullRoundForTrapExpiry()
        }
        #expect(engine.activeTraps.isEmpty)
    }

    @Test func blackholePlacementRejectsBufferNearStarAndFork() {
        let engine = LudoPassAndPlayEngine(playerCount: 2)
        _ = engine.resolveOpening()
        let greenEntry = LudoBoardPath.publicPathEntryIndex(for: .green)
        let afterStar = LudoBoardPath.publicTrack[LudoBoardPath.clockwiseNextPathIndex(from: greenEntry)]
        let beforeFork = LudoBoardPath.publicTrack[
            (LudoBoardPath.publicPathForkIndexBeforeHomeColumn(for: .green) + 1) % 52
        ]
        #expect(!LudoBlackholePlacement.canPlaceBlackhole(
            at: afterStar,
            activeSeats: engine.activeSeatsOrdered,
            tokens: engine.tokens,
            trapCells: [],
            blackholeCells: [],
            occupiedCells: [],
            bufferCells: LudoBlackholePlacement.placementBufferCells(),
            extraHazardCells: []
        ))
        #expect(!LudoBlackholePlacement.canPlaceBlackhole(
            at: beforeFork,
            activeSeats: engine.activeSeatsOrdered,
            tokens: engine.tokens,
            trapCells: [],
            blackholeCells: [],
            occupiedCells: [],
            bufferCells: LudoBlackholePlacement.placementBufferCells(),
            extraHazardCells: []
        ))
    }

    @Test func blackholeOnPathSendsTokenToYard() {
        let engine = LudoPassAndPlayEngine(playerCount: 2)
        _ = engine.resolveOpening()
        let seat = engine.currentSeat
        let entry = LudoBoardPath.publicPathEntryIndex(for: seat)
        let ahead = LudoBoardPath.advanceClockwise(from: entry, steps: 2)
        let cell = LudoBoardPath.publicTrack[ahead]
        engine.__unit_setActiveBlackholes([
            LudoActiveBlackhole(cell: cell, placedBy: seat, fullRoundsRemaining: 3),
        ])
        engine.__unit_setToken(for: seat, tokenId: 0, spot: .track(pathIndex: entry, lapProgress: 0))
        let result = engine.applyGameplayRoll(2)
        guard case .autoApplied = result else {
            Issue.record("Expected auto move onto blackhole path")
            return
        }
        guard case .yard = engine.spot(for: seat, tokenId: 0)! else {
            Issue.record("Token should be in yard")
            return
        }
        #expect(engine.activeBlackholes.count == 1)
    }

    @Test func blackholeShieldStopsOnTile() {
        let engine = LudoPassAndPlayEngine(playerCount: 2)
        _ = engine.resolveOpening()
        let seat = engine.currentSeat
        let entry = LudoBoardPath.publicPathEntryIndex(for: seat)
        let cell = LudoBoardPath.publicTrack[LudoBoardPath.advanceClockwise(from: entry, steps: 1)]
        engine.__unit_setActiveBlackholes([
            LudoActiveBlackhole(cell: cell, placedBy: seat, fullRoundsRemaining: 3),
        ])
        engine.__unit_setShield(owner: seat, tokenId: 0, kind: .small, appliedBy: seat)
        engine.__unit_setToken(for: seat, tokenId: 0, spot: .track(pathIndex: entry, lapProgress: 0))
        _ = engine.applyGameplayRoll(1)
        guard case .track(let idx, _) = engine.spot(for: seat, tokenId: 0)! else {
            Issue.record("Shielded token should stop on blackhole tile")
            return
        }
        #expect(idx == LudoBoardPath.advanceClockwise(from: entry, steps: 1))
        #expect(!engine.isTokenShielded(owner: seat, tokenId: 0))
    }

    @Test func homeStretchCannotOvershoot() {
        let engine = LudoPassAndPlayEngine(playerCount: 2)
        _ = engine.resolveOpening()
        let seat = engine.currentSeat
        engine.__unit_setToken(for: seat, tokenId: 0, spot: .home(step: 4))
        let blocked = engine.applyGameplayRoll(2)
        guard case .passedNoMove = blocked else {
            Issue.record("Overshoot should force pass")
            return
        }
        let ok = engine.applyGameplayRoll(1)
        guard case .autoApplied = ok else {
            Issue.record("Exact finish should work")
            return
        }
        guard case .finished = engine.spot(for: seat, tokenId: 0)! else {
            Issue.record("Expected finished")
            return
        }
    }
}

struct ludoTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}
