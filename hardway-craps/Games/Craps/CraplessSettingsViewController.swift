//
//  CraplessSettingsViewController.swift
//  hardway-craps
//

import UIKit

final class CraplessSettingsViewController: BaseSettingsViewController {

    private enum SettingsKeys {
        static let hardwaysEnabled = "CraplessHardwaysEnabled"
        static let makeEmEnabled = "CraplessMakeEmEnabled"
        static let hornEnabled = "CraplessHornEnabled"
    }

    private static let speedSteps: [(label: String, multiplier: Double)] = [
        ("Slow", 2.0),
        ("Relaxed", 1.33),
        ("Normal", 1.0),
        ("Fast", 0.67),
        ("Turbo", 0.5)
    ]

    private var hardwaysEnabled: Bool = true
    private var makeEmEnabled: Bool = true
    private var hornEnabled: Bool = true

    var onFixedRoll: ((Int) -> Void)?

    var autoplayInitiallyEnabled: Bool = false
    var onAutoplayChanged: ((Bool) -> Void)?

    override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSettings()
    }

    override func setupViewController() {
        super.setupViewController()
        title = "Crapless Settings"
    }

    private func loadSettings() {
        if UserDefaults.standard.object(forKey: SettingsKeys.hardwaysEnabled) != nil {
            hardwaysEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.hardwaysEnabled)
        }
        if UserDefaults.standard.object(forKey: SettingsKeys.makeEmEnabled) != nil {
            makeEmEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.makeEmEnabled)
        }
        if UserDefaults.standard.object(forKey: SettingsKeys.hornEnabled) != nil {
            hornEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.hornEnabled)
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(hardwaysEnabled, forKey: SettingsKeys.hardwaysEnabled)
        UserDefaults.standard.set(makeEmEnabled, forKey: SettingsKeys.makeEmEnabled)
        UserDefaults.standard.set(hornEnabled, forKey: SettingsKeys.hornEnabled)
        onSettingsChanged?()
    }

    // MARK: - Table View Data Source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 2  // Game Details + Hit the ATM
        case 1: return 5  // Autoplay + Game Speed + bonus bets
        case 2: return 7  // Explainer (no Variant or Don't Pass rows)
        case 3: return 2  // Testing
        default: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return nil
        case 1: return "Game"
        case 2: return "Crapless Craps Explainer"
        case 3: return "Testing"
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)

        cell.textLabel?.textColor = .white
        cell.selectionStyle = .none
        cell.accessoryType = .none
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }

        switch indexPath.section {
        case 0:
            switch indexPath.row {
            case 0:
                configureActionCell(cell, title: "Game Details", icon: "chart.line.uptrend.xyaxis") { [weak self] in
                    self?.dismiss(animated: true) {
                        self?.onShowGameDetails?()
                    }
                }
            case 1:
                configureATMCell(cell) { [weak self] amount in
                    self?.onHitATM?(amount)
                }
            default: break
            }
        case 1:
            switch indexPath.row {
            case 0:
                configureSwitchCell(cell, title: "Autoplay", isOn: autoplayInitiallyEnabled) { [weak self] isOn in
                    self?.onAutoplayChanged?(isOn)
                }
            case 1:
                configureGameSpeedCell(cell)
            case 2:
                configureSwitchCell(cell, title: "Hardways", isOn: hardwaysEnabled) { [weak self] isOn in
                    self?.hardwaysEnabled = isOn
                    self?.saveSettings()
                }
            case 3:
                configureSwitchCell(cell, title: "Make Em'", isOn: makeEmEnabled) { [weak self] isOn in
                    self?.makeEmEnabled = isOn
                    self?.saveSettings()
                }
            case 4:
                configureSwitchCell(cell, title: "Horn", isOn: hornEnabled) { [weak self] isOn in
                    self?.hornEnabled = isOn
                    self?.saveSettings()
                }
            default: break
            }
        case 2:
            configureExplainerCell(cell, at: indexPath.row)
        case 3:
            switch indexPath.row {
            case 0:
                configureSwitchCell(cell, title: "No Sevens", isOn: CrapsDebugSettings.isNoSevensEnabled) { isOn in
                    CrapsDebugSettings.isNoSevensEnabled = isOn
                }
            case 1:
                configureFixedRollCell(cell) { [weak self] total in
                    self?.dismiss(animated: true) {
                        self?.onFixedRoll?(total)
                    }
                }
            default: break
            }
        default: break
        }

        return cell
    }

    private func configureGameSpeedCell(_ cell: UITableViewCell) {
        let label = createStandardLabel(text: "Game Speed")

        let currentMultiplier = CrapsAnimationTiming.speedMultiplier
        let currentIndex = Self.speedSteps.enumerated().min(by: {
            abs($0.element.multiplier - currentMultiplier) < abs($1.element.multiplier - currentMultiplier)
        })?.offset ?? 2

        let valueLabel = UILabel()
        valueLabel.text = Self.speedSteps[currentIndex].label
        valueLabel.textColor = .white.withAlphaComponent(0.6)
        valueLabel.font = .systemFont(ofSize: 15)
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = Float(Self.speedSteps.count - 1)
        slider.value = Float(currentIndex)
        slider.translatesAutoresizingMaskIntoConstraints = false

        var trackConfig = UISlider.TrackConfiguration(numberOfTicks: Self.speedSteps.count)
        trackConfig.allowsTickValuesOnly = true
        slider.trackConfiguration = trackConfig

        slider.addAction(UIAction { [weak self] action in
            guard let self, let slider = action.sender as? UISlider else { return }
            let stepIndex = Int(slider.value.rounded())
            let step = Self.speedSteps[stepIndex]
            valueLabel.text = step.label
            CrapsAnimationTiming.setSpeed(step.multiplier)
        }, for: .valueChanged)

        cell.contentView.addSubview(label)
        cell.contentView.addSubview(valueLabel)
        cell.contentView.addSubview(slider)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),

            valueLabel.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            valueLabel.centerYAnchor.constraint(equalTo: label.centerYAnchor),

            slider.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            slider.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            slider.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            slider.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
        ])
    }

    private func configureFixedRollCell(_ cell: UITableViewCell, onSelection: @escaping (Int) -> Void) {
        let label = createStandardLabel(text: "Fixed Roll", color: HardwayColors.label)
        let menuItems = (2...12).map { total in
            UIAction(title: "\(total)") { _ in onSelection(total) }
        }
        let menu = UIMenu(title: "", children: menuItems)
        let button = createMenuButton(title: "Select Roll", menu: menu)
        layoutLabelAndButton(label: label, button: button, in: cell)
    }

    private func configureExplainerCell(_ cell: UITableViewCell, at row: Int) {
        let explainerItems: [(title: String, subtitle: String)] = [
            ("Pass Line", "Wins on 7 on the come-out roll. All other totals (2, 3, 4, 5, 6, 8, 9, 10, 11, 12) establish a point. Roll the point again before a 7 to win."),
            ("Come Out Roll", "The first roll of a new round. Only 7 wins. Every other total becomes the point."),
            ("Point", "When a point is established (any total except 7), you must roll that number again before rolling a 7 to win your pass line bet. The puck shows OFF when no point is set, and ON with the point number displayed."),
            ("Field", "A one-time bet that wins on 2, 3, 4, 9, 10, 11, or 12. Loses on 5, 6, 7, or 8. Pays double on 2, triple on 12."),
            ("Pass Line Odds", "An additional bet placed behind your pass line bet after a point is established. Pays true odds with no house edge."),
            ("Hardways & Horn", "Hardways are pairs: hard 4 (2-2), hard 6 (3-3), hard 8 (4-4), hard 10 (5-5). Hardway bets stay active until the soft number is rolled or a 7. Horn is a one-time bet on 2, 3, 11, or 12."),
            ("Make Em'", "Bet that ALL numbers in either the small (2, 3, 4, 5, 6) or tall (8, 9, 10, 11, 12) will be rolled before a 7. Also known as 'All Small' or 'All Tall'.")
        ]

        guard row < explainerItems.count else { return }

        let item = explainerItems[row]
        let titleLabel = createStandardLabel(text: item.title)
        let subtitleLabel = createSecondaryLabel(text: item.subtitle)
        subtitleLabel.numberOfLines = 0

        cell.contentView.addSubview(titleLabel)
        cell.contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),

            subtitleLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            subtitleLabel.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)
        ])
    }

    // MARK: - Table View Delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 0 && indexPath.row == 0 {
            dismiss(animated: true) { [weak self] in
                self?.onShowGameDetails?()
            }
        }
    }
}
