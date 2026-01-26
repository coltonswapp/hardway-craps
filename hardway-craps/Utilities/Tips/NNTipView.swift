//
//  NNTipView.swift
//  hardway-craps
//
//  Created by Colton Swapp on 1/23/26.
//

import UIKit

class NNTipView: UIView {

    // MARK: - Properties
    private let tip: NNTipModel
    private let arrowEdge: TipArrowEdge
    private var dismissHandler: (() -> Void)?
    private var sourceView: UIView?
    private var arrowXConstraint: NSLayoutConstraint?
    private var arrowYConstraint: NSLayoutConstraint?

    // Public property to access the tip ID
    var tipId: String {
        return tip.id
    }

    // MARK: - UI Elements
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = HardwayColors.surfaceGray
        view.layer.cornerRadius = 12
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = HardwayColors.yellow
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        label.textColor = UIColor.label
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        label.textColor = UIColor.secondaryLabel
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    private let dismissButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = UIImage(systemName: "xmark", withConfiguration: config)
        button.setImage(image, for: .normal)
        button.tintColor = UIColor.tertiaryLabel
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    
    private let arrowView: UIView = {
        let view = UIView()
        view.backgroundColor = HardwayColors.surfaceGray
        view.layer.cornerRadius = 3
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Initialization
    init(tip: NNTipModel, arrowEdge: TipArrowEdge = .top, dismissHandler: (() -> Void)? = nil) {
        self.tip = tip
        self.arrowEdge = arrowEdge
        self.dismissHandler = dismissHandler
        super.init(frame: .zero)
        setupUI()
        configureTip()
    }

    // Set the source view for arrow positioning
    func setSourceView(_ sourceView: UIView) {
        self.sourceView = sourceView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    private func setupUI() {
        backgroundColor = UIColor.clear

        // Add arrow first so it's behind the container
        addSubview(arrowView)
        addSubview(containerView)

        containerView.addSubview(iconImageView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(messageLabel)
        containerView.addSubview(dismissButton)

        setupConstraints()
        setupArrow()
        setupDismissButton()
    }
    
    private func setupConstraints() {
        let iconSize: CGFloat = 32
        let padding: CGFloat = 12
        let iconTitleSpacing: CGFloat = 12
        let titleMessageSpacing: CGFloat = 4
        let dismissButtonSize: CGFloat = 24

        NSLayoutConstraint.activate([
            // Container constraints will be set based on arrow position

            // Icon constraints
            iconImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: padding),
            iconImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: padding),
            iconImageView.widthAnchor.constraint(equalToConstant: iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: iconSize),

            // Dismiss button constraints
            dismissButton.topAnchor.constraint(equalTo: containerView.topAnchor, constant: padding),
            dismissButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            dismissButton.widthAnchor.constraint(equalToConstant: dismissButtonSize),
            dismissButton.heightAnchor.constraint(equalToConstant: dismissButtonSize),

            // Title constraints
            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: iconTitleSpacing),
            titleLabel.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: padding),

            // Message constraints
            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: titleMessageSpacing),
            messageLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -padding)
        ])
    }
    
    private func setupArrow() {
        let arrowSize: CGFloat = 12
        let arrowOffset: CGFloat = arrowSize / 2
        
        switch arrowEdge {
        case .top:
            // .top edge = tooltip above source = arrow points down - square rotated 45 degrees, positioned at bottom
            arrowXConstraint = arrowView.centerXAnchor.constraint(equalTo: centerXAnchor)
            NSLayoutConstraint.activate([
                arrowXConstraint!,
                arrowView.centerYAnchor.constraint(equalTo: containerView.bottomAnchor),
                arrowView.widthAnchor.constraint(equalToConstant: arrowSize),
                arrowView.heightAnchor.constraint(equalToConstant: arrowSize),
                
                containerView.topAnchor.constraint(equalTo: topAnchor),
                containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -arrowOffset)
            ])
            arrowView.transform = CGAffineTransform(rotationAngle: .pi / 4)
            
        case .bottom:
            // .bottom edge = tooltip below source = arrow points up - square rotated 45 degrees, positioned at top
            arrowXConstraint = arrowView.centerXAnchor.constraint(equalTo: centerXAnchor)
            NSLayoutConstraint.activate([
                arrowXConstraint!,
                arrowView.centerYAnchor.constraint(equalTo: containerView.topAnchor),
                arrowView.widthAnchor.constraint(equalToConstant: arrowSize),
                arrowView.heightAnchor.constraint(equalToConstant: arrowSize),
                
                containerView.topAnchor.constraint(equalTo: topAnchor, constant: arrowOffset),
                containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                containerView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            arrowView.transform = CGAffineTransform(rotationAngle: .pi / 4)
            
        case .leading:
            // Arrow points left - square rotated 45 degrees, positioned at leading edge
            NSLayoutConstraint.activate([
                arrowView.centerXAnchor.constraint(equalTo: containerView.leadingAnchor),
                arrowView.centerYAnchor.constraint(equalTo: centerYAnchor),
                arrowView.widthAnchor.constraint(equalToConstant: arrowSize),
                arrowView.heightAnchor.constraint(equalToConstant: arrowSize),
                
                containerView.topAnchor.constraint(equalTo: topAnchor),
                containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: arrowOffset),
                containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
                containerView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            arrowView.transform = CGAffineTransform(rotationAngle: .pi / 4)
            
        case .trailing:
            // Arrow points right - square rotated 45 degrees, positioned at trailing edge
            arrowYConstraint = arrowView.centerYAnchor.constraint(equalTo: centerYAnchor)
            NSLayoutConstraint.activate([
                arrowView.centerXAnchor.constraint(equalTo: containerView.trailingAnchor),
                arrowYConstraint!,
                arrowView.widthAnchor.constraint(equalToConstant: arrowSize),
                arrowView.heightAnchor.constraint(equalToConstant: arrowSize),
                
                containerView.topAnchor.constraint(equalTo: topAnchor),
                containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -arrowOffset),
                containerView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            arrowView.transform = CGAffineTransform(rotationAngle: .pi / 4)
        }
    }
    
    
    private func setupDismissButton() {
        dismissButton.addTarget(self, action: #selector(dismissButtonTapped), for: .touchUpInside)
    }
    
    private func configureTip() {
        // Use the tip's properties directly - much cleaner!
        titleLabel.text = tip.title
        
        if let message = tip.message {
            messageLabel.text = message
            messageLabel.isHidden = message.isEmpty
        } else {
            messageLabel.isHidden = true
        }
        
        // Use the system image name directly
        iconImageView.image = UIImage(systemName: tip.systemImageName)
    }
    
    // MARK: - Actions
    @objc private func dismissButtonTapped() {
        // Call dismiss handler (which will handle tip state tracking)
        dismissHandler?()
    }
    
    // MARK: - Public Methods
    func setDismissHandler(_ handler: @escaping () -> Void) {
        self.dismissHandler = handler
    }
    
    // Update arrow position to point to the source view
    func updateArrowPosition() {
        guard let sourceView = sourceView,
              let superview = superview else { return }
        
        // Get the source view's frame in the superview's coordinate system
        let sourceViewFrameInSuperview = sourceView.superview?.convert(sourceView.frame, to: superview) ?? CGRect.zero
        let sourceViewCenterInSuperview = CGPoint(x: sourceViewFrameInSuperview.midX, y: sourceViewFrameInSuperview.midY)
        
        // Get the tooltip's frame in the superview's coordinate system
        let tooltipFrameInSuperview = frame
        
        switch arrowEdge {
        case .top, .bottom:
            guard let arrowXConstraint = arrowXConstraint else { return }
            
            // Calculate offset from tooltip center to source view center
            let tooltipCenterX = tooltipFrameInSuperview.midX
            let offset = sourceViewCenterInSuperview.x - tooltipCenterX
            
            // Clamp the offset to keep arrow within reasonable bounds of the tooltip
            let maxOffset = bounds.width * 0.4 // Don't let arrow go beyond 40% of tooltip width
            let clampedOffset = max(-maxOffset, min(maxOffset, offset))
            
            // Update the constraint
            arrowXConstraint.constant = clampedOffset
            
        case .leading, .trailing:
            guard let arrowYConstraint = arrowYConstraint else { return }
            
            // Calculate offset from tooltip center to source view center
            let tooltipCenterY = tooltipFrameInSuperview.midY
            let offset = sourceViewCenterInSuperview.y - tooltipCenterY
            
            // Clamp the offset to keep arrow within reasonable bounds of the tooltip
            let maxOffset = bounds.height * 0.4 // Don't let arrow go beyond 40% of tooltip height
            let clampedOffset = max(-maxOffset, min(maxOffset, offset))
            
            // Update the constraint
            arrowYConstraint.constant = clampedOffset
        }
    }
    
    func showWithAnimation() {
        // Start with scale 0
        transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        alpha = 0.0
        
        // Animate to full scale
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: [.curveEaseOut]) {
            self.transform = CGAffineTransform.identity
            self.alpha = 1.0
        } completion: { _ in
            // Animation complete
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Arrow is now a simple rotated square - no need to recreate shape
        updateShadowPath()
    }
    
    private func updateShadowPath() {
        // Create a unified shadow path that includes both container and arrow
        let path = UIBezierPath()
        let containerRect = containerView.frame
        let arrowRect = arrowView.frame
        let arrowSize: CGFloat = 12
        
        // Add the container rectangle with rounded corners
        path.append(UIBezierPath(roundedRect: containerRect, cornerRadius: 12))
        
        // Add arrow triangle based on edge
        switch arrowEdge {
        case .top:
            // Arrow pointing down from bottom of container
            let arrowTip = CGPoint(x: arrowRect.midX, y: arrowRect.midY + arrowSize/2)
            let arrowLeft = CGPoint(x: arrowRect.midX - arrowSize/2, y: containerRect.maxY)
            let arrowRight = CGPoint(x: arrowRect.midX + arrowSize/2, y: containerRect.maxY)
            
            path.move(to: arrowLeft)
            path.addLine(to: arrowTip)
            path.addLine(to: arrowRight)
            path.close()
            
        case .bottom:
            // Arrow pointing up from top of container
            let arrowTip = CGPoint(x: arrowRect.midX, y: arrowRect.midY - arrowSize/2)
            let arrowLeft = CGPoint(x: arrowRect.midX - arrowSize/2, y: containerRect.minY)
            let arrowRight = CGPoint(x: arrowRect.midX + arrowSize/2, y: containerRect.minY)
            
            path.move(to: arrowLeft)
            path.addLine(to: arrowTip)
            path.addLine(to: arrowRight)
            path.close()
            
        case .leading:
            // Arrow pointing left from leading edge of container
            let arrowTip = CGPoint(x: arrowRect.midX - arrowSize/2, y: arrowRect.midY)
            let arrowTop = CGPoint(x: containerRect.minX, y: arrowRect.midY - arrowSize/2)
            let arrowBottom = CGPoint(x: containerRect.minX, y: arrowRect.midY + arrowSize/2)
            
            path.move(to: arrowTop)
            path.addLine(to: arrowTip)
            path.addLine(to: arrowBottom)
            path.close()
            
        case .trailing:
            // Arrow pointing right from trailing edge of container
            let arrowTip = CGPoint(x: arrowRect.midX + arrowSize/2, y: arrowRect.midY)
            let arrowTop = CGPoint(x: containerRect.maxX, y: arrowRect.midY - arrowSize/2)
            let arrowBottom = CGPoint(x: containerRect.maxX, y: arrowRect.midY + arrowSize/2)
            
            path.move(to: arrowTop)
            path.addLine(to: arrowTip)
            path.addLine(to: arrowBottom)
            path.close()
        }
        
        // Apply unified shadow to the main view
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
//        layer.shadowOffset = CGSize(width: 2, height: 0)
        layer.shadowRadius = 15
        layer.shadowPath = path.cgPath
    }
}
