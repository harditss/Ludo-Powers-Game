//
//  LudoSeat.swift
//  ludo
//

import SpriteKit

/// One corner of the board. Order is clockwise starting bottom-left (common printed-board layout).
enum LudoSeat: Int, CaseIterable, Hashable, Codable {
    case green = 0
    case yellow = 1
    case red = 2
    case blue = 3

    var tokenFill: SKColor {
        switch self {
        case .green: return SKColor(red: 0.15, green: 0.65, blue: 0.28, alpha: 1)
        case .yellow: return SKColor(red: 0.95, green: 0.78, blue: 0.1, alpha: 1)
        case .red: return SKColor(red: 0.9, green: 0.2, blue: 0.18, alpha: 1)
        case .blue: return SKColor(red: 0.2, green: 0.45, blue: 0.95, alpha: 1)
        }
    }

    var tokenStroke: SKColor {
        switch self {
        case .green: return SKColor(red: 0.05, green: 0.35, blue: 0.12, alpha: 1)
        case .yellow: return SKColor(red: 0.5, green: 0.4, blue: 0.02, alpha: 1)
        case .red: return SKColor(red: 0.45, green: 0.05, blue: 0.05, alpha: 1)
        case .blue: return SKColor(red: 0.05, green: 0.2, blue: 0.55, alpha: 1)
        }
    }

    var baseFill: SKColor {
        tokenFill.withAlphaComponent(0.35)
    }

    var baseStroke: SKColor {
        tokenStroke.withAlphaComponent(0.6)
    }

    /// Which corners are in play for a given count (2 = opposite **green** vs **red**).
    static func activeSeats(forPlayerCount count: Int) -> Set<LudoSeat> {
        switch min(4, max(2, count)) {
        case 2: return [.green, .red]
        case 3: return [.green, .yellow, .red]
        default: return Set(LudoSeat.allCases)
        }
    }

    var displayName: String {
        switch self {
        case .green: return "Green"
        case .yellow: return "Yellow"
        case .red: return "Red"
        case .blue: return "Blue"
        }
    }
}
