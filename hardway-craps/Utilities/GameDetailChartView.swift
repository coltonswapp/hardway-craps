//
//  GameDetailChartView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/14/26.
//

import SwiftUI
import Charts
import UIKit

struct GameDetailChartView: View {
    private let points: [ChartPoint]
    @State private var selectedRoll: Int?
    private let isBlackjack: Bool

    init(balanceHistory: [Int], betSizeHistory: [Int], atmVisitIndices: [Int] = [], isBlackjack: Bool = false) {
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

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value(isBlackjack ? "Hand" : "Roll", point.rollIndex),
                    y: .value("Amount", point.balance)
                )
                .foregroundStyle(by: .value("Series", "Balance"))
                .interpolationMethod(.catmullRom)
            }
            ForEach(points) { point in
                LineMark(
                    x: .value(isBlackjack ? "Hand" : "Roll", point.rollIndex),
                    y: .value("Amount", point.betSize)
                )
                .foregroundStyle(by: .value("Series", "Bet Size"))
                .interpolationMethod(.catmullRom)
            }
            // Add green dots for ATM visits at the top of the chart
            ForEach(points.filter { $0.isATMVisit }) { point in
                PointMark(
                    x: .value(isBlackjack ? "Hand" : "Roll", point.rollIndex),
                    y: .value("Amount", yDomain.upperBound)
                )
                .foregroundStyle(by: .value("Series", "Cash Infusion"))
                .symbol(.circle)
                .symbolSize(50)
            }
            if let selectedPoint = selectedPoint {
                RuleMark(x: .value(isBlackjack ? "Hand" : "Roll", selectedPoint.rollIndex))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(Color(HardwayColors.label))

                PointMark(
                    x: .value(isBlackjack ? "Hand" : "Roll", selectedPoint.rollIndex),
                    y: .value("Amount", selectedPoint.balance)
                )
                .foregroundStyle(Color(HardwayColors.yellow))

                PointMark(
                    x: .value(isBlackjack ? "Hand" : "Roll", selectedPoint.rollIndex),
                    y: .value("Amount", selectedPoint.betSize)
                )
                .foregroundStyle(Color(HardwayColors.label))
            }
        }
        .chartForegroundStyleScale([
            "Balance": Color(HardwayColors.yellow),
            "Bet Size": Color(HardwayColors.label),
            "Cash Infusion": Color.green
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
            GeometryReader { geometry in
                let plotFrame = geometry[proxy.plotAreaFrame]

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let xPosition = min(max(value.location.x - plotFrame.origin.x, 0), plotFrame.width)
                                    if let roll: Int = proxy.value(atX: xPosition) {
                                        selectedRoll = clampRoll(roll)
                                    }
                                }
                                .onEnded { _ in
                                    selectedRoll = nil
                                }
                        )

                    if let selectedPoint,
                       let xPosition = proxy.position(forX: selectedPoint.rollIndex) {
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
            }
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
