//
//  LudoStrengthScoring.swift
//  ludo
//
//  Heuristic “strength” score per seat for UI / AI. Uses public-loop geometry only (ignores extra-turn chains).
//

import Foundation

enum LudoStrengthScoring {

    private static let finishedTokenBonus = 25
    private static let safeZoneBonus = 5
    private static let dangerPenaltyRollOneToFive = 8
    private static let dangerPenaltyRollSix = 3

    /// Steps along the main loop direction (clockwise = decreasing path index) from `fromIdx` to first arrival on `toIdx`. `0` = same cell.
    static func clockwiseStepsOnPublicLoop(from fromIdx: Int, to toIdx: Int) -> Int {
        let goal = (toIdx % 52 + 52) % 52
        var cur = (fromIdx % 52 + 52) % 52
        if cur == goal { return 0 }
        for k in 1...52 {
            cur = LudoBoardPath.clockwiseNextPathIndex(from: cur)
            if cur == goal { return k }
        }
        return 999
    }

    /// attack bonus: roll 1 → +8, …, roll 6 → +3
    private static func attackOpportunityBonus(stepsAway: Int) -> Int {
        guard (1...6).contains(stepsAway) else { return 0 }
        return 9 - stepsAway
    }

    private static func progressPoints(spot: LudoTokenSpot) -> Int {
        switch spot {
        case .yard:
            return 0
        case .track(_, let lapProgress):
            return lapProgress
        case .home(let step):
            return LudoBoardPath.trackStepsFromEntryToHomeFork + step + 1
        case .finished:
            return LudoBoardPath.trackStepsFromEntryToHomeFork + LudoBoardPath.homeGoalStepIndex + finishedTokenBonus
        }
    }

    private static func isSafeZone(spot: LudoTokenSpot) -> Bool {
        switch spot {
        case .track(let pathIndex, _):
            let idx = (pathIndex % 52 + 52) % 52
            return LudoBoardPath.safePublicPathIndexSet.contains(idx)
        case .home:
            return true
        case .yard, .finished:
            return false
        }
    }

    private static func publicPathIndex(for spot: LudoTokenSpot) -> Int? {
        guard case .track(let i, _) = spot else { return nil }
        return (i % 52 + 52) % 52
    }

    /// `score = progress + safety + threat − danger` (all seats; yard = 0 progress).
    static func strengthScore(for seat: LudoSeat, tokens: [LudoSeat: [LudoTokenSpot]], activeSeats: Set<LudoSeat>) -> Int {
        guard let row = tokens[seat], row.count == 4 else { return 0 }

        var progress = 0
        var safety = 0
        for tid in 0..<4 {
            let sp = row[tid]
            progress += progressPoints(spot: sp)
            if isSafeZone(spot: sp) {
                safety += safeZoneBonus
            }
        }

        var threat = 0
        var dangerPenalty = 0

        for tid in 0..<4 {
            let mySpot = row[tid]
            guard let myIdx = publicPathIndex(for: mySpot) else { continue }

            for other in LudoSeat.allCases where other != seat && activeSeats.contains(other) {
                guard let orow = tokens[other], orow.count == 4 else { continue }
                for eid in 0..<4 {
                    let esp = orow[eid]
                    guard let eIdx = publicPathIndex(for: esp) else { continue }
                    guard LudoBoardPath.isCaptureAllowed(onPublicPathIndex: eIdx) else { continue }
                    let steps = clockwiseStepsOnPublicLoop(from: myIdx, to: eIdx)
                    if (1...6).contains(steps) {
                        threat += attackOpportunityBonus(stepsAway: steps)
                    }
                }
            }

            guard LudoBoardPath.isCaptureAllowed(onPublicPathIndex: myIdx) else { continue }

            var minRollToHitMe = Int.max
            for other in LudoSeat.allCases where other != seat && activeSeats.contains(other) {
                guard let orow = tokens[other], orow.count == 4 else { continue }
                for eid in 0..<4 {
                    let esp = orow[eid]
                    guard let eIdx = publicPathIndex(for: esp) else { continue }
                    let steps = clockwiseStepsOnPublicLoop(from: eIdx, to: myIdx)
                    if (1...6).contains(steps) {
                        minRollToHitMe = min(minRollToHitMe, steps)
                    }
                }
            }
            if minRollToHitMe <= 5 {
                dangerPenalty += dangerPenaltyRollOneToFive
            } else if minRollToHitMe == 6 {
                dangerPenalty += dangerPenaltyRollSix
            }
        }

        return progress + safety + threat - dangerPenalty
    }

    static func strengthScoresAll(tokens: [LudoSeat: [LudoTokenSpot]], activeSeats: Set<LudoSeat>) -> [(seat: LudoSeat, score: Int)] {
        activeSeats.sorted(by: { $0.rawValue < $1.rawValue }).map { seat in
            (seat, strengthScore(for: seat, tokens: tokens, activeSeats: activeSeats))
        }
    }

    /// Points behind the strongest active seat (0 if tied or leading).
    static func gapToLeader(for seat: LudoSeat, tokens: [LudoSeat: [LudoTokenSpot]], activeSeats: Set<LudoSeat>) -> Int {
        let pairs = strengthScoresAll(tokens: tokens, activeSeats: activeSeats)
        let maxScore = pairs.map(\.score).max() ?? 0
        let mine = pairs.first { $0.seat == seat }?.score ?? 0
        return max(0, maxScore - mine)
    }
}
