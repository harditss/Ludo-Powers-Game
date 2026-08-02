//
//  LudoBoardTileRole.swift
//  ludo
//

import Foundation

/// What a single grid cell represents on the classic 15×15 Ludo board.
/// Columns and rows are 0…14 with origin at bottom-left (column grows right, row grows up on screen in SpriteKit).
enum LudoBoardTileRole: Equatable {
    /// Plain path on the cross arms or corner arms (white / cream).
    case neutralPath
    /// Inner 2×2 yard where the four tokens begin.
    case yard(LudoSeat)
    /// Five consecutive coloured squares leading from the public path toward the centre (home column / row).
    case homeColumn(LudoSeat)
    /// The sixth coloured square for this player: on the main path, not part of the home column.
    case start(LudoSeat)
    /// One of the nine centre cells under the finishing triangles.
    case centerTile
}

/// Maps grid coordinates to tile roles for the standard square cross layout.
enum LudoBoardGrid {

    static let size = 15

    /// Classifies every cell on the 15×15 board (full square playspace).
    static func tileRole(col: Int, row: Int) -> LudoBoardTileRole {
        precondition((0..<size).contains(col) && (0..<size).contains(row))

        let inCenter = (6...8).contains(col) && (6...8).contains(row)
        if inCenter { return .centerTile }

        let greenYard = (2...3).contains(col) && (2...3).contains(row)
        let yellowYard = (11...12).contains(col) && (2...3).contains(row)
        let redYard = (11...12).contains(col) && (11...12).contains(row)
        let blueYard = (2...3).contains(col) && (11...12).contains(row)
        if greenYard { return .yard(.green) }
        if yellowYard { return .yard(.yellow) }
        if redYard { return .yard(.red) }
        if blueYard { return .yard(.blue) }

        if col == 7, (1...5).contains(row) { return .homeColumn(.green) }
        if col == 7, (9...13).contains(row) { return .homeColumn(.red) }
        if row == 7, (1...5).contains(col) { return .homeColumn(.blue) }
        if row == 7, (9...13).contains(col) { return .homeColumn(.yellow) }

        if col == 6, row == 1 { return .start(.green) }
        if col == 13, row == 6 { return .start(.yellow) }
        if col == 6, row == 13 { return .start(.red) }
        if col == 1, row == 8 { return .start(.blue) }

        return .neutralPath
    }

    /// Fractional grid coordinates (column, row) for the four yard token resting spots per seat.
    static func yardTokenFractionalCenters(for seat: LudoSeat) -> [(CGFloat, CGFloat)] {
        switch seat {
        case .green:
            return [(2.25, 2.25), (3.75, 2.25), (2.25, 3.75), (3.75, 3.75)]
        case .yellow:
            return [(11.25, 2.25), (12.75, 2.25), (11.25, 3.75), (12.75, 3.75)]
        case .red:
            return [(11.25, 11.25), (12.75, 11.25), (11.25, 12.75), (12.75, 12.75)]
        case .blue:
            return [(2.25, 11.25), (3.75, 11.25), (2.25, 12.75), (3.75, 12.75)]
        }
    }
}
