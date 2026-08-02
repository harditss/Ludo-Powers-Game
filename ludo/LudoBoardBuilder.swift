//
//  LudoBoardBuilder.swift
//  ludo
//

import CoreGraphics
import SpriteKit

/// Renders the 15×15 classic Ludo grid: 52-cell public loop, home columns, yards, and centre finish.
enum LudoBoardBuilder {

    private static let cellStep: CGFloat = 28
    private static var boardSpan: CGFloat { CGFloat(LudoBoardPath.gridSize) * cellStep }

    /// World-space width/height of the built board (for scaling and touch mapping).
    static var worldBoardSpan: CGFloat { boardSpan }
    static var worldCellStep: CGFloat { cellStep }

    /// World-space centre of cell `(row, col)` with board origin at the board centre.
    static func boardPoint(row: Int, col: Int) -> CGPoint {
        let half = boardSpan / 2
        let x = (CGFloat(col) + 0.5) * cellStep - half
        let y = (CGFloat(row) + 0.5) * cellStep - half
        return CGPoint(x: x, y: y)
    }

    /// World position for a public-loop index `0 ... 51`.
    static func publicTrackWorldPoint(index: Int) -> CGPoint {
        let g = LudoBoardPath.publicTrack[(index % 52 + 52) % 52]
        return boardPoint(row: g.row, col: g.col)
    }

    @discardableResult
    static func buildBoard(in parent: SKNode, playerCount: Int) -> [LudoSeat: [SKShapeNode]] {
        parent.removeAllChildren()

        let activeSeats = LudoSeat.activeSeats(forPlayerCount: playerCount)

        let root = SKNode()
        root.name = "ludoBoard"
        parent.addChild(root)

        let margin: CGFloat = 18
        let outer = SKShapeNode(
            rectOf: CGSize(width: boardSpan + margin * 2, height: boardSpan + margin * 2),
            cornerRadius: 12
        )
        outer.fillColor = SKColor(red: 0.88, green: 0.84, blue: 0.76, alpha: 1)
        outer.strokeColor = SKColor(red: 0.52, green: 0.38, blue: 0.22, alpha: 1)
        outer.lineWidth = 5
        outer.glowWidth = 1
        outer.zPosition = -4
        outer.name = "boardOuter"
        root.addChild(outer)
        let outerSheen = SKShapeNode(
            rectOf: CGSize(width: boardSpan + margin * 1.7, height: boardSpan + margin * 1.1),
            cornerRadius: 10
        )
        outerSheen.fillColor = SKColor(red: 1, green: 0.98, blue: 0.92, alpha: 0.28)
        outerSheen.strokeColor = .clear
        outerSheen.position = CGPoint(x: 0, y: margin * 0.35)
        outerSheen.zPosition = -3.9
        outerSheen.name = "boardOuterSheen"
        root.addChild(outerSheen)

        let publicSet = Set(LudoBoardPath.publicTrack)
        var homeSet = Set<GridCoord>()
        for seat in LudoSeat.allCases {
            LudoBoardPath.homeColumn(for: seat).forEach { homeSet.insert($0) }
        }

        for row in 0..<LudoBoardPath.gridSize {
            for col in 0..<LudoBoardPath.gridSize {
                let cell = GridCoord(row: row, col: col)
                if let seat = yardSeat(for: cell) {
                    addYardTile(cell, seat: seat, active: activeSeats.contains(seat), to: root)
                    continue
                }
                if publicSet.contains(cell) {
                    if let idx = LudoBoardPath.publicPathIndex(of: cell) {
                        addPublicPathTile(index: idx, cell: cell, to: root)
                    }
                    continue
                }
                if homeSet.contains(cell), let seat = homeSeat(for: cell) {
                    addHomeTile(cell, seat: seat, active: activeSeats.contains(seat), to: root)
                    continue
                }
                if (6...8).contains(row), (6...8).contains(col) {
                    // Centre finish: four coloured triangles only (no square tiles).
                    continue
                }
            }
        }

        addCenterQuadrantTriangles(to: root)

        var tokens: [LudoSeat: [SKShapeNode]] = [:]
        for seat in LudoSeat.allCases {
            let cells = LudoBoardPath.yardCells(for: seat)
            var seatTokens: [SKShapeNode] = []
            for (i, cell) in cells.enumerated() {
                let token = makeToken(seat: seat)
                token.position = boardPoint(row: cell.row, col: cell.col)
                token.name = "token_\(seat.rawValue)_\(i)"
                token.zPosition = 12
                token.alpha = activeSeats.contains(seat) ? 1 : 0.35
                root.addChild(token)
                seatTokens.append(token)
            }
            tokens[seat] = seatTokens
        }

        return tokens
    }

    private static func yardSeat(for cell: GridCoord) -> LudoSeat? {
        for seat in LudoSeat.allCases {
            if LudoBoardPath.yardCells(for: seat).contains(cell) { return seat }
        }
        return nil
    }

    private static func homeSeat(for cell: GridCoord) -> LudoSeat? {
        for seat in LudoSeat.allCases {
            if LudoBoardPath.homeColumn(for: seat).contains(cell) { return seat }
        }
        return nil
    }

    private static func addYardTile(_ cell: GridCoord, seat: LudoSeat, active: Bool, to root: SKNode) {
        let tile = tileShape()
        tile.position = boardPoint(row: cell.row, col: cell.col)
        tile.fillColor = SKColor(white: 0.97, alpha: active ? 1 : 0.45)
        tile.strokeColor = active ? seat.tokenStroke : SKColor(white: 0.55, alpha: 0.35)
        tile.lineWidth = active ? 2.5 : 1.5
        tile.name = "yard_\(seat.rawValue)_\(cell.row)_\(cell.col)"
        tile.zPosition = 0
        root.addChild(tile)
    }

    private static func addPublicPathTile(index: Int, cell: GridCoord, to root: SKNode) {
        let tile = tileShape()
        tile.position = boardPoint(row: cell.row, col: cell.col)
        let isSafe = LudoBoardPath.safePublicPathIndices.contains(index)
        if isSafe, let seat = seatForSafePathIndex(index) {
            tile.fillColor = seat.tokenFill.withAlphaComponent(0.82)
            tile.strokeColor = seat.tokenStroke
            tile.lineWidth = 2.2
            addStarGlyph(at: tile.position, in: root)
        } else {
            tile.fillColor = SKColor(white: 0.98, alpha: 1)
            tile.strokeColor = SKColor(white: 0.58, alpha: 1)
            tile.lineWidth = 1.3
        }
        tile.name = "track_\(index)"
        tile.zPosition = 1
        root.addChild(tile)
    }

    private static func seatForSafePathIndex(_ index: Int) -> LudoSeat? {
        for seat in LudoSeat.allCases where LudoBoardPath.publicPathEntryIndex(for: seat) == index {
            return seat
        }
        return nil
    }

    private static func addHomeTile(_ cell: GridCoord, seat: LudoSeat, active: Bool, to root: SKNode) {
        let tile = tileShape()
        tile.position = boardPoint(row: cell.row, col: cell.col)
        tile.fillColor = seat.tokenFill.withAlphaComponent(active ? 0.7 : 0.22)
        tile.strokeColor = active ? seat.tokenStroke.withAlphaComponent(0.85) : SKColor(white: 0.55, alpha: 0.35)
        tile.lineWidth = active ? 1.8 : 1.2
        if let index = LudoBoardPath.homeColumn(for: seat).firstIndex(of: cell) {
            tile.name = "home_\(seat.rawValue)_\(index)"
        }
        tile.zPosition = 2
        root.addChild(tile)
    }

    private static func tileShape() -> SKShapeNode {
        SKShapeNode(rectOf: CGSize(width: cellStep - 1.2, height: cellStep - 1.2), cornerRadius: 3)
    }

    private static func addStarGlyph(at position: CGPoint, in root: SKNode) {
        let path = CGMutablePath()
        let radius: CGFloat = 7
        let points = 5
        for i in 0..<(points * 2) {
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let r = i % 2 == 0 ? radius : radius * 0.45
            let point = CGPoint(x: position.x + r * cos(angle), y: position.y + r * sin(angle))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        let star = SKShapeNode(path: path)
        star.fillColor = SKColor(white: 1, alpha: 0.35)
        star.strokeColor = SKColor(white: 0.2, alpha: 0.5)
        star.lineWidth = 0.8
        star.zPosition = 3
        star.name = "starGlyph"
        root.addChild(star)
    }

    private static func makeToken(seat: LudoSeat) -> SKShapeNode {
        let token = SKShapeNode(circleOfRadius: 9)
        token.fillColor = seat.tokenFill
        token.strokeColor = seat.tokenStroke
        token.lineWidth = 2
        token.glowWidth = 0.5
        LudoBoardJuice.attachTokenShadow(to: token)
        return token
    }

    /// Four right triangles (one per seat) meeting at the hub; outer boundary is a square.
    private static func addCenterQuadrantTriangles(to root: SKNode) {
        let center = boardPoint(row: 7, col: 7)
        let half = cellStep * 1.5
        let corners: [(LudoSeat, CGPoint, CGPoint)] = [
            (.green, CGPoint(x: -half, y: -half), CGPoint(x: half, y: -half)),
            (.yellow, CGPoint(x: half, y: -half), CGPoint(x: half, y: half)),
            (.red, CGPoint(x: half, y: half), CGPoint(x: -half, y: half)),
            (.blue, CGPoint(x: -half, y: half), CGPoint(x: -half, y: -half)),
        ]
        for (seat, a, b) in corners {
            let path = CGMutablePath()
            path.move(to: a)
            path.addLine(to: b)
            path.addLine(to: .zero)
            path.closeSubpath()
            let triangle = SKShapeNode(path: path)
            triangle.fillColor = seat.tokenFill.withAlphaComponent(0.62)
            triangle.strokeColor = seat.tokenStroke.withAlphaComponent(0.9)
            triangle.lineWidth = 2
            triangle.lineJoin = .miter
            triangle.glowWidth = 1
            triangle.position = center
            triangle.zPosition = 4
            triangle.name = "centerTri_\(seat.rawValue)"
            root.addChild(triangle)
        }
    }
}
