//
//  LudoFrozenToken.swift
//  ludo
//
//  Freeze Token powerup — opponent track token cannot move on owner’s next turn.
//

import Foundation

struct LudoFrozenToken: Equatable, Sendable {
    let owner: LudoSeat
    let tokenId: Int
    let frozenBy: LudoSeat
}

struct LudoFrozenTokenKey: Hashable, Sendable {
    let owner: LudoSeat
    let tokenId: Int

    init(_ owner: LudoSeat, _ tokenId: Int) {
        self.owner = owner
        self.tokenId = tokenId
    }
}

enum LudoFreezeTargetRules {

    /// Opponent tokens on the main loop that can be frozen.
    static func validTargets(
        applier: LudoSeat,
        activeSeats: [LudoSeat],
        tokens: [LudoSeat: [LudoTokenSpot]],
        frozen: [LudoFrozenToken],
        shieldedTokenKeys: Set<LudoTokenShieldKey> = []
    ) -> [(seat: LudoSeat, tokenId: Int)] {
        let frozenKeys = Set(frozen.map { LudoFrozenTokenKey($0.owner, $0.tokenId) })
        var out: [(LudoSeat, Int)] = []
        for seat in activeSeats where seat != applier {
            guard let row = tokens[seat] else { continue }
            for tid in 0..<4 {
                let key = LudoFrozenTokenKey(seat, tid)
                if frozenKeys.contains(key) { continue }
                if shieldedTokenKeys.contains(LudoTokenShieldKey(seat, tid)) { continue }
                guard case .track = row[tid] else { continue }
                out.append((seat, tid))
            }
        }
        return out
    }

    static func canFreeze(
        owner: LudoSeat,
        tokenId: Int,
        applier: LudoSeat,
        activeSeats: [LudoSeat],
        tokens: [LudoSeat: [LudoTokenSpot]],
        frozen: [LudoFrozenToken],
        shieldedTokenKeys: Set<LudoTokenShieldKey> = []
    ) -> Bool {
        validTargets(
            applier: applier,
            activeSeats: activeSeats,
            tokens: tokens,
            frozen: frozen,
            shieldedTokenKeys: shieldedTokenKeys
        ).contains { $0.seat == owner && $0.tokenId == tokenId }
    }
}
