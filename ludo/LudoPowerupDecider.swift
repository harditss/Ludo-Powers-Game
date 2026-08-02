//
//  LudoPowerupDecider.swift
//  ludo
//
//  Weighted rarity rolls for mystery-tile powerups based on strength gap to the leader.
//

import Foundation

enum LudoPowerupDecider {

    /// Powerups eligible when a given rarity is rolled.
    static func powerups(for rarity: LudoPowerupRarity) -> [LudoPowerup] {
        LudoPowerup.allCases.filter { $0.rarity == rarity && $0.isImplemented }
    }

    /// Picks uniformly from the pool for `rarity`, or `nil` if the pool is empty.
    static func rollPowerup(for rarity: LudoPowerupRarity) -> LudoPowerup? {
        let pool = powerups(for: rarity)
        guard !pool.isEmpty else { return nil }
        return pool.randomElement()
    }

    /// Table from design: `scoreGapToLeader` = max leaderboard strength minus this seat’s strength (0 if tied or leading).
    static func powerupWeights(scoreGapToLeader gap: Int) -> [LudoPowerupRarity: Double] {
        let g = max(0, gap)
        if g <= 20 {
            return [.common: 65, .rare: 24, .epic: 7, .legendary: 1, .bad: 3]
        }
        if g <= 50 {
            return [.common: 53, .rare: 33, .epic: 10, .legendary: 2, .bad: 2]
        }
        if g <= 90 {
            return [.common: 39.5, .rare: 37.5, .epic: 17, .legendary: 5, .bad: 1]
        }
        if g <= 140 {
            return [.common: 24, .rare: 40, .epic: 26, .legendary: 10, .bad: 0]
        }
        return [.common: 15, .rare: 38, .epic: 32, .legendary: 15, .bad: 0]
    }

    static func rollRarity(scoreGapToLeader gap: Int) -> LudoPowerupRarity {
        let table = powerupWeights(scoreGapToLeader: gap)
        let order: [LudoPowerupRarity] = [.common, .rare, .epic, .legendary, .bad]
        let total = order.reduce(0.0) { $0 + max(0, table[$1] ?? 0) }
        guard total > 0 else { return .common }
        var roll = Double.random(in: 0..<total)
        for key in order {
            let w = max(0, table[key] ?? 0)
            if w == 0 { continue }
            roll -= w
            if roll < 0 { return key }
        }
        return .common
    }
}
