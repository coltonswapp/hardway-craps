//
//  LabelShimmerView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class LabelShimmerView: UIView {

    private let targetLabel: UILabel

    private var shimmerLayer: CAGradientLayer!

    init(targetLabel: UILabel) {

        self.targetLabel = targetLabel

        super.init(frame: .zero)

        setupShimmer()

    }

    required init?(coder: NSCoder) {

        fatalError("init(coder:) has not been implemented")

    }

    private func setupShimmer() {

        translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = UIColor.clear

        isUserInteractionEnabled = false

        setupShimmerLayer()

        setupMask()

    }

    private func setupShimmerLayer() {

        shimmerLayer = CAGradientLayer()

        shimmerLayer.colors = [

            UIColor.clear.cgColor,

            UIColor.white.withAlphaComponent(0.4).cgColor,

            UIColor.white.withAlphaComponent(0.4).cgColor,

            UIColor.clear.cgColor

        ]

        shimmerLayer.locations = [0, 0.3, 0.7, 1]

        // 10 degree angle: convert to start/end points

        let angle = 10 * CGFloat.pi / 180

        let startPoint = CGPoint(x: 0.5 - cos(angle) * 0.5, y: 0.5 - sin(angle) * 0.5)

        let endPoint = CGPoint(x: 0.5 + cos(angle) * 0.5, y: 0.5 + sin(angle) * 0.5)

        shimmerLayer.startPoint = startPoint

        shimmerLayer.endPoint = endPoint

        layer.addSublayer(shimmerLayer)

    }

    private func setupMask() {

        let maskLayer = CALayer()

        layer.mask = maskLayer

    }

    override func layoutSubviews() {

        super.layoutSubviews()

        shimmerLayer.frame = bounds

        // Update the mask layer to match the target label's text

        if let maskLayer = layer.mask {

            maskLayer.frame = bounds

            // Create a text layer that matches our target label

            let textLayer = CATextLayer()

            textLayer.string = targetLabel.text

            textLayer.font = targetLabel.font

            textLayer.fontSize = targetLabel.font.pointSize

            textLayer.alignmentMode = CATextLayerAlignmentMode(rawValue: targetLabel.textAlignment.caTextAlignment)

            textLayer.foregroundColor = UIColor.white.cgColor

            textLayer.frame = maskLayer.bounds

            textLayer.contentsScale = UIScreen.main.scale

            maskLayer.sublayers?.removeAll()

            maskLayer.addSublayer(textLayer)

        }

    }

    func startShimmerAnimation() {

        let animation = CABasicAnimation(keyPath: "locations")

        animation.fromValue = [-0.8, -0.6, -0.4, -0.2]

        animation.toValue = [1.2, 1.4, 1.6, 1.8]

        animation.duration = 1.8

        animation.repeatCount = .infinity

        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        shimmerLayer.add(animation, forKey: "shimmer")

    }
    
    func startQuickShimmerAnimation() {
        let animation = CABasicAnimation(keyPath: "locations")
        
        animation.fromValue = [-0.8, -0.6, -0.4, -0.2]
        
        animation.toValue = [1.2, 1.4, 1.6, 1.8]
        
        animation.duration = 0.75
        
        animation.repeatCount = .infinity
        
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        shimmerLayer.add(animation, forKey: "shimmer")
    }

    func stopShimmerAnimation() {

        shimmerLayer.removeAnimation(forKey: "shimmer")

    }

}

// MARK: - UILabel Extension

extension UILabel {

    private static var shimmerViewAssociationKey: UInt8 = 0

    private var shimmerView: LabelShimmerView? {

        get {

            return objc_getAssociatedObject(self, &UILabel.shimmerViewAssociationKey) as? LabelShimmerView

        }

        set {

            objc_setAssociatedObject(self, &UILabel.shimmerViewAssociationKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        }

    }

    func addShimmerEffect() {

        guard shimmerView == nil, let superview = superview else { return }

        let shimmer = LabelShimmerView(targetLabel: self)

        shimmerView = shimmer

        superview.addSubview(shimmer)

        NSLayoutConstraint.activate([

            shimmer.leadingAnchor.constraint(equalTo: leadingAnchor),

            shimmer.trailingAnchor.constraint(equalTo: trailingAnchor),

            shimmer.topAnchor.constraint(equalTo: topAnchor),

            shimmer.bottomAnchor.constraint(equalTo: bottomAnchor)

        ])

        shimmer.startShimmerAnimation()

    }
    
    func addQuickShimmerEffect() {
        guard shimmerView == nil, let superview = superview else { return }
        
        let shimmer = LabelShimmerView(targetLabel: self)
        
        shimmerView = shimmer
        
        superview.addSubview(shimmer)
        
        NSLayoutConstraint.activate([
            shimmer.leadingAnchor.constraint(equalTo: leadingAnchor),
            shimmer.trailingAnchor.constraint(equalTo: trailingAnchor),
            shimmer.topAnchor.constraint(equalTo: topAnchor),
            shimmer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        shimmer.startQuickShimmerAnimation()
    }

    func removeShimmerEffect() {

        shimmerView?.stopShimmerAnimation()

        shimmerView?.removeFromSuperview()

        shimmerView = nil

    }

    func startShimmer() {

        shimmerView?.startShimmerAnimation()

    }
    
    func quickShimmer() {
        shimmerView?.startQuickShimmerAnimation()
    }

    func stopShimmer() {

        shimmerView?.stopShimmerAnimation()

    }

}

// MARK: - Helper Extensions

private extension NSTextAlignment {

    var caTextAlignment: String {

        switch self {

        case .left:

            return CATextLayerAlignmentMode.left.rawValue

        case .center:

            return CATextLayerAlignmentMode.center.rawValue

        case .right:

            return CATextLayerAlignmentMode.right.rawValue

        case .justified:

            return CATextLayerAlignmentMode.justified.rawValue

        case .natural:

            return CATextLayerAlignmentMode.natural.rawValue

        @unknown default:

            return CATextLayerAlignmentMode.natural.rawValue

        }

    }

}

