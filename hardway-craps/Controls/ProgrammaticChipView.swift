//
//  ProgrammaticChipView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 2/5/26.
//

import UIKit

class ProgrammaticChipView: UIControl {
    
    // MARK: - Properties
    
    let value: Int
    
    private let valueLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14, weight: .bold)
        return label
    }()
    
    // Chip styling properties
    var chipBackgroundColor: UIColor = UIColor(red: 78/255, green: 78/255, blue: 41/255, alpha: 1.0) {
        didSet {
            setNeedsDisplay()
        }
    }
    
    var ring1Color: UIColor = UIColor(red: 133/255, green: 133/255, blue: 0/255, alpha: 1.0) {
        didSet {
            setNeedsDisplay()
        }
    }
    
    var ring2Color: UIColor = UIColor(red: 255/255, green: 255/255, blue: 55/255, alpha: 1.0) {
        didSet {
            setNeedsDisplay()
        }
    }
    
    var textColor: UIColor = UIColor(red: 255/255, green: 255/255, blue: 73/255, alpha: 1.0) {
        didSet {
            valueLabel.textColor = textColor
        }
    }
    
    // MARK: - Color Set Management
    
    /// Apply a color set to this chip view
    func apply(colorSet: ChipColorSet) {
        colorSet.apply(to: self)
    }
    
    // MARK: - Initialization
    
    init(value: Int, size: CGFloat = 40, colorSet: ChipColorSet = .yellowGreen) {
        self.value = value
        super.init(frame: .zero)
        setupView(size: size)
        colorSet.apply(to: self)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Update corner radius to maintain circular shape
        let size = min(bounds.width, bounds.height)
        layer.cornerRadius = size / 2
    }
    
    private func setupView(size: CGFloat) {
        backgroundColor = .clear
        
        // Configure label
        valueLabel.text = "\(value)"
        valueLabel.textColor = textColor
        addSubview(valueLabel)
        
        NSLayoutConstraint.activate([
            valueLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
            // Ensure chips maintain square aspect ratio
            widthAnchor.constraint(equalTo: heightAnchor)
        ])
        
        // Make it circular
        layer.cornerRadius = size / 2
        clipsToBounds = false
        
        // Add shadow for overlapping effect (like ChipControl)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 2, height: 2)
        layer.shadowRadius = 4
        layer.shadowOpacity = 0.3
        layer.masksToBounds = false
        
        setupGestures()
    }
    
    private func setupGestures() {
        addTarget(self, action: #selector(touchDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchDragExit, .touchCancel])
        
        // Add pan gesture for dragging
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        // Find the root view (view controller's view) by traversing up the hierarchy
        var rootView: UIView? = self
        while let parent = rootView?.superview {
            rootView = parent
        }
        
        guard let containerView = rootView else { return }
        
        let location = gesture.location(in: containerView)
        
        switch gesture.state {
        case .began:
            // Cancel the scale animation
            layer.removeAllAnimations()
            BetDragManager.shared.startDragging(value: value, from: location, in: containerView)
        case .changed:
            BetDragManager.shared.updateDrag(to: location)
        case .ended:
            BetDragManager.shared.endDrag(at: location, in: containerView)
            // Reset chip appearance
            UIView.animate(withDuration: 0.2) {
                self.transform = .identity
            }
        case .cancelled, .failed:
            BetDragManager.shared.cancelDrag()
            UIView.animate(withDuration: 0.2) {
                self.transform = .identity
            }
        default:
            break
        }
    }
    
    @objc private func touchDown() {
        UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }
    }
    
    @objc private func touchUp() {
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.transform = .identity
        }
    }
    
    // MARK: - Drawing
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        // Always draw in a square rect, centered in the actual rect
        // This prevents stretching of the background circle
        let size = min(rect.width, rect.height)
        let squareRect = CGRect(
            x: rect.midX - size / 2,
            y: rect.midY - size / 2,
            width: size,
            height: size
        )
        
        let center = CGPoint(x: squareRect.midX, y: squareRect.midY)
        let radius = size / 2
        let lineWidth: CGFloat = 4.2
        
        // Draw background circle in square rect to prevent stretching
        context.setFillColor(chipBackgroundColor.cgColor)
        context.fillEllipse(in: squareRect)
        
        // Dash pattern: [8, 8] means 8 points dash, 8 points gap = 16 points total cycle
        let dashLength: CGFloat = 8
        let gapLength: CGFloat = 8
        let cycleLength = dashLength + gapLength // 20 points
        
        // Calculate stroke radius so outer edge aligns with circle edge
        // Arc centerline should be at: radius - (lineWidth / 2)
        // This positions the outer edge of the stroke at the circle's edge
        let strokeRadius = radius - (lineWidth / 2)
        
        // Calculate rotation angle to offset by half a dash cycle
        // For a circle with radius r, circumference = 2πr
        // To offset by half cycle (10 points), rotate by: (dashLength / circumference) * 2π radians
        let circumference = 2 * .pi * strokeRadius
        let offsetAngle = (dashLength / circumference) * 2 * .pi
        
        // Draw ring 1 (first dashed stroke)
        context.saveGState()
        context.setStrokeColor(ring1Color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineDash(phase: 0, lengths: [dashLength, gapLength])
        context.addArc(center: center, radius: strokeRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()
        context.restoreGState()
        
        // Draw ring 2 (second dashed stroke, rotated to fill gaps)
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: offsetAngle) // Rotate by calculated offset angle
        context.translateBy(x: -center.x, y: -center.y)
        context.setStrokeColor(ring2Color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineDash(phase: 0, lengths: [dashLength, gapLength])
        context.addArc(center: center, radius: strokeRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()
        context.restoreGState()
    }
}
