//
//  DiceOutcomeHistogramChartView.swift
//  hardway-craps
//
//  Bar chart of dice totals 2...12 for the current Craps session.
//

import Charts
import SwiftUI
import UIKit

struct DiceOutcomeHistogramChartView: View {
  /// Bins for totals 2...12; index i = count for (i + 2).
  let counts: [Int]

  @State private var selectedDiceTotal: Int?
  @State private var ruleXInGeometry: CGFloat?
  @State private var scrubPointInGeometry: CGPoint?
  @State private var lockOuterScrollForChart = false
  private let lockParentVerticalScrollWhileDragging: ((Bool) -> Void)?

  init(counts: [Int], lockParentVerticalScrollWhileDragging: ((Bool) -> Void)? = nil) {
    self.counts = counts
    self.lockParentVerticalScrollWhileDragging = lockParentVerticalScrollWhileDragging
  }

  private var bars: [(total: Int, count: Int)] {
    (2...12).map { total in
      let idx = total - 2
      let c = (idx < counts.count) ? counts[idx] : 0
      return (total, c)
    }
  }

  private var diceCategoryLabels: [String] {
    (2...12).map { String($0) }
  }

  private var totalRolls: Int {
    counts.reduce(0, +)
  }

  private var yUpper: Int {
    let m = bars.map(\.count).max() ?? 0
    return max(m, 1)
  }

  private static func outcomesForTotal(_ total: Int) -> Int {
    guard (2...12).contains(total) else { return 0 }
    return min(total - 1, 13 - total)
  }

  var body: some View {
    configuredChart
      .padding(.vertical, 8)
      .onChange(of: lockOuterScrollForChart) { _, locked in
        lockParentVerticalScrollWhileDragging?(locked)
      }
      .onDisappear {
        lockOuterScrollForChart = false
        ruleXInGeometry = nil
        scrubPointInGeometry = nil
        lockParentVerticalScrollWhileDragging?(false)
      }
  }

  private var barMarksChart: some View {
    Chart {
      ForEach(bars, id: \.total) { item in
        BarMark(
          x: .value("Total", String(item.total)),
          y: .value("Rolls", item.count)
        )
        .foregroundStyle(barForeground(for: item.total))
      }
    }
  }

  private var configuredChart: some View {
    barMarksChart
      .chartXScale(domain: diceCategoryLabels)
      .chartXAxis {
        AxisMarks(values: diceCategoryLabels) { value in
          AxisGridLine()
          AxisTick()
          AxisValueLabel(centered: true) {
            if let label = value.as(String.self) {
              Text(label)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.9))
            }
          }
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading)
      }
      .chartYScale(domain: 0...Double(yUpper))
      .chartPlotStyle { plot in
        plot.padding(.horizontal, 4)
      }
      .animation(.easeInOut(duration: 0.15), value: selectedDiceTotal)
      .chartOverlay { proxy in
        histogramOverlay(proxy: proxy)
      }
  }

  private func histogramOverlay(proxy: ChartProxy) -> some View {
    GeometryReader { geometry in
      let plotFrame = geometry[proxy.plotAreaFrame]
      ZStack(alignment: .topLeading) {
        scrubRuleLine(plotFrame: plotFrame)

        if let t = selectedDiceTotal {
          let anchorX = scrubTooltipAnchorX(proxy: proxy, plotFrame: plotFrame, diceTotal: t)
          let tooltipCenter = ChartScrub.chartTooltipCenter(anchorX: anchorX, plot: plotFrame)

          diceTooltipCard(diceTotal: t)
            .frame(maxWidth: ChartScrub.tooltipMaxWidth, alignment: .leading)
            .position(x: tooltipCenter.x, y: tooltipCenter.y)
        }

        ChartPlotScrubLayer(
          plotFrame: plotFrame,
          lockParentScroll: $lockOuterScrollForChart,
          ruleXInGeometry: $ruleXInGeometry,
          scrubPointInGeometry: $scrubPointInGeometry,
          onPlotLocalX: { localX in
            selectedDiceTotal = diceTotalFromChart(proxy: proxy, xPosition: localX)
          },
          onScrubGestureEnded: { selectedDiceTotal = nil },
          onTapFlashEnded: { selectedDiceTotal = nil }
        )
      }
    }
  }

  @ViewBuilder
  private func scrubRuleLine(plotFrame: CGRect) -> some View {
    if let ruleX = ruleXInGeometry {
      Path { path in
        path.move(to: CGPoint(x: ruleX, y: plotFrame.minY))
        path.addLine(to: CGPoint(x: ruleX, y: plotFrame.maxY))
      }
      .stroke(Color(HardwayColors.label), style: StrokeStyle(lineWidth: 1, dash: [4]))
    }
  }

  private func scrubTooltipAnchorX(proxy: ChartProxy, plotFrame: CGRect, diceTotal: Int) -> CGFloat {
    if let rx = ruleXInGeometry {
      return rx
    }
    if let xPosition = proxy.position(forX: String(diceTotal)) {
      return plotFrame.origin.x + xPosition
    }
    return plotFrame.midX
  }

  private func diceTooltipCard(diceTotal: Int) -> some View {
    diceTooltipCopy(diceTotal: diceTotal)
      .padding(8)
      .background(Color.black.opacity(0.8))
      .cornerRadius(8)
  }

  private func diceTooltipCopy(diceTotal: Int) -> some View {
    let idx = diceTotal - 2
    let timesRolled = (idx >= 0 && idx < counts.count) ? counts[idx] : 0
    let actualPct = totalRolls > 0 ? Double(timesRolled) / Double(totalRolls) * 100 : 0
    let expectedPct = Double(Self.outcomesForTotal(diceTotal)) / 36.0 * 100

    return VStack(alignment: .leading, spacing: 4) {
      Text("Total \(diceTotal)")
        .font(.caption2)
        .foregroundStyle(Color.white)
      Text("Times rolled: \(timesRolled)")
        .font(.caption2)
        .foregroundStyle(Color(HardwayColors.yellow))
      Text(String(format: "Session: %.1f%%", actualPct))
        .font(.caption2)
        .foregroundStyle(Color(HardwayColors.label))
      Text(String(format: "Expected: %.1f%%", expectedPct))
        .font(.caption2)
        .foregroundStyle(Color.white.opacity(0.85))
    }
  }

  private func barForeground(for total: Int) -> Color {
    guard let sel = selectedDiceTotal else {
      return Color(HardwayColors.betGray)
    }
    if sel == total {
      return Color(HardwayColors.yellow)
    }
    return Color(HardwayColors.betGray).opacity(ChartScrub.dimmedBarOpacity)
  }

  private func diceTotalFromChart(proxy: ChartProxy, xPosition: CGFloat) -> Int? {
    if let label: String = proxy.value(atX: xPosition), let n = Int(label) {
      return clampDiceTotal(n)
    }
    if let n: Int = proxy.value(atX: xPosition) {
      return clampDiceTotal(n)
    }
    return nil
  }

  private func clampDiceTotal(_ raw: Int) -> Int {
    min(max(raw, 2), 12)
  }
}
