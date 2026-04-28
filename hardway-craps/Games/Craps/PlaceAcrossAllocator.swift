//
//  PlaceAcrossAllocator.swift
//  hardway-craps
//

import Foundation

/// One valid “across” spread: same amount on 4/5/9/10 (`outsideEach`) and on 6/8 (`insideEach`).
struct PlaceAcrossAllocation: Equatable {
    let outsideEach: Int
    let insideEach: Int

    var total: Int { 4 * outsideEach + 2 * insideEach }
}

enum PlaceAcrossAllocator {

    /// Target ratio inside/outside (e.g. $30 / $25 = 1.2).
    private static let targetInsideOverOutside: Double = 1.2

    /// Table-style **$10 minimum per number** (app does not enforce on manual place bets, but across presets follow it).
    /// Outside (4/5/9/10): at least $10, multiples of $5.
    /// Inside (6/8): at least **$12** each — smallest multiple of $6 ≥ $10 (true 7:6 place units).
    static let minimumOutsideEach = 10
    static let minimumInsideEach = 12

    /// Smallest total for a full six-number across at the above minimums ($64).
    static var minimumSpreadTotal: Int { 4 * minimumOutsideEach + 2 * minimumInsideEach }

    /// Minimum across: **$10** on 4 / 5 / 9 / 10, **$12** on 6 & 8 ($64 total).
    static var canonicalMinimumAcross: PlaceAcrossAllocation {
        PlaceAcrossAllocation(outsideEach: minimumOutsideEach, insideEach: minimumInsideEach)
    }

    /// Featured “classic” across total ($25 on 4/5/9/10, $30 on 6 & 8).
    static let featuredAcrossTotal = 160

    private static var minimumFullTotal: Int { minimumSpreadTotal }

    /// Finds a valid allocation for an exact total: outside multiples of $5, inside multiples of $6,
    /// full six numbers (`outsideEach` / `insideEach` at least the table mins above). Prefers ratios near `targetInsideOverOutside`.
    /// - Parameter chipStep: If set, both amounts must be multiples of this value (e.g. selected chip).
    static func allocation(forExactTotal total: Int, chipStep: Int? = nil) -> PlaceAcrossAllocation? {
        guard total >= minimumFullTotal else { return nil }

        var best: (o: Int, i: Int, score: Double)?
        let maxO = total / 4

        for o in stride(from: 0, through: maxO, by: 5) {
            let rem = total - 4 * o
            guard rem >= 0, rem % 2 == 0 else { continue }
            let i = rem / 2
            guard i % 6 == 0 else { continue }
            if let step = chipStep, step > 0 {
                guard o % step == 0, i % step == 0 else { continue }
            }
            guard o >= minimumOutsideEach, i >= minimumInsideEach else { continue }

            let ratio = Double(i) / Double(o)
            let score = abs(ratio - targetInsideOverOutside)
            if let current = best {
                if score < current.score - 1e-9 {
                    best = (o, i, score)
                } else if abs(score - current.score) <= 1e-9, o > current.o {
                    best = (o, i, score)
                }
            } else {
                best = (o, i, score)
            }
        }

        guard let b = best else { return nil }
        return PlaceAcrossAllocation(outsideEach: b.o, insideEach: b.i)
    }

    /// Preset totals ≤ `balance` with a valid allocation, largest first, capped at `maxOptions`.
    /// The **canonical minimum across** ($10 / $12 / $64) is always included when balance allows,
    /// even if it would not appear among the top `maxOptions` totals from balance alone.
    static func presets(
        balance: Int,
        chipStepPreferred: Int?,
        maxOptions: Int = 4
    ) -> [PlaceAcrossAllocation] {
        guard balance >= minimumFullTotal, maxOptions > 0 else { return [] }

        let minimumAlloc = canonicalMinimumAcross
        let reserveMinimumSlot = balance >= minimumAlloc.total
        let collectLimit = max(0, maxOptions - (reserveMinimumSlot ? 1 : 0))

        func collect(usingChipStep step: Int?, limit: Int) -> [PlaceAcrossAllocation] {
            guard limit > 0 else { return [] }
            var seen = Set<Int>()
            var result: [PlaceAcrossAllocation] = []
            var t = balance
            if t % 2 != 0 { t -= 1 }
            while t >= minimumFullTotal {
                if let alloc = allocation(forExactTotal: t, chipStep: step), seen.insert(alloc.total).inserted {
                    result.append(alloc)
                    if result.count >= limit { break }
                }
                t -= 2
            }
            return result
        }

        var result: [PlaceAcrossAllocation]
        if let step = chipStepPreferred, step > 1 {
            let strict = collect(usingChipStep: step, limit: collectLimit)
            result = strict.isEmpty ? collect(usingChipStep: nil, limit: collectLimit) : strict
        } else {
            result = collect(usingChipStep: nil, limit: collectLimit)
        }

        if reserveMinimumSlot && !result.contains(minimumAlloc) {
            result.append(minimumAlloc)
        }
        result.sort { $0.total > $1.total }
        return result
    }

    /// Curated menu: **$64 minimum**, **$160** classic, then **two** valid spreads above $160 (compact, no long list).
    static func menuRows(balance: Int) -> [(allocation: PlaceAcrossAllocation, isEnabled: Bool)] {
        var seen = Set<Int>()
        var rows: [(allocation: PlaceAcrossAllocation, isEnabled: Bool)] = []

        @discardableResult
        func append(_ alloc: PlaceAcrossAllocation) -> Bool {
            guard !seen.contains(alloc.total) else { return false }
            seen.insert(alloc.total)
            rows.append((allocation: alloc, isEnabled: balance >= alloc.total))
            return true
        }

        append(canonicalMinimumAcross)

        if let featured = allocation(forExactTotal: featuredAcrossTotal, chipStep: nil) {
            append(featured)
        }

        var t = featuredAcrossTotal + 2
        if t % 2 != 0 { t += 1 }
        var tiersAboveFeatured = 0
        let scanCap = featuredAcrossTotal + 20_000
        while tiersAboveFeatured < 2 && t <= scanCap {
            if let alloc = allocation(forExactTotal: t, chipStep: nil),
               alloc.total > featuredAcrossTotal {
                if append(alloc) { tiersAboveFeatured += 1 }
            }
            t += 2
        }

        rows.sort { $0.allocation.total < $1.allocation.total }
        return rows
    }
}
