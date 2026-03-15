//
//  PageCurlView.swift
//  hardway-craps
//
//  Based on StPageFlip algorithm
//  Created by Colton Swapp on 3/7/26.
//

import UIKit

final class PageCurlView: UIView {

    // The card images
    private var backImage: UIImage?
    private var frontImage: UIImage?

    // Current curl state
    private var curlPoint: CGPoint = .zero
    private var isCurling = false

    // Curl corner
    enum CurlCorner {
        case topRight
        case bottomRight

        func defaultPoint(in bounds: CGRect) -> CGPoint {
            switch self {
            case .topRight: return CGPoint(x: bounds.maxX, y: bounds.minY)
            case .bottomRight: return CGPoint(x: bounds.maxX, y: bounds.maxY)
            }
        }
    }

    private var curlCorner: CurlCorner = .bottomRight

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImages(back: UIImage?, front: UIImage?) {
        self.backImage = back
        self.frontImage = front
    }

    func updateCurl(at point: CGPoint, corner: CurlCorner) {
        self.curlPoint = point
        self.curlCorner = corner
        self.isCurling = true
        setNeedsDisplay()
    }

    func resetCurl() {
        self.isCurling = false
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        if !isCurling {
            // Just draw the back image
            if let backImage = backImage {
                backImage.draw(in: bounds)
            }
            return
        }

        // Calculate curl geometry
        let geometry = calculateCurlGeometry(point: curlPoint, corner: curlCorner, bounds: bounds)

        // Draw the front page (revealed underneath)
        if let frontImage = frontImage {
            ctx.saveGState()
            if let clipPath = geometry.bottomClipPath {
                ctx.addPath(clipPath)
                ctx.clip()
            }
            frontImage.draw(in: bounds)
            ctx.restoreGState()
        }

        // Draw the curling page (back image transformed)
        if let backImage = backImage {
            ctx.saveGState()

            // Clip to the flipping area
            if let clipPath = geometry.flippingClipPath {
                ctx.addPath(clipPath)
                ctx.clip()
            }

            // Apply transform for the curl
            if let transform = geometry.transform {
                ctx.concatenate(transform)
            }

            backImage.draw(in: bounds)
            ctx.restoreGState()
        }

        // Draw shadows
        drawShadows(ctx: ctx, geometry: geometry)
    }

    private func calculateCurlGeometry(point: CGPoint, corner: CurlCorner, bounds: CGRect) -> CurlGeometry {
        let pageWidth = bounds.width
        let pageHeight = bounds.height

        // Calculate distance from corner to curl point
        let cornerPoint = corner.defaultPoint(in: bounds)
        let dx = point.x - cornerPoint.x
        let dy = point.y - cornerPoint.y

        // Calculate angle using StPageFlip's formula
        let left = pageWidth - point.x
        let top = corner == .topRight ? point.y : (pageHeight - point.y)
        let distance = sqrt(top * top + left * left)

        guard distance > 0.1 else {
            return CurlGeometry(flippingClipPath: nil, bottomClipPath: nil, transform: nil, angle: 0, progress: 0)
        }

        let angle = 2 * acos(left / distance)

        // Calculate progress (0 to 1)
        let maxDistance = sqrt(pageWidth * pageWidth + pageHeight * pageHeight)
        let currentDistance = sqrt(dx * dx + dy * dy)
        let progress = min(max(currentDistance / maxDistance, 0), 1)

        // Create clipping paths
        let flippingPath = createFlippingClipPath(point: point, angle: angle, corner: corner, bounds: bounds)
        let bottomPath = createBottomClipPath(point: point, angle: angle, corner: corner, bounds: bounds)

        // Create transform (rotate around the curl axis)
        let transform = createCurlTransform(point: point, angle: angle, corner: corner, bounds: bounds)

        return CurlGeometry(
            flippingClipPath: flippingPath,
            bottomClipPath: bottomPath,
            transform: transform,
            angle: angle,
            progress: progress
        )
    }

    private func createFlippingClipPath(point: CGPoint, angle: CGFloat, corner: CurlCorner, bounds: CGRect) -> CGPath {
        let path = CGMutablePath()

        // Simplified clipping - create a triangle from corner to curl point
        let cornerPoint = corner.defaultPoint(in: bounds)

        path.move(to: cornerPoint)
        path.addLine(to: point)

        // Add perpendicular line to create the curl edge
        let perpX = point.x + cos(angle / 2) * bounds.width
        let perpY = point.y + sin(angle / 2) * bounds.height

        path.addLine(to: CGPoint(x: perpX, y: perpY))
        path.addLine(to: CGPoint(x: bounds.maxX, y: corner == .topRight ? 0 : bounds.maxY))
        path.closeSubpath()

        return path
    }

    private func createBottomClipPath(point: CGPoint, angle: CGFloat, corner: CurlCorner, bounds: CGRect) -> CGPath {
        let path = CGMutablePath()

        // The visible area under the curl
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: bounds.maxX, y: 0))
        path.addLine(to: point)
        path.addLine(to: CGPoint(x: 0, y: bounds.maxY))
        path.closeSubpath()

        return path
    }

    private func createCurlTransform(point: CGPoint, angle: CGFloat, corner: CurlCorner, bounds: CGRect) -> CGAffineTransform {
        // Simplified: just translate toward the curl point
        let cornerPoint = corner.defaultPoint(in: bounds)
        let dx = (point.x - cornerPoint.x) * 0.3
        let dy = (point.y - cornerPoint.y) * 0.3

        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: dx, y: dy)
        transform = transform.rotated(by: angle * 0.1)

        return transform
    }

    private func drawShadows(ctx: CGContext, geometry: CurlGeometry) {
        guard geometry.progress > 0 else { return }

        ctx.saveGState()

        // Draw a simple gradient shadow along the curl edge
        let shadowOpacity = min(geometry.progress * 0.5, 0.5)

        let colors = [
            UIColor.black.withAlphaComponent(shadowOpacity).cgColor,
            UIColor.black.withAlphaComponent(0).cgColor
        ]

        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(
                gradient,
                start: curlPoint,
                end: CGPoint(x: curlPoint.x - 50, y: curlPoint.y),
                options: []
            )
        }

        ctx.restoreGState()
    }

    private struct CurlGeometry {
        let flippingClipPath: CGPath?
        let bottomClipPath: CGPath?
        let transform: CGAffineTransform?
        let angle: CGFloat
        let progress: CGFloat
    }
}
