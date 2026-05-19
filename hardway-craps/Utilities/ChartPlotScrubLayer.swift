//
//  ChartPlotScrubLayer.swift
//  hardway-craps
//
//  Plot-local transparent scrub catcher: horizontal vs vertical hysteresis, tap flash, parent scroll lock.
//

import SwiftUI

struct ChartPlotScrubLayer: View {
  let plotFrame: CGRect
  @Binding var lockParentScroll: Bool
  @Binding var ruleXInGeometry: CGFloat?
  @Binding var scrubPointInGeometry: CGPoint?

  var horizontalDominanceRatio: CGFloat = ChartScrub.horizontalDominanceRatio
  var tapDistanceThreshold: CGFloat = ChartScrub.tapDistanceThreshold

  /// Plot-local X (0 … plot width) for `proxy.value(atX:)`.
  let onPlotLocalX: (CGFloat) -> Void
  let onScrubGestureEnded: () -> Void
  let onTapFlashEnded: () -> Void

  @State private var committedToScrub = false
  @State private var tapGeneration = 0

  var body: some View {
    Rectangle()
      .fill(Color.clear)
      .frame(width: plotFrame.width, height: plotFrame.height)
      .position(x: plotFrame.midX, y: plotFrame.midY)
      .contentShape(Rectangle())
      .highPriorityGesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            guard plotFrame.contains(value.location) else { return }

            if !committedToScrub {
              let dx = abs(value.translation.width)
              let dy = abs(value.translation.height)
              if dx > dy * horizontalDominanceRatio {
                committedToScrub = true
                lockParentScroll = true
                tapGeneration += 1
              } else if dy > 0, dx <= dy * horizontalDominanceRatio {
                return
              }
            }

            guard committedToScrub else { return }

            let localX = min(max(value.location.x - plotFrame.minX, 0), plotFrame.width)
            let localY = min(max(value.location.y - plotFrame.minY, 0), plotFrame.height)
            let finger = CGPoint(x: plotFrame.minX + localX, y: plotFrame.minY + localY)
            ruleXInGeometry = finger.x
            scrubPointInGeometry = finger
            onPlotLocalX(localX)
          }
          .onEnded { value in
            let wasScrub = committedToScrub
            committedToScrub = false
            lockParentScroll = false
            ruleXInGeometry = nil
            scrubPointInGeometry = nil

            if wasScrub {
              onScrubGestureEnded()
              return
            }

            let dist = hypot(value.translation.width, value.translation.height)
            guard plotFrame.contains(value.location), dist < tapDistanceThreshold else {
              return
            }

            let localX = min(max(value.location.x - plotFrame.minX, 0), plotFrame.width)
            onPlotLocalX(localX)
            tapGeneration += 1
            let gen = tapGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
              guard gen == tapGeneration else { return }
              onTapFlashEnded()
            }
          }
      )
  }
}
