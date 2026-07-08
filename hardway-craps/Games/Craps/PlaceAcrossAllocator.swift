//
//  PlaceAcrossAllocator.swift
//  hardway-craps
//

import Foundation

/// One valid “across” spread: same amount on outside box numbers and on 6/8 (`insideEach`).
struct PlaceAcrossAllocation: Equatable {
    let variant: CrapsVariant
    let outsideEach: Int
    let insideEach: Int

    var total: Int {
        PlaceAcrossAllocator.outsideCount(for: variant) * outsideEach + 2 * insideEach
    }
}

enum PlaceAcrossAllocator {

    /// Target ratio inside/outside (e.g. $30 / $25 = 1.2).
    private static let targetInsideOverOutside: Double = 1.2

    /// Table-style **$10 minimum per number** (app does not enforce on manual place bets, but across presets follow it).
    /// Outside boxes: at least $10, multiples of $5.
    /// Inside (6/8): at least **$12** each — smallest multiple of $6 ≥ $10 (true 7:6 place units).
    static let minimumOutsideEach = 10
    static let minimumInsideEach = 12

    static func outsideCount(for variant: CrapsVariant) -> Int {
        switch variant {
        case .standard: return 4
        case .crapless: return 8
        }
    }

    /// Smallest total for a full spread at table minimums (standard $64, crapless $104).
    static func minimumSpreadTotal(for variant: CrapsVariant) -> Int {
        outsideCount(for: variant) * minimumOutsideEach + 2 * minimumInsideEach
    }

    /// Minimum across at **$10** outside boxes per number and **$12** on 6 & 8.
    static func canonicalMinimumAcross(for variant: CrapsVariant) -> PlaceAcrossAllocation {
        PlaceAcrossAllocation(
            variant: variant,
            outsideEach: minimumOutsideEach,
            insideEach: minimumInsideEach
        )
    }

    /// Featured “classic” across: standard $160 ($25 / $30); crapless $260 (same per-number).
    static func featuredAcrossTotal(for variant: CrapsVariant) -> Int {
        switch variant {
        case .standard: return 160
        case .crapless: return 260
        }
    }

    private static func minimumFullTotal(for variant: CrapsVariant) -> Int {
        minimumSpreadTotal(for: variant)
    }

    /// Human-readable outside box list for menus (middle dot separators).
    static func outsideBoxesMenuLabel(for variant: CrapsVariant) -> String {
        switch variant {
        case .standard:
            return "4·5·9·10"
        case .crapless:
            return "2·3·4·5·9·10·11·12"
        }
    }

    /// Slash-separated outside boxes for table instruction text.
    static func outsideBoxesInstructionLabel(for variant: CrapsVariant) -> String {
        switch variant {
        case .standard:
            return "4/5/9/10"
        case .crapless:
            return "2/3/4/5/9/10/11/12"
        }
    }

    /// Finds a valid allocation for an exact total: outside multiples of $5, inside multiples of $6,
    /// at least table mins. Prefers ratios near `targetInsideOverOutside`.
    /// - Parameter chipStep: If set, both amounts must be multiples of this value (e.g. selected chip).
    static func allocation(forExactTotal total: Int, variant: CrapsVariant, chipStep: Int? = nil) -> PlaceAcrossAllocation? {
        let outsideN = outsideCount(for: variant)
        let minTotal = minimumFullTotal(for: variant)
        guard total >= minTotal else { return nil }

        var best: (o: Int, i: Int, score: Double)?
        let maxO = total / outsideN

        for o in stride(from: 0, through: maxO, by: 5) {
            let rem = total - outsideN * o
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
        return PlaceAcrossAllocation(variant: variant, outsideEach: b.o, insideEach: b.i)
    }

    /// Preset totals ≤ `balance` with a valid allocation, largest first, capped at `maxOptions`.
    /// Canonical minimum is always included when balance allows.
    static func presets(
        balance: Int,
        variant: CrapsVariant,
        chipStepPreferred: Int?,
        maxOptions: Int = 4
    ) -> [PlaceAcrossAllocation] {
        let minTotal = minimumFullTotal(for: variant)
        guard balance >= minTotal, maxOptions > 0 else { return [] }

        let minimumAlloc = canonicalMinimumAcross(for: variant)
        let reserveMinimumSlot = balance >= minimumAlloc.total
        let collectLimit = max(0, maxOptions - (reserveMinimumSlot ? 1 : 0))

        func collect(usingChipStep step: Int?, limit: Int) -> [PlaceAcrossAllocation] {
            guard limit > 0 else { return [] }
            var seen = Set<Int>()
            var result: [PlaceAcrossAllocation] = []
            var t = balance
            if t % 2 != 0 { t -= 1 }
            while t >= minTotal {
                if let alloc = allocation(forExactTotal: t, variant: variant, chipStep: step), seen.insert(alloc.total).inserted {
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

    /// Curated menu: minimum, classic featured total, then two valid spreads above featured.
    static func menuRows(balance: Int, variant: CrapsVariant) -> [(allocation: PlaceAcrossAllocation, isEnabled: Bool)] {
        var seen = Set<Int>()
        var rows: [(allocation: PlaceAcrossAllocation, isEnabled: Bool)] = []

        @discardableResult
        func append(_ alloc: PlaceAcrossAllocation) -> Bool {
            guard !seen.contains(alloc.total) else { return false }
            seen.insert(alloc.total)
            rows.append((allocation: alloc, isEnabled: balance >= alloc.total))
            return true
        }

        append(canonicalMinimumAcross(for: variant))

        let featuredTotal = featuredAcrossTotal(for: variant)
        if let featured = allocation(forExactTotal: featuredTotal, variant: variant, chipStep: nil) {
            append(featured)
        }

        var t = featuredTotal + 2
        if t % 2 != 0 { t += 1 }
        var tiersAboveFeatured = 0
        let scanCap = featuredTotal + 20_000
        while tiersAboveFeatured < 2 && t <= scanCap {
            if let alloc = allocation(forExactTotal: t, variant: variant, chipStep: nil),
               alloc.total > featuredTotal {
                if append(alloc) { tiersAboveFeatured += 1 }
            }
            t += 2
        }

        rows.sort { $0.allocation.total < $1.allocation.total }
        return rows
    }
}

extension PlaceAcrossAllocation {

  /// Total chips placed when the active **point** box is omitted (same outside vs inside amount rule as `applyPlaceAcross`).
  func chipCostSkipping(pointNumber: Int?) -> Int {
    guard let p = pointNumber else { return total }
    let insideBoxes: Set<Int> = [6, 8]
    let deduction = insideBoxes.contains(p) ? insideEach : outsideEach
    return total - deduction
  }
}
