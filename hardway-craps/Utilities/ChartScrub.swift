//
//  ChartScrub.swift
//  hardway-craps
//
//  Shared constants and tooltip placement for chart scrub overlays.
//

import CoreGraphics

enum ChartScrub {
  static let horizontalDominanceRatio: CGFloat = 0.42
  static let tapDistanceThreshold: CGFloat = 12
  static let tooltipMaxWidth: CGFloat = 118
  static let tooltipEstimatedHeight: CGFloat = 76
  static let dimmedBarOpacity: Double = 0.22

  /// Places the tooltip beside the vertical scrub rule near the top of the plot (prefers trailing side).
  static func chartTooltipCenter(anchorX: CGFloat, plot: CGRect) -> CGPoint {
    let halfW = tooltipMaxWidth / 2
    let gapFromRule: CGFloat = 6
    let edgeInset: CGFloat = 2
    let h = tooltipEstimatedHeight

    var cx = anchorX + gapFromRule + halfW
    if cx + halfW > plot.maxX - edgeInset {
      cx = anchorX - gapFromRule - halfW
    }
    cx = min(max(cx, plot.minX + halfW + edgeInset), plot.maxX - halfW - edgeInset)

    var cy = plot.minY + h / 2
    if cy + h / 2 > plot.maxY - edgeInset {
      cy = plot.maxY - edgeInset - h / 2
    }
    return CGPoint(x: cx, y: cy)
  }
}
