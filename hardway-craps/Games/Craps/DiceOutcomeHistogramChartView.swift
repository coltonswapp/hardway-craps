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
    @State private var horizontalScrubLocksParentScroll = false
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

    /// String categories in roll order so the axis matches bar centers (not numeric 2…12 linear spacing).
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

    /// Ways to roll `total` with two fair d6 (out of 36).
    private static func outcomesForTotal(_ total: Int) -> Int {
        guard (2...12).contains(total) else { return 0 }
        return min(total - 1, 13 - total)
    }

    private static let tooltipHalfWidth: CGFloat = 95

    /// See `GameDetailChartView` — ratio so slight horizontal motion counts as scrubbing vs vertical scroll.
    private static let horizontalScrubVsVerticalRatio: CGFloat = 0.42

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
                interactionLayer(
                    proxy: proxy,
                    plotFrame: plotFrame,
                    scrubLocksParentScroll: $horizontalScrubLocksParentScroll
                )
                selectionOverlay(proxy: proxy, plotFrame: plotFrame)
            }
        }
    }

    private func interactionLayer(
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
                        updateSelection(proxy: proxy, plotFrame: plotFrame, location: event.location)
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let horizontal = abs(value.translation.width)
                        let vertical = abs(value.translation.height)
                        let isHorizontalDominant = horizontal >= vertical * Self.horizontalScrubVsVerticalRatio
                        if isHorizontalDominant {
                            if !scrubLocksParentScroll.wrappedValue {
                                scrubLocksParentScroll.wrappedValue = true
                            }
                            updateSelection(proxy: proxy, plotFrame: plotFrame, location: value.location)
                        } else if scrubLocksParentScroll.wrappedValue {
                            scrubLocksParentScroll.wrappedValue = false
                        }
                    }
                    .onEnded { _ in
                        if scrubLocksParentScroll.wrappedValue {
                            scrubLocksParentScroll.wrappedValue = false
                        }
                        selectedDiceTotal = nil
                    }
            )
    }

    @ViewBuilder
    private func selectionOverlay(proxy: ChartProxy, plotFrame: CGRect) -> some View {
        if let t = selectedDiceTotal,
           let xPosition = proxy.position(forX: String(t)) {
            let lineX = plotFrame.origin.x + xPosition
            Path { path in
                path.move(to: CGPoint(x: lineX, y: plotFrame.minY))
                path.addLine(to: CGPoint(x: lineX, y: plotFrame.maxY))
            }
            .stroke(Color(HardwayColors.label), style: StrokeStyle(lineWidth: 1, dash: [4]))

            selectionView(diceTotal: t)
                .frame(width: 190, alignment: .leading)
                .position(
                    x: min(
                        max(lineX, plotFrame.minX + Self.tooltipHalfWidth),
                        plotFrame.maxX - Self.tooltipHalfWidth
                    ),
                    y: plotFrame.minY + 40
                )
        }
    }

    private func updateSelection(proxy: ChartProxy, plotFrame: CGRect, location: CGPoint) {
        let xPosition = min(max(location.x - plotFrame.origin.x, 0), plotFrame.width)
        selectedDiceTotal = diceTotalFromChart(proxy: proxy, xPosition: xPosition)
    }

    private func barForeground(for total: Int) -> Color {
        if selectedDiceTotal == total {
            return Color(HardwayColors.yellow)
        }
        return Color(HardwayColors.betGray)
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

    private func selectionView(diceTotal: Int) -> some View {
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
        .padding(8)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
    }
}
