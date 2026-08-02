//
//  LudoActiveTrap.swift
//  ludo
//
//  Trap powerup state and placement validation (pass-and-play / future multiplayer).
//

import Foundation

/// A trap on the shared track, visible to all players.
struct LudoActiveTrap: Equatable, Sendable {
    let cell: GridCoord
    let placedBy: LudoSeat
    /// Full pass-and-play rounds remaining (every active seat takes a turn once per round).
    var fullRoundsRemaining: Int

    static let maxFullRounds = 3
}

/// Board rules for trap placement and overlap with future hazards.
enum LudoTrapPlacement {

    static func trapCells(from activeTraps: [LudoActiveTrap]) -> Set<GridCoord> {
        Set(activeTraps.map(\.cell))
    }

    /// Cells where a new trap may be placed given current tokens, traps, and hazards.
    static func validPlacementCells(
        activeSeats: [LudoSeat],
        tokens: [LudoSeat: [LudoTokenSpot]],
        activeTraps: [LudoActiveTrap],
        hazardCells: Set<GridCoord>
    ) -> [GridCoord] {
        let occupiedTrapCells = trapCells(from: activeTraps)
        var out: [GridCoord] = []
        out.reserveCapacity(40)
        for index in 0..<LudoBoardPath.publicTrack.count {
            if LudoBoardPath.safePublicPathIndexSet.contains(index) { continue }
            let cell = LudoBoardPath.publicTrack[index]
            if canPlaceTrap(
                at: cell,
                activeSeats: activeSeats,
                tokens: tokens,
                occupiedTrapCells: occupiedTrapCells,
                hazardCells: hazardCells
            ) {
                out.append(cell)
            }
        }
        return out
    }

    static func canPlaceTrap(
        at cell: GridCoord,
        activeSeats: [LudoSeat],
        tokens: [LudoSeat: [LudoTokenSpot]],
        occupiedTrapCells: Set<GridCoord>,
        hazardCells: Set<GridCoord>
    ) -> Bool {
        guard let pathIndex = LudoBoardPath.publicPathIndex(of: cell) else { return false }
        if LudoBoardPath.safePublicPathIndexSet.contains(pathIndex) { return false }
        if LudoBoardPath.goalHub == cell { return false }
        if hazardCells.contains(cell) { return false }
        if occupiedTrapCells.contains(cell) { return false }
        if isYardOrHomeStretchCell(cell) { return false }
        if isOccupiedSpawnTile(cell, activeSeats: activeSeats, tokens: tokens) { return false }
        return true
    }

    private static func isYardOrHomeStretchCell(_ cell: GridCoord) -> Bool {
        for seat in LudoSeat.allCases {
            if LudoBoardPath.yardCells(for: seat).contains(cell) { return true }
            if LudoBoardPath.homeStretchCellsInGoalOrder(for: seat).contains(cell) { return true }
        }
        return false
    }

    /// Coloured start square with a token currently standing on it.
    private static func isOccupiedSpawnTile(
        _ cell: GridCoord,
        activeSeats: [LudoSeat],
        tokens: [LudoSeat: [LudoTokenSpot]]
    ) -> Bool {
        for seat in activeSeats {
            let entry = LudoBoardPath.publicPathEntryIndex(for: seat)
            guard LudoBoardPath.publicTrack[entry] == cell else { continue }
            guard let row = tokens[seat] else { continue }
            for spot in row {
                if case .track(let pathIndex, _) = spot,
                   (pathIndex % 52 + 52) % 52 == entry {
                    return true
                }
            }
        }
        return false
    }
}
