//
//  LudoTokenShield.swift
//  ludo
//
//  Small Shield / Big Shield — one-hit protection from harmful effects.
//

import Foundation

enum LudoShieldKind: String, Equatable, Sendable {
    case small
    case big
}

struct LudoActiveShield: Equatable, Sendable {
    let owner: LudoSeat
    let tokenId: Int
    let kind: LudoShieldKind
    let appliedBy: LudoSeat
}

struct LudoTokenShieldKey: Hashable, Sendable {
    let owner: LudoSeat
    let tokenId: Int

    init(_ owner: LudoSeat, _ tokenId: Int) {
        self.owner = owner
        self.tokenId = tokenId
    }
}

enum LudoSmallShieldTargetRules {

    /// Own tokens on the track or home stretch that can receive Small Shield.
    static func validTargets(
        applier: LudoSeat,
        tokens: [LudoSeat: [LudoTokenSpot]],
        shields: [LudoActiveShield]
    ) -> [(seat: LudoSeat, tokenId: Int)] {
        let shieldedKeys = Set(shields.map { LudoTokenShieldKey($0.owner, $0.tokenId) })
        guard let row = tokens[applier] else { return [] }
        var out: [(LudoSeat, Int)] = []
        for tid in 0..<4 {
            let key = LudoTokenShieldKey(applier, tid)
            if shieldedKeys.contains(key) { continue }
            switch row[tid] {
            case .track, .home:
                out.append((applier, tid))
            case .yard, .finished:
                break
            }
        }
        return out
    }

    static func canApply(
        owner: LudoSeat,
        tokenId: Int,
        applier: LudoSeat,
        tokens: [LudoSeat: [LudoTokenSpot]],
        shields: [LudoActiveShield]
    ) -> Bool {
        guard owner == applier else { return false }
        return validTargets(applier: applier, tokens: tokens, shields: shields)
            .contains { $0.seat == owner && $0.tokenId == tokenId }
    }
}
