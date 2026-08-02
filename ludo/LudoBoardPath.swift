//
//  LudoBoardPath.swift
//  ludo
//
//  Public track order follows the classic 52-cell loop (orthogonal adjacency with four
//  “corner-cut” steps), adapted from the board graph in schweryjonas/ludo-game (Board.path()).
//

import Foundation

/// Board cell in **Java / common Ludo grid** order: `row` 0 = bottom, `col` 0 = left (SpriteKit +y up).
struct GridCoord: Hashable, Sendable, Codable {
    var row: Int
    var col: Int
}

/// Geometry and topology for the 15×15 Ludo grid used by the renderer and future rules engine.
enum LudoBoardPath {

    static let gridSize = 15

    /// The shared outer loop (52 cells). Movement follows **decreasing** path indices `(i - 1 + 52) % 52`.
    /// The **fork** index `(entry + 2) % 52` is the last white loop cell before that seat’s coloured home column (two path steps before its star along that direction). It is reached **50** track steps after leaving the yard onto the coloured start — so home entry must not require `lapProgress >= 52`, which would overshoot the first visit to the fork.
    static let publicTrack: [GridCoord] = [
        GridCoord(row: 1, col: 6),
        GridCoord(row: 0, col: 6),
        GridCoord(row: 0, col: 7),
        GridCoord(row: 0, col: 8),
        GridCoord(row: 1, col: 8),
        GridCoord(row: 2, col: 8),
        GridCoord(row: 3, col: 8),
        GridCoord(row: 4, col: 8),
        GridCoord(row: 5, col: 8),
        GridCoord(row: 6, col: 9),
        GridCoord(row: 6, col: 10),
        GridCoord(row: 6, col: 11),
        GridCoord(row: 6, col: 12),
        GridCoord(row: 6, col: 13),
        GridCoord(row: 6, col: 14),
        GridCoord(row: 7, col: 14),
        GridCoord(row: 8, col: 14),
        GridCoord(row: 8, col: 13),
        GridCoord(row: 8, col: 12),
        GridCoord(row: 8, col: 11),
        GridCoord(row: 8, col: 10),
        GridCoord(row: 8, col: 9),
        GridCoord(row: 9, col: 8),
        GridCoord(row: 10, col: 8),
        GridCoord(row: 11, col: 8),
        GridCoord(row: 12, col: 8),
        GridCoord(row: 13, col: 8),
        GridCoord(row: 14, col: 8),
        GridCoord(row: 14, col: 7),
        GridCoord(row: 14, col: 6),
        GridCoord(row: 13, col: 6),
        GridCoord(row: 12, col: 6),
        GridCoord(row: 11, col: 6),
        GridCoord(row: 10, col: 6),
        GridCoord(row: 9, col: 6),
        GridCoord(row: 8, col: 5),
        GridCoord(row: 8, col: 4),
        GridCoord(row: 8, col: 3),
        GridCoord(row: 8, col: 2),
        GridCoord(row: 8, col: 1),
        GridCoord(row: 8, col: 0),
        GridCoord(row: 7, col: 0),
        GridCoord(row: 6, col: 0),
        GridCoord(row: 6, col: 1),
        GridCoord(row: 6, col: 2),
        GridCoord(row: 6, col: 3),
        GridCoord(row: 6, col: 4),
        GridCoord(row: 6, col: 5),
        GridCoord(row: 5, col: 6),
        GridCoord(row: 4, col: 6),
        GridCoord(row: 3, col: 6),
        GridCoord(row: 2, col: 6),
    ]

    /// Path indices whose tiles are each player’s **coloured start** (also safe / cannot be captured in normal rules).
    static let safePublicPathIndices: [Int] = [0, 13, 26, 39]

    static let safePublicPathIndexSet: Set<Int> = Set(safePublicPathIndices)

    /// `true` when landing on this public-loop index may send opponent tokens back to the yard.
    static func isCaptureAllowed(onPublicPathIndex index: Int) -> Bool {
        let i = (index % 52 + 52) % 52
        return !safePublicPathIndexSet.contains(i)
    }

    /// Where each seat **enters** the public loop after rolling a six (same cell as coloured start).
    static func publicPathEntryIndex(for seat: LudoSeat) -> Int {
        switch seat {
        case .green: return 0
        case .yellow: return 13
        case .red: return 26
        case .blue: return 39
        }
    }

    /// Five coloured squares from the fork (track-side) toward the hub; index `0` touches the main loop fork neighbour.
    static func homeColumn(for seat: LudoSeat) -> [GridCoord] {
        switch seat {
        case .green:
            return [
                GridCoord(row: 1, col: 7), GridCoord(row: 2, col: 7), GridCoord(row: 3, col: 7),
                GridCoord(row: 4, col: 7), GridCoord(row: 5, col: 7),
            ]
        case .red:
            return [
                GridCoord(row: 13, col: 7), GridCoord(row: 12, col: 7), GridCoord(row: 11, col: 7),
                GridCoord(row: 10, col: 7), GridCoord(row: 9, col: 7),
            ]
        case .yellow:
            return [
                GridCoord(row: 7, col: 13), GridCoord(row: 7, col: 12), GridCoord(row: 7, col: 11),
                GridCoord(row: 7, col: 10), GridCoord(row: 7, col: 9),
            ]
        case .blue:
            return [
                GridCoord(row: 7, col: 1), GridCoord(row: 7, col: 2), GridCoord(row: 7, col: 3),
                GridCoord(row: 7, col: 4), GridCoord(row: 7, col: 5),
            ]
        }
    }

    /// Yard cells (one token each) matching the reference board’s home bases.
    static func yardCells(for seat: LudoSeat) -> [GridCoord] {
        switch seat {
        case .green:
            return [
                GridCoord(row: 2, col: 2), GridCoord(row: 2, col: 3),
                GridCoord(row: 3, col: 2), GridCoord(row: 3, col: 3),
            ]
        case .yellow:
            return [
                GridCoord(row: 2, col: 11), GridCoord(row: 2, col: 12),
                GridCoord(row: 3, col: 11), GridCoord(row: 3, col: 12),
            ]
        case .red:
            return [
                GridCoord(row: 11, col: 11), GridCoord(row: 11, col: 12),
                GridCoord(row: 12, col: 11), GridCoord(row: 12, col: 12),
            ]
        case .blue:
            return [
                GridCoord(row: 11, col: 2), GridCoord(row: 11, col: 3),
                GridCoord(row: 12, col: 2), GridCoord(row: 12, col: 3),
            ]
        }
    }

    static func publicPathIndex(of cell: GridCoord) -> Int? {
        publicTrack.firstIndex { $0 == cell }
    }

    /// One step along the main game direction on the outer loop (`publicTrack` indices **decrease** mod 52).
    static func clockwiseNextPathIndex(from index: Int) -> Int {
        let i = (index % 52 + 52) % 52
        return (i - 1 + 52) % 52
    }

    private static func nearestSeatForMysteryTrackCell(to cell: GridCoord) -> LudoSeat {
        var bestSeat = LudoSeat.green
        var bestD = Int.max
        for seat in LudoSeat.allCases {
            let star = publicTrack[publicPathEntryIndex(for: seat)]
            let d = abs(cell.row - star.row) + abs(cell.col - star.col)
            if d < bestD || (d == bestD && seat.rawValue < bestSeat.rawValue) {
                bestD = d
                bestSeat = seat
            }
        }
        return bestSeat
    }

    /// White loop cells closest to this seat’s coloured start (Manhattan), excluding stars — partitions the outer track per arm.
    static func mysteryWhiteTrackCells(for seat: LudoSeat) -> [GridCoord] {
        var out: [GridCoord] = []
        out.reserveCapacity(14)
        for index in 0..<publicTrack.count {
            if safePublicPathIndexSet.contains(index) { continue }
            let cell = publicTrack[index]
            if nearestSeatForMysteryTrackCell(to: cell) == seat {
                out.append(cell)
            }
        }
        return out
    }

    /// Board cell for a token’s current spot (yard tile, track, home stretch, or hub).
    static func gridCoord(for seat: LudoSeat, tokenId: Int, spot: LudoTokenSpot) -> GridCoord? {
        switch spot {
        case .yard:
            let yards = yardCells(for: seat)
            guard yards.indices.contains(tokenId) else { return nil }
            return yards[tokenId]
        case .finished:
            return goalHub
        case .track(let pathIndex, _):
            let i = (pathIndex % 52 + 52) % 52
            return publicTrack[i]
        case .home(let step):
            let column = homeStretchCellsInGoalOrder(for: seat)
            guard column.indices.contains(step) else { return nil }
            return column[step]
        }
    }

    /// Board cell one step **clockwise ahead** of this token (track or home column). Yard / finished have no ahead cell.
    static func gridCoordOneStepAheadClockwise(seat: LudoSeat, spot: LudoTokenSpot) -> GridCoord? {
        switch spot {
        case .yard, .finished:
            return nil
        case .track(let pathIndex, _):
            let i = (pathIndex % 52 + 52) % 52
            if mayTurnIntoHomeFromFork(seat: seat, pathIndex: i) {
                return homeStretchCellsInGoalOrder(for: seat)[0]
            }
            return publicTrack[clockwiseNextPathIndex(from: i)]
        case .home(let step):
            guard step < homeGoalStepIndex - 1 else { return nil }
            let column = homeStretchCellsInGoalOrder(for: seat)
            let nextStep = step + 1
            guard column.indices.contains(nextStep) else { return nil }
            return column[nextStep]
        }
    }

    /// Advance `steps` times along the main track direction from `index`.
    static func advanceClockwise(from index: Int, steps: Int) -> Int {
        var i = (index % 52 + 52) % 52
        for _ in 0..<max(0, steps) {
            i = clockwiseNextPathIndex(from: i)
        }
        return i
    }

    /// Clockwise steps along the shared loop from this seat’s coloured start to `pathIndex` (0 at entry).
    static func stepsClockwiseFromEntry(to pathIndex: Int, for seat: LudoSeat) -> Int {
        let entry = publicPathEntryIndex(for: seat)
        let goal = (pathIndex % 52 + 52) % 52
        if goal == entry { return 0 }
        var steps = 0
        var i = entry
        while steps < 52 {
            i = clockwiseNextPathIndex(from: i)
            steps += 1
            if i == goal { return steps }
        }
        return steps
    }

    /// Stored `lapProgress` for a token standing on the main loop — matches board position for this owner.
    static func trackLapProgressForPosition(seat: LudoSeat, pathIndex: Int) -> Int {
        stepsClockwiseFromEntry(to: pathIndex, for: seat)
    }

    /// May this token turn up its home column on the next step from the white fork (owner + path index, not lap alone).
    static func mayTurnIntoHomeFromFork(seat: LudoSeat, pathIndex: Int) -> Bool {
        let fork = publicPathForkIndexBeforeHomeColumn(for: seat)
        let i = (pathIndex % 52 + 52) % 52
        guard i == fork else { return false }
        return stepsClockwiseFromEntry(to: i, for: seat) >= trackStepsFromEntryToHomeFork
    }

    /// Track index two steps **before** the coloured start (star) along the main track direction — the white junction before the coloured home column.
    static func publicPathForkIndexBeforeHomeColumn(for seat: LudoSeat) -> Int {
        let e = publicPathEntryIndex(for: seat)
        return (e + 2) % 52
    }

    /// Steps from `publicPathEntryIndex` to `publicPathForkIndexBeforeHomeColumn` along `clockwiseNextPathIndex` (50 for every seat on this board).
    static let trackStepsFromEntryToHomeFork: Int = 50

    /// Five coloured home cells from the fork toward the hub (same order as `homeColumn(for:)`).
    static func homeStretchCellsInGoalOrder(for seat: LudoSeat) -> [GridCoord] {
        homeColumn(for: seat)
    }

    /// `homeStep` 0…4 = on coloured tiles; `5` = HOME (hub). Overshooting HOME is illegal (exact roll to finish).
    static func isLegalHomeStretchMove(from homeStep: Int, roll: Int) -> Bool {
        homeStep + roll <= homeGoalStepIndex
    }

    /// `homeStep + roll == homeGoalStepIndex` means entering the centre; smaller sums stay on coloured tiles.
    static let homeGoalStepIndex = 5
    static let goalTriangleCells: [GridCoord] = [
        GridCoord(row: 7, col: 6),
        GridCoord(row: 7, col: 8),
        GridCoord(row: 6, col: 7),
        GridCoord(row: 8, col: 7),
    ]

    /// Centre hub cell.
    static let goalHub = GridCoord(row: 7, col: 7)
}
