//
//  LudoActiveBlackhole.swift
//  ludo
//
//  Blackhole hazard state (pass-and-play / future multiplayer sync).
//

import Foundation

/// A blackhole on the shared track — visible to all; persists after triggering.
struct LudoActiveBlackhole: Equatable, Sendable, Codable {
    let cell: GridCoord
    let placedBy: LudoSeat
    /// Full pass-and-play rounds remaining (each active seat takes one turn per round).
    var fullRoundsRemaining: Int

    static let maxFullRounds = 3
}

enum LudoBlackholePlacement {

    static func blackholeCells(from active: [LudoActiveBlackhole]) -> Set<GridCoord> {
        Set(active.map(\.cell))
    }

    static func placementBufferCells() -> Set<GridCoord> {
        var cells = Set<GridCoord>()
        for seat in LudoSeat.allCases {
            let fork = LudoBoardPath.publicPathForkIndexBeforeHomeColumn(for: seat)
            let beforeFork = (fork + 1) % 52
            let afterStar = LudoBoardPath.clockwiseNextPathIndex(from: LudoBoardPath.publicPathEntryIndex(for: seat))
            cells.insert(LudoBoardPath.publicTrack[beforeFork])
            cells.insert(LudoBoardPath.publicTrack[afterStar])
        }
        return cells
    }

    static func occupiedTrackCells(tokens: [LudoSeat: [LudoTokenSpot]]) -> Set<GridCoord> {
        var out = Set<GridCoord>()
        for (seat, row) in tokens {
            for (tid, spot) in row.enumerated() {
                if let g = LudoBoardPath.gridCoord(for: seat, tokenId: tid, spot: spot) {
                    out.insert(g)
                }
            }
        }
        return out
    }

    static func validPlacementCells(
        activeSeats: [LudoSeat],
        tokens: [LudoSeat: [LudoTokenSpot]],
        activeTraps: [LudoActiveTrap],
        activeBlackholes: [LudoActiveBlackhole],
        extraHazardCells: Set<GridCoord>
    ) -> [GridCoord] {
        let trapCells = LudoTrapPlacement.trapCells(from: activeTraps)
        let blackholeCells = blackholeCells(from: activeBlackholes)
        let occupied = occupiedTrackCells(tokens: tokens)
        let buffers = placementBufferCells()
        var out: [GridCoord] = []
        out.reserveCapacity(32)
        for index in 0..<LudoBoardPath.publicTrack.count {
            let cell = LudoBoardPath.publicTrack[index]
            if canPlaceBlackhole(
                at: cell,
                activeSeats: activeSeats,
                tokens: tokens,
                trapCells: trapCells,
                blackholeCells: blackholeCells,
                occupiedCells: occupied,
                bufferCells: buffers,
                extraHazardCells: extraHazardCells
            ) {
                out.append(cell)
            }
        }
        return out
    }

    static func canPlaceBlackhole(
        at cell: GridCoord,
        activeSeats: [LudoSeat],
        tokens: [LudoSeat: [LudoTokenSpot]],
        trapCells: Set<GridCoord>,
        blackholeCells: Set<GridCoord>,
        occupiedCells: Set<GridCoord>,
        bufferCells: Set<GridCoord>,
        extraHazardCells: Set<GridCoord>
    ) -> Bool {
        guard let pathIndex = LudoBoardPath.publicPathIndex(of: cell) else { return false }
        if LudoBoardPath.safePublicPathIndexSet.contains(pathIndex) { return false }
        if LudoBoardPath.goalHub == cell { return false }
        if bufferCells.contains(cell) { return false }
        if trapCells.contains(cell) || blackholeCells.contains(cell) { return false }
        if extraHazardCells.contains(cell) { return false }
        if occupiedCells.contains(cell) { return false }
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
