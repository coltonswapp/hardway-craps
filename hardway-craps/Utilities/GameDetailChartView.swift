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
  @State private var selectedRoll: Int?
  @State private var horizontalScrubLocksParentScroll = false
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

  var body: some View {
    configuredChart
      .padding(.vertical, 8)
      .onChange(of: horizontalScrubLocksParentScroll) { _, locked in
        lockParentVerticalScrollWhileDragging?(locked)
      }
      .onDisappear {
        horizontalScrubLocksParentScroll = false
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
        RuleMark(x: .value(rollOrHandLabel, selectedPoint.rollIndex))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
          .foregroundStyle(Color(HardwayColors.label))

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
    lineChart
      .chartForegroundStyleScale([
        "Balance": Color(HardwayColors.yellow),
        "Bet Size": Color(HardwayColors.label),
        "Cash Infusion": Color.green,
      ])
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

  private func balanceChartOverlay(proxy: ChartProxy) -> some View {
    GeometryReader { geometry in
      let plotFrame = geometry[proxy.plotAreaFrame]
      ZStack(alignment: .topLeading) {
        balanceInteractionLayer(
          proxy: proxy,
          plotFrame: plotFrame,
          scrubLocksParentScroll: $horizontalScrubLocksParentScroll
        )
        balanceSelectionOverlay(proxy: proxy, plotFrame: plotFrame)
      }
    }
  }

  private func balanceInteractionLayer(
    proxy: ChartProxy,
    plotFrame: CGRect,
    scrubLocksParentScroll: Binding<Bool>
  ) -> some View {
    Rectangle()
      .fill(Color.clear)
      .contentShape(Rectangle())
      .simultaneousGesture(
        SpatialTapGesture()
          .onEnded { event in
            updateRollSelection(proxy: proxy, plotFrame: plotFrame, location: event.location)
          }
      )
      .simultaneousGesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let horizontal = abs(value.translation.width)
            let vertical = abs(value.translation.height)
            let isHorizontalDominant = horizontal >= vertical * Self.horizontalScrubHysteresis
            if isHorizontalDominant {
              if !scrubLocksParentScroll.wrappedValue {
                scrubLocksParentScroll.wrappedValue = true
              }
              updateRollSelection(proxy: proxy, plotFrame: plotFrame, location: value.location)
            } else if scrubLocksParentScroll.wrappedValue {
              scrubLocksParentScroll.wrappedValue = false
            }
          }
          .onEnded { _ in
            if scrubLocksParentScroll.wrappedValue {
              scrubLocksParentScroll.wrappedValue = false
            }
            selectedRoll = nil
          }
      )
  }

  /// Horizontal movement can be slightly smaller than vertical and still count as chart scrubbing (snappier overlay).
  private static let horizontalScrubHysteresis: CGFloat = 0.42

  @ViewBuilder
  private func balanceSelectionOverlay(proxy: ChartProxy, plotFrame: CGRect) -> some View {
    if let selectedPoint,
      let xPosition = proxy.position(forX: selectedPoint.rollIndex)
    {
      let lineX = plotFrame.origin.x + xPosition
      Path { path in
        path.move(to: CGPoint(x: lineX, y: plotFrame.minY))
        path.addLine(to: CGPoint(x: lineX, y: plotFrame.maxY))
      }
      .stroke(Color(HardwayColors.label), style: StrokeStyle(lineWidth: 1, dash: [4]))

      selectionView(for: selectedPoint)
        .frame(width: 150, alignment: .leading)
        .position(
          x: min(max(lineX, plotFrame.minX + 75), plotFrame.maxX - 75),
          y: plotFrame.minY + 30
        )
    }
  }

  private func updateRollSelection(proxy: ChartProxy, plotFrame: CGRect, location: CGPoint) {
    let xPosition = min(max(location.x - plotFrame.origin.x, 0), plotFrame.width)
    if let roll: Int = proxy.value(atX: xPosition) {
      selectedRoll = clampRoll(roll)
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

  private func selectionView(for point: ChartPoint) -> some View {
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
    .padding(8)
    .background(Color.black.opacity(0.8))
    .cornerRadius(8)
  }
}

private struct ChartPoint: Identifiable {
  let id = UUID()
  let rollIndex: Int
  let balance: Int
  let betSize: Int
  let isATMVisit: Bool
}
