//
//  BaccaratRoadmapView.swift
//  hardway-craps
//
//  Big Road (大路) scoreboard for baccarat hand history.
//

import UIKit

/// Represents a single baccarat hand result
enum BaccaratResult {
    case banker
    case player
    case tie
}

/// Metadata for a single baccarat hand on the roadmap
struct BaccaratHandInfo {
    let result: BaccaratResult
    var isNatural: Bool = false
    var hasPair: Bool = false  // either side had a pair
}

/// Big Road scoreboard view — the classic baccarat hand history display.
/// Consecutive wins by the same side stack downward; a new column starts when the winner changes.
/// Ties are shown as a green diagonal slash on the last entry.
final class BaccaratRoadmapView: UIView {

    // MARK: - Configuration

    private let rows = 6
    private let cellSize: CGFloat
    private let cellSpacing: CGFloat
    private let cellInset: CGFloat

    // MARK: - State

    /// The full history of hand info
    private(set) var hands: [BaccaratHandInfo] = []

    /// Internal grid representation: each column is a list of cells
    private struct Cell {
        let result: BaccaratResult // .banker or .player (ties attach to prior cell)
        var isNatural: Bool = false
        var hasPair: Bool = false
        var tieCount: Int = 0      // number of ties on this cell
    }
    private var columns: [[Cell]] = []

    // MARK: - Subviews

    private let scrollView = UIScrollView()
    private let gridLayer = UIView()

    // MARK: - Init

    /// - Parameter compact: Use smaller cells for inline display
    init(compact: Bool = false) {
        if compact {
            self.cellSize = 14
            self.cellSpacing = 2
            self.cellInset = 1.5
        } else {
            self.cellSize = 20
            self.cellSpacing = 3
            self.cellInset = 2
        }
        super.init(frame: .zero)
        setup()
    }

    override init(frame: CGRect) {
        self.cellSize = 20
        self.cellSpacing = 3
        self.cellInset = 2
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        self.cellSize = 20
        self.cellSpacing = 3
        self.cellInset = 2
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor.white.withAlphaComponent(0.06)
        layer.cornerRadius = 6
        layer.masksToBounds = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)

        gridLayer.translatesAutoresizingMaskIntoConstraints = true
        scrollView.addSubview(gridLayer)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])

        // Draw faint grid lines
        layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        layer.borderWidth = 0.5
    }

    private var lastDrawnWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        // Redraw when width changes or when there's a pending redraw (data changed while collapsed)
        if bounds.width != lastDrawnWidth || needsRedraw {
            redraw()
            scrollToEnd()
        }
    }

    // MARK: - Public API

    /// Record a new hand result and update the display
    func addResult(_ result: BaccaratResult, isNatural: Bool = false, hasPair: Bool = false) {
        hands.append(BaccaratHandInfo(result: result, isNatural: isNatural, hasPair: hasPair))
        rebuildGrid()
        setNeedsRedraw()
    }

    /// Force a redraw on next display cycle (safe to call when collapsed)
    private var needsRedraw = false
    private func setNeedsRedraw() {
        needsRedraw = true
        // Try to draw immediately if we have valid bounds
        if bounds.width > 0 {
            redraw()
            scrollToEnd()
        }
    }

    /// Clear all history
    func clearResults() {
        hands.removeAll()
        columns.removeAll()
        setNeedsRedraw()
    }

    // MARK: - Grid Building (Big Road algorithm)

    private func rebuildGrid() {
        columns = []

        for hand in hands {
            if hand.result == .tie {
                // Attach tie to the last non-tie cell
                if !columns.isEmpty {
                    let lastCol = columns.count - 1
                    let lastRow = columns[lastCol].count - 1
                    if lastRow >= 0 {
                        columns[lastCol][lastRow].tieCount += 1
                    }
                }
                // If no previous cell exists, we just skip (tie before any hand)
                continue
            }

            let side = hand.result // .banker or .player
            let newCell = Cell(result: side, isNatural: hand.isNatural, hasPair: hand.hasPair)

            if columns.isEmpty {
                // First non-tie result starts column 0
                columns.append([newCell])
            } else {
                let lastCol = columns.count - 1
                let lastSide = columns[lastCol].first?.result ?? side

                if lastSide == side {
                    // Same winner — continue down in the same column
                    if columns[lastCol].count < rows {
                        columns[lastCol].append(newCell)
                    } else {
                        // Column full — "dragon tail": start a new column at the bottom row
                        columns.append([newCell])
                    }
                } else {
                    // Winner changed — start a new column
                    columns.append([newCell])
                }
            }
        }
    }

    // MARK: - Drawing

    private func redraw() {
        // Skip drawing when the view has no usable width
        guard bounds.width > 0 else { return }

        lastDrawnWidth = bounds.width
        needsRedraw = false

        // Remove old dots
        gridLayer.subviews.forEach { $0.removeFromSuperview() }
        gridLayer.layer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let stride = cellSize + cellSpacing
        let visibleWidth = max(scrollView.bounds.width, bounds.width)
        let minCols = Int(ceil(visibleWidth / stride))
        let totalCols = max(columns.count, minCols)
        let gridWidth = CGFloat(totalCols) * stride
        let gridHeight = CGFloat(rows) * stride

        // Update content size
        gridLayer.frame = CGRect(x: 0, y: 0, width: gridWidth, height: gridHeight)
        scrollView.contentSize = CGSize(width: gridWidth + 4, height: gridHeight)

        // Draw grid lines across the full visible area
        drawGridLines(cols: totalCols, stride: stride, gridHeight: gridHeight, gridWidth: gridWidth)

        // Draw cells
        for (colIndex, column) in columns.enumerated() {
            for (rowIndex, cell) in column.enumerated() {
                let x = CGFloat(colIndex) * stride
                let y = CGFloat(rowIndex) * stride
                let dotFrame = CGRect(x: x + cellInset, y: y + cellInset,
                                      width: cellSize - cellInset * 2, height: cellSize - cellInset * 2)
                let cellRect = CGRect(x: x, y: y, width: cellSize, height: cellSize)

                let dotView = makeDot(for: cell, frame: dotFrame)
                gridLayer.addSubview(dotView)

                // Pair indicator — small yellow dot in top-left corner
                if cell.hasPair {
                    let pairDot = makePairIndicator(at: cellRect)
                    gridLayer.addSubview(pairDot)
                }

                // Tie indicator(s)
                if cell.tieCount > 0 {
                    let tieLine = makeTieIndicator(at: cellRect, count: cell.tieCount)
                    gridLayer.layer.addSublayer(tieLine)
                }
            }
        }
    }

    private func drawGridLines(cols: Int, stride: CGFloat, gridHeight: CGFloat, gridWidth: CGFloat) {
        let gridLineColor = UIColor.white.withAlphaComponent(0.06).cgColor

        // Horizontal lines
        for row in 0...rows {
            let y = CGFloat(row) * stride
            let line = CALayer()
            line.frame = CGRect(x: 0, y: y, width: gridWidth, height: 0.5)
            line.backgroundColor = gridLineColor
            gridLayer.layer.addSublayer(line)
        }

        // Vertical lines
        for col in 0...cols {
            let x = CGFloat(col) * stride
            let line = CALayer()
            line.frame = CGRect(x: x, y: 0, width: 0.5, height: gridHeight)
            line.backgroundColor = gridLineColor
            gridLayer.layer.addSublayer(line)
        }
    }

    private func makeDot(for cell: Cell, frame: CGRect) -> UIView {
        let dot = UIView(frame: frame)
        dot.layer.cornerRadius = frame.width / 2

        switch cell.result {
        case .banker:
            if cell.isNatural {
                dot.backgroundColor = .systemRed
            } else {
                dot.backgroundColor = .clear
                dot.layer.borderColor = UIColor.systemRed.cgColor
                dot.layer.borderWidth = 1.5
            }
        case .player:
            if cell.isNatural {
                dot.backgroundColor = .systemBlue
            } else {
                dot.backgroundColor = .clear
                dot.layer.borderColor = UIColor.systemBlue.cgColor
                dot.layer.borderWidth = 1.5
            }
        case .tie:
            dot.backgroundColor = .systemGreen
        }

        return dot
    }

    private func makePairIndicator(at cellRect: CGRect) -> UIView {
        let size: CGFloat = cellSize * 0.35
        let dot = UIView(frame: CGRect(x: cellRect.minX, y: cellRect.minY, width: size, height: size))
        dot.backgroundColor = .systemYellow
        dot.layer.cornerRadius = size / 2
        return dot
    }

    private func makeTieIndicator(at cellRect: CGRect, count: Int) -> CAShapeLayer {
        let layer = CAShapeLayer()
        let path = UIBezierPath()

        // Draw a green diagonal line across the cell
        let inset: CGFloat = 2
        path.move(to: CGPoint(x: cellRect.minX + inset, y: cellRect.maxY - inset))
        path.addLine(to: CGPoint(x: cellRect.maxX - inset, y: cellRect.minY + inset))

        layer.path = path.cgPath
        layer.strokeColor = UIColor.systemGreen.cgColor
        layer.lineWidth = 1.5
        layer.fillColor = nil

        // If multiple ties, add a small count label
        if count > 1 {
            let textLayer = CATextLayer()
            textLayer.string = "\(count)"
            textLayer.fontSize = cellSize < 18 ? 7 : 9
            textLayer.foregroundColor = UIColor.systemGreen.cgColor
            textLayer.alignmentMode = .center
            textLayer.contentsScale = UIScreen.main.scale
            textLayer.frame = CGRect(x: cellRect.maxX - 8, y: cellRect.minY - 1, width: 10, height: 10)
            layer.addSublayer(textLayer)
        }

        return layer
    }

    /// Scroll so the newest column is visible when history overflows the viewport.
    /// `contentSize` is often padded wider than actual data (`minCols`); scrolling by full
    /// content width hid all beads on the left — users had to drag back to see anything.
    private func scrollToEnd() {
        let viewport = scrollView.bounds.width
        guard viewport > 0, scrollView.contentSize.width > 0 else { return }

        let stride = cellSize + cellSpacing
        let dataWidth = CGFloat(columns.count) * stride
        let maxContentOffset = max(scrollView.contentSize.width - viewport, 0)
        let targetOffset: CGFloat
        if dataWidth <= viewport {
            targetOffset = 0
        } else {
            targetOffset = dataWidth - viewport
        }
        scrollView.setContentOffset(CGPoint(x: min(targetOffset, maxContentOffset), y: 0), animated: true)
    }

    // MARK: - Sizing

    override var intrinsicContentSize: CGSize {
        let height = CGFloat(rows) * (cellSize + cellSpacing) + 4  // +4 for padding
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }
}
