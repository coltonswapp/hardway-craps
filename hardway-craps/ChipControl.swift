//
//  ChipControl.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class ChipControl: UIControl {

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
//        iv.backgroundColor = .red.withAlphaComponent(0.5)
        return iv
    }()

    let value: Int

    init(value: Int) {
        self.value = value
        super.init(frame: .zero)
        setupView()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 60),
            imageView.heightAnchor.constraint(equalToConstant: 60)
        ])

        imageView.image = UIImage(named: "hardway-chip-\(value)")
        
        // Add shadow for overlapping effect
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 2, height: 2)
        layer.shadowRadius = 4
        layer.shadowOpacity = 0.3
        layer.masksToBounds = false
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
}
