//
//  InstructionLabel.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/23/25.
//

import UIKit

class InstructionLabel: UIView {

    private let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .left
        label.textColor = HardwayColors.label
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.alpha = 0
        return label
    }()

    private var displayLink: CADisplayLink?
    private var animationStartTime: CFTimeInterval = 0
    private var fullMessage: String = ""
    private var charactersPerSecond: Double = 60.0
    private var fadeOutTimer: Timer?

    init() {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
        fadeOutTimer?.invalidate()
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    func showMessage(_ message: String, shouldFade: Bool = true, duration: TimeInterval = 3.0) {
        // Cancel any existing animation
        displayLink?.invalidate()
        fadeOutTimer?.invalidate()

        fullMessage = message
        
        // Set the full text immediately (with invisible characters) to stabilize layout
        // This prevents line jumping because the layout is calculated with the full text
        updateAttributedText(visibleCharacterCount: 0)
        label.alpha = 1.0

        // Start character-by-character animation
        animationStartTime = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(updateTypewriterAnimation))
        displayLink?.add(to: .main, forMode: .common)

        // Calculate how long the typing will take
        let typingDuration = Double(fullMessage.count) / charactersPerSecond

        if shouldFade {
            // Schedule fade out after typing completes + hold duration
            fadeOutTimer = Timer.scheduledTimer(withTimeInterval: typingDuration + duration, repeats: false) { [weak self] _ in
                self?.fadeOut()
            }
        }
    }

    private func fadeOut() {
        displayLink?.invalidate()

        // Fade out animation
        animationStartTime = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(updateFadeOutAnimation))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func updateTypewriterAnimation() {
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - animationStartTime

        // Calculate how many characters should be visible
        let targetCharacterCount = Int(elapsed * charactersPerSecond)

        if targetCharacterCount >= fullMessage.count {
            // Typing complete - show full text normally
            label.text = fullMessage
            label.textColor = HardwayColors.label
            displayLink?.invalidate()
            displayLink = nil
        } else {
            // Update attributed text to reveal characters progressively
            updateAttributedText(visibleCharacterCount: targetCharacterCount)
        }
    }
    
    private func updateAttributedText(visibleCharacterCount: Int) {
        let attributedString = NSMutableAttributedString(string: fullMessage)
        let textColor = HardwayColors.label
        
        // Set attributes for the entire string
        attributedString.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: fullMessage.count))
        attributedString.addAttribute(.font, value: label.font ?? .systemFont(ofSize: 14, weight: .medium), range: NSRange(location: 0, length: fullMessage.count))
        
        // Make characters beyond visibleCharacterCount transparent
        if visibleCharacterCount < fullMessage.count {
            let invisibleRange = NSRange(location: visibleCharacterCount, length: fullMessage.count - visibleCharacterCount)
            attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: invisibleRange)
        }
        
        label.attributedText = attributedString
    }

    @objc private func updateFadeOutAnimation() {
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - animationStartTime
        let duration: CFTimeInterval = 0.8

        if elapsed >= duration {
            // Fade complete
            label.alpha = 0.0
            displayLink?.invalidate()
            displayLink = nil
        } else {
            // Calculate fade progress
            let progress = elapsed / duration
            let easedProgress = easeOutQuad(progress)
            label.alpha = 1.0 - easedProgress
        }
    }

    private func easeOutQuad(_ t: Double) -> Double {
        return t * (2.0 - t)
    }
}
