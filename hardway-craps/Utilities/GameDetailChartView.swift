//
//  GameDetailChartView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/14/26.
//

import Charts
import SwiftUI
import UIKit

struct GameDetailChartView: View {
  private let points: [ChartPoint]
  /// Domain value under scrub/tap (snapped via Chart proxy).
  @State private var selectedRoll: Int?
  @State private var ruleXInGeometry: CGFloat?
  @State private var scrubPointInGeometry: CGPoint?
  @State private var lockOuterScrollForChart = false
  private let isBlackjack: Bool
  private let lockParentVerticalScrollWhileDragging: ((Bool) -> Void)?

  init(
    balanceHistory: [Int], betSizeHistory: [Int], atmVisitIndices: [Int] = [],
    isBlackjack: Bool = false,
    lockParentVerticalScrollWhileDragging: ((Bool) -> Void)? = nil
  ) {
    self.lockParentVerticalScrollWhileDragging = lockParentVerticalScrollWhileDragging
    self.isBlackjack = isBlackjack
    let count = min(balanceHistory.count, betSizeHistory.count)
    let atmIndicesSet = Set(atmVisitIndices)

    if count == 0 {
      points = [ChartPoint(rollIndex: 0, balance: 0, betSize: 0, isATMVisit: false)]
    } else {
      points = (0..<count).map { index in
        ChartPoint(
          rollIndex: index + 1,
          balance: balanceHistory[index],
          betSize: betSizeHistory[index],
          isATMVisit: atmIndicesSet.contains(index)
        )
      }
    }
  }

  private var rollOrHandLabel: String {
    isBlackjack ? "Hand" : "Roll"
  }

  private var hasCashInfusions: Bool {
    points.contains { $0.isATMVisit }
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

  private var lineChart: some View {
    Chart {
      ForEach(points) { point in
        LineMark(
          x: .value(rollOrHandLabel, point.rollIndex),
          y: .value("Amount", point.balance)
        )
        .foregroundStyle(by: .value("Series", "Balance"))
        .interpolationMethod(.catmullRom)
      }
      ForEach(points) { point in
        LineMark(
          x: .value(rollOrHandLabel, point.rollIndex),
          y: .value("Amount", point.betSize)
        )
        .foregroundStyle(by: .value("Series", "Bet Size"))
        .interpolationMethod(.catmullRom)
      }
      ForEach(points.filter(\.isATMVisit)) { point in
        PointMark(
          x: .value(rollOrHandLabel, point.rollIndex),
          y: .value("Amount", yDomain.upperBound)
        )
        .foregroundStyle(by: .value("Series", "Cash Infusion"))
        .symbol(.circle)
        .symbolSize(50)
      }
      if let selectedPoint = selectedPoint {
        PointMark(
          x: .value(rollOrHandLabel, selectedPoint.rollIndex),
          y: .value("Amount", selectedPoint.balance)
        )
        .foregroundStyle(Color(HardwayColors.yellow))

        PointMark(
          x: .value(rollOrHandLabel, selectedPoint.rollIndex),
          y: .value("Amount", selectedPoint.betSize)
        )
        .foregroundStyle(Color(HardwayColors.label))
      }
    }
  }

  private var configuredChart: some View {
    chartWithConditionalLegendForegroundScale
      .chartLegend(position: .bottom, alignment: .center)
      .chartXAxis {
        AxisMarks(position: .bottom)
      }
      .chartYAxis {
        AxisMarks(position: .leading)
      }
      .chartYScale(domain: yDomain)
      .chartOverlay { proxy in
        balanceChartOverlay(proxy: proxy)
      }
  }

  @ViewBuilder
  private var chartWithConditionalLegendForegroundScale: some View {
    if hasCashInfusions {
      lineChart
        .chartForegroundStyleScale([
          "Balance": Color(HardwayColors.yellow),
          "Bet Size": Color(HardwayColors.label),
          "Cash Infusion": Color.green,
        ])
    } else {
      lineChart
        .chartForegroundStyleScale([
          "Balance": Color(HardwayColors.yellow),
          "Bet Size": Color(HardwayColors.label),
        ])
    }
  }

  private func balanceChartOverlay(proxy: ChartProxy) -> some View {
    GeometryReader { geometry in
      let plotFrame = geometry[proxy.plotAreaFrame]
      ZStack(alignment: .topLeading) {
        scrubRuleLine(plotFrame: plotFrame)

        if let selectedPoint {
          let anchorX = scrubTooltipAnchorX(proxy: proxy, plotFrame: plotFrame, selectedPoint: selectedPoint)
          let tooltipCenter = ChartScrub.chartTooltipCenter(anchorX: anchorX, plot: plotFrame)

          balanceTooltipCard(for: selectedPoint)
            .frame(maxWidth: ChartScrub.tooltipMaxWidth, alignment: .leading)
            .position(x: tooltipCenter.x, y: tooltipCenter.y)
        }

        ChartPlotScrubLayer(
          plotFrame: plotFrame,
          lockParentScroll: $lockOuterScrollForChart,
          ruleXInGeometry: $ruleXInGeometry,
          scrubPointInGeometry: $scrubPointInGeometry,
          onPlotLocalX: { localX in
            if let roll: Int = proxy.value(atX: localX) {
              selectedRoll = clampRoll(roll)
            }
          },
          onScrubGestureEnded: { selectedRoll = nil },
          onTapFlashEnded: { selectedRoll = nil }
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

  /// Tooltip sits beside the scrub line while dragging; after release (tap flash) uses snapped category center.
  private func scrubTooltipAnchorX(proxy: ChartProxy, plotFrame: CGRect, selectedPoint: ChartPoint)
    -> CGFloat
  {
    if let rx = ruleXInGeometry {
      return rx
    }
    if let xPosition = proxy.position(forX: selectedPoint.rollIndex) {
      return plotFrame.origin.x + xPosition
    }
    return plotFrame.midX
  }

  private func balanceTooltipCard(for point: ChartPoint) -> some View {
    selectionCopy(for: point)
      .padding(8)
      .background(Color.black.opacity(0.8))
      .cornerRadius(8)
  }

  private func selectionCopy(for point: ChartPoint) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("\(isBlackjack ? "Hand" : "Roll") \(point.rollIndex)")
        .font(.caption2)
        .foregroundStyle(Color.white)
      Text("Balance: $\(point.balance)")
        .font(.caption2)
        .foregroundStyle(Color(HardwayColors.yellow))
      Text("Bet: $\(point.betSize)")
        .font(.caption2)
        .foregroundStyle(Color(HardwayColors.label))
    }
  }

  private var selectedPoint: ChartPoint? {
    guard let selectedRoll else { return nil }
    return points.first { $0.rollIndex == selectedRoll }
  }

  private var yDomain: ClosedRange<Double> {
    let balanceValues = points.map { Double($0.balance) }
    let betValues = points.map { Double($0.betSize) }
    let minValue = min(balanceValues.min() ?? 0, betValues.min() ?? 0)
    let maxValue = max(balanceValues.max() ?? 0, betValues.max() ?? 0)
    let range = max(maxValue - minValue, 1)
    let paddedMax = maxValue + range * 0.12
    let paddedMin = min(minValue - range * 0.05, 0)
    return paddedMin...paddedMax
  }

  private func clampRoll(_ roll: Int) -> Int {
    let minRoll = points.first?.rollIndex ?? 0
    let maxRoll = points.last?.rollIndex ?? 0
    return min(max(roll, minRoll), maxRoll)
  }
}

private struct ChartPoint: Identifiable {
  let id = UUID()
  let rollIndex: Int
  let balance: Int
  let betSize: Int
  let isATMVisit: Bool
}
