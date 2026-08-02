//
//  LudoPowerup.swift
//  ludo
//
//  Mystery-tile powerup definitions and rarity pools.
//

import Foundation

enum LudoPowerupRarity: String, CaseIterable, Sendable {
    case common
    case rare
    case epic
    case legendary
    /// Deliberately negative / harmful outcomes when present in the table.
    case bad

    var displayTitle: String {
        rawValue.uppercased()
    }
}

enum LudoPowerup: String, CaseIterable, Sendable {
    case dash
    case trap
    case freezeToken
    case swap
    case smallShield
    /// Placeholder — stronger multi-hit protection (TBD).
    case bigShield
    case blackhole

    var displayName: String {
        switch self {
        case .dash: return "Dash"
        case .trap: return "Trap"
        case .freezeToken: return "Freeze Token"
        case .swap: return "Swap"
        case .smallShield: return "Small Shield"
        case .bigShield: return "Big Shield"
        case .blackhole: return "Blackhole"
        }
    }

    var rarity: LudoPowerupRarity {
        switch self {
        case .dash, .trap, .freezeToken, .smallShield: return .common
        case .swap: return .rare
        case .bigShield: return .epic
        case .blackhole: return .legendary
        }
    }

    /// Mystery-tile pool only includes implemented powerups.
    var isImplemented: Bool {
        switch self {
        case .dash, .trap, .freezeToken, .swap, .smallShield, .blackhole: return true
        case .bigShield: return false
        }
    }

    /// Steps to advance on the shared track / home stretch (not from yard).
    var forwardSteps: Int? {
        switch self {
        case .dash: return 3
        case .trap, .freezeToken, .swap, .smallShield, .bigShield, .blackhole: return nil
        }
    }

    /// How far clockwise Swap scans for the next token to swap with.
    static let swapSearchSteps = 25

    var effectSummary: String {
        switch self {
        case .dash:
            return "Move 3 spaces ahead immediately (that token)."
        case .trap:
            return "Place a trap on a white track tile (visible to all). Lasts \(LudoActiveTrap.maxFullRounds) full rounds (each player plays once per round). The next token that lands on it goes to the yard; that trap then disappears."
        case .freezeToken:
            return "Freeze an opponent’s token on the track. It cannot move on that player’s next turn (visible to all). Cleared if sent to the yard."
        case .swap:
            return "Swap with the next opponent’s token clockwise ahead within \(Self.swapSearchSteps) spaces. Skips opponents on their home stretch."
        case .smallShield:
            return "Give one of your tokens on the track or home stretch a 1-hit shield (visible to all). Blocks one capture, trap, freeze, or hazard hit; expires after your next turn if unused."
        case .bigShield:
            return "Coming soon — stronger shield for your token."
        case .blackhole:
            return "Place a blackhole on the white track (visible to all). Lasts \(LudoActiveBlackhole.maxFullRounds) full rounds. Any token that lands on or passes through it is sucked in; shields block once and stop on the tile."
        }
    }

    /// Rarity tiers for catalog / sorting (excludes empty tiers).
    static let catalogRarityOrder: [LudoPowerupRarity] = [.common, .rare, .epic, .legendary, .bad]

    /// Powerups listed in the in-game catalog (excludes removed / unreleased entries).
    static var catalogCases: [LudoPowerup] {
        allCases
    }

    static var catalogSortedByRarity: [LudoPowerup] {
        catalogCases.sorted { lhs, rhs in
            let li = catalogRarityOrder.firstIndex(of: lhs.rarity) ?? 99
            let ri = catalogRarityOrder.firstIndex(of: rhs.rarity) ?? 99
            if li != ri { return li < ri }
            return lhs.displayName < rhs.displayName
        }
    }

    static func catalogGroupedByRarity() -> [(rarity: LudoPowerupRarity, powerups: [LudoPowerup])] {
        catalogRarityOrder.compactMap { rarity in
            let list = catalogCases.filter { $0.rarity == rarity }
            return list.isEmpty ? nil : (rarity, list)
        }
    }

    static var implementedCases: [LudoPowerup] {
        allCases.filter(\.isImplemented)
    }
}
