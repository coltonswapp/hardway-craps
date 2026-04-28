//
//  MainViewController.swift
//  hardway-craps
//
//  Created by Colton Swapp on 12/22/25.
//

import UIKit

class MainViewController: UIViewController {

  // MARK: - Game Definitions

  private enum GameType {
    case craps
    case craplessCraps
    case blackjack
    case baccarat
  }

  private struct GamePage {
    let title: String
    let type: GameType
  }

  private let gamePages: [GamePage] = [
    GamePage(title: "Craps", type: .craps),
    GamePage(title: "Crapless", type: .craplessCraps),
    GamePage(title: "Blackjack", type: .blackjack),
    GamePage(title: "Baccarat", type: .baccarat),
  ]

  // MARK: - UI Components

  private lazy var tabBar = GameCategoryTabBar(titles: gamePages.map(\.title))
  private let pagingScrollView = HorizontalPagingScrollView()
  private let pagesContainer = UIView()

  private var pageTableViews: [UITableView] = []
  private var pageSessions: [[GameSession]] = []
  private var pageCtaContainers: [UIView] = []
  private var pageBlurViews: [UIVisualEffectView] = []
  private var tabBarBlurView: UIVisualEffectView?

  private var isUpdatingFromScroll = false
  private var hasSetInitialInsets = false

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    title = "Game Sessions"

    pageSessions = gamePages.map { _ in [] }

    setupNavigationBar()
    setupPagingScrollView()
    setupTabBarWithBlur()
    setupPages()
    loadSessions()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    loadSessions()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let width = pagingScrollView.bounds.width
    guard width > 0 else { return }
    pagingScrollView.contentSize = CGSize(
      width: width * CGFloat(gamePages.count),
      height: pagingScrollView.bounds.height
    )
    for (i, _) in gamePages.enumerated() {
      let pageView = pagesContainer.subviews[i]
      pageView.frame = CGRect(
        x: width * CGFloat(i),
        y: 0,
        width: width,
        height: pagingScrollView.bounds.height
      )
    }
    updateTableViewInsets()
  }

  // MARK: - Navigation Bar

  private func setupNavigationBar() {
    let settingsButton = UIBarButtonItem(
      image: UIImage(systemName: "gearshape"),
      style: .plain,
      target: self,
      action: #selector(showSettings)
    )
    navigationItem.rightBarButtonItem = settingsButton
  }

  @objc private func showSettings() {
    let settingsVC = AppSettingsViewController()
    let navController = UINavigationController(rootViewController: settingsVC)
    present(navController, animated: true)
  }

  // MARK: - Tab Bar

  private func setupTabBarWithBlur() {
    tabBarBlurView = UIVisualEffectView()
    if let maskImage = UIImage(named: "testBG3"),
      let flipped = flipImageVertically(maskImage)
    {
      tabBarBlurView?.effect = UIBlurEffect.variableBlurEffect(radius: 16, maskImage: flipped)
    }
    tabBarBlurView?.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(tabBarBlurView!)

    tabBar.delegate = self
    view.addSubview(tabBar)

    NSLayoutConstraint.activate([
      tabBarBlurView!.topAnchor.constraint(equalTo: view.topAnchor),
      tabBarBlurView!.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tabBarBlurView!.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tabBarBlurView!.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),

      tabBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
  }

  private func flipImageVertically(_ image: UIImage) -> UIImage? {
    guard let cgImage = image.cgImage else { return nil }
    return UIImage(cgImage: cgImage, scale: image.scale, orientation: .downMirrored)
  }

  // MARK: - Paging Scroll View

  private func setupPagingScrollView() {
    pagingScrollView.translatesAutoresizingMaskIntoConstraints = false
    pagingScrollView.delegate = self
    pagingScrollView.backgroundColor = .clear
    view.addSubview(pagingScrollView)

    pagesContainer.translatesAutoresizingMaskIntoConstraints = false
    pagingScrollView.addSubview(pagesContainer)

    NSLayoutConstraint.activate([
      pagingScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      pagingScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      pagingScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      pagingScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      pagesContainer.topAnchor.constraint(equalTo: pagingScrollView.topAnchor),
      pagesContainer.leadingAnchor.constraint(equalTo: pagingScrollView.leadingAnchor),
      pagesContainer.heightAnchor.constraint(equalTo: pagingScrollView.heightAnchor),
      pagesContainer.widthAnchor.constraint(
        equalTo: pagingScrollView.widthAnchor, multiplier: CGFloat(gamePages.count)),
    ])
  }

  // MARK: - Page Setup

  private func setupPages() {
    for (index, page) in gamePages.enumerated() {
      let pageView = UIView()
      pageView.backgroundColor = .clear
      pagesContainer.addSubview(pageView)

      let tableView = createTableView(tag: index)
      pageView.addSubview(tableView)
      pageTableViews.append(tableView)

      NSLayoutConstraint.activate([
        tableView.topAnchor.constraint(equalTo: pageView.topAnchor),
        tableView.leadingAnchor.constraint(equalTo: pageView.leadingAnchor),
        tableView.trailingAnchor.constraint(equalTo: pageView.trailingAnchor),
        tableView.bottomAnchor.constraint(equalTo: pageView.bottomAnchor),
      ])

      let (ctaContainer, blurView) = createCtaArea(for: page, in: pageView)
      pageCtaContainers.append(ctaContainer)
      pageBlurViews.append(blurView)
    }
  }

  private func createTableView(tag: Int) -> UITableView {
    let tv = UITableView(frame: .zero, style: .plain)
    tv.translatesAutoresizingMaskIntoConstraints = false
    tv.backgroundColor = .black
    tv.separatorColor = .darkGray
    tv.delegate = self
    tv.dataSource = self
    tv.tag = tag
    tv.register(SessionTableViewCell.self, forCellReuseIdentifier: "SessionCell")
    return tv
  }

  private func createCtaArea(for page: GamePage, in pageView: UIView) -> (
    UIView, UIVisualEffectView
  ) {
    let blurView = UIVisualEffectView()
    if let maskImage = UIImage(named: "testBG3") {
      blurView.effect = UIBlurEffect.variableBlurEffect(radius: 16, maskImage: maskImage)
    }
    blurView.translatesAutoresizingMaskIntoConstraints = false
    pageView.addSubview(blurView)

    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    container.backgroundColor = .clear
    pageView.addSubview(container)

    let stack = UIStackView()
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.alignment = .fill
    stack.distribution = .fillEqually
    stack.spacing = 12
    container.addSubview(stack)

    switch page.type {
    case .blackjack:
      let soloButton = NNPrimaryLabeledButton(title: "Solo")
      soloButton.addTarget(self, action: #selector(blackjackSoloTapped), for: .touchUpInside)

      let multiButton = NNPrimaryLabeledButton(title: "Multiplayer")
      multiButton.addTarget(
        self, action: #selector(blackjackMultiplayerTapped), for: .touchUpInside)

      let horizontalStack = UIStackView(arrangedSubviews: [soloButton, multiButton])
      horizontalStack.axis = .horizontal
      horizontalStack.alignment = .fill
      horizontalStack.distribution = .fillEqually
      horizontalStack.spacing = 12

      stack.addArrangedSubview(horizontalStack)

      horizontalStack.heightAnchor.constraint(equalToConstant: 55).isActive = true

    case .baccarat:
      let newGameButton = NNPrimaryLabeledButton(title: "New Game")
      newGameButton.addTarget(self, action: #selector(baccaratNewGameTapped), for: .touchUpInside)
      stack.addArrangedSubview(newGameButton)
      newGameButton.heightAnchor.constraint(equalToConstant: 55).isActive = true

    case .craps:
      let newGameButton = NNPrimaryLabeledButton(title: "New Game")
      newGameButton.addTarget(self, action: #selector(crapsNewGameTapped), for: .touchUpInside)
      stack.addArrangedSubview(newGameButton)
      newGameButton.heightAnchor.constraint(equalToConstant: 55).isActive = true

    case .craplessCraps:
      let newGameButton = NNPrimaryLabeledButton(title: "New Game")
      newGameButton.addTarget(
        self, action: #selector(craplessCrapsNewGameTapped), for: .touchUpInside)
      stack.addArrangedSubview(newGameButton)
      newGameButton.heightAnchor.constraint(equalToConstant: 55).isActive = true
    }

    NSLayoutConstraint.activate([
      blurView.leadingAnchor.constraint(equalTo: pageView.leadingAnchor),
      blurView.trailingAnchor.constraint(equalTo: pageView.trailingAnchor),
      blurView.topAnchor.constraint(equalTo: container.topAnchor),
      blurView.bottomAnchor.constraint(equalTo: pageView.bottomAnchor),

      container.leadingAnchor.constraint(equalTo: pageView.leadingAnchor),
      container.trailingAnchor.constraint(equalTo: pageView.trailingAnchor),
      container.bottomAnchor.constraint(equalTo: pageView.bottomAnchor),

      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
      stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
    ])

    return (container, blurView)
  }

  private func updateTableViewInsets() {
    let tabBarHeight = tabBar.bounds.height
    for (i, container) in pageCtaContainers.enumerated() {
      container.layoutIfNeeded()
      let ctaHeight = container.bounds.height
      guard ctaHeight > 0 else { continue }
      pageTableViews[i].contentInset = UIEdgeInsets(
        top: tabBarHeight,
        left: 0,
        bottom: ctaHeight + 20,
        right: 0
      )
      pageTableViews[i].verticalScrollIndicatorInsets = UIEdgeInsets(
        top: tabBarHeight,
        left: 0,
        bottom: ctaHeight - 20,
        right: 0
      )
    }
    if !hasSetInitialInsets, tabBarHeight > 0 {
      hasSetInitialInsets = true
      for tv in pageTableViews {
        tv.contentOffset.y = -tabBarHeight
      }
    }
  }

  // MARK: - Actions

  @objc private func crapsNewGameTapped() {
    let gameplayVC = CrapsGameplayViewController()
    navigationController?.pushViewController(gameplayVC, animated: true)
  }

  @objc private func craplessCrapsNewGameTapped() {
    let gameplayVC = CrapsGameplayViewController(variant: .crapless)
    navigationController?.pushViewController(gameplayVC, animated: true)
  }

  @objc private func blackjackSoloTapped() {
    let vc = BlackjackGameplayViewController()
    navigationController?.pushViewController(vc, animated: true)
  }

  @objc private func blackjackMultiplayerTapped() {
    let vc = MPBlackjackLobbyViewController()
    navigationController?.pushViewController(vc, animated: true)
  }

  @objc private func baccaratNewGameTapped() {
    let gameplayVC = BaccaratGameplayViewController()
    navigationController?.pushViewController(gameplayVC, animated: true)
  }

  // MARK: - Data Loading

  private func loadSessions() {
    let allSessions = SessionPersistenceManager.shared.loadAllSessions()
    for (i, page) in gamePages.enumerated() {
      switch page.type {
      case .blackjack:
        pageSessions[i] = allSessions.filter { $0.isBlackjackSession }
      case .craps:
        pageSessions[i] = allSessions.filter {
          $0.isCrapsSession
            || (!$0.isBlackjackSession && !$0.isBaccaratSession && !$0.isCraplessCrapsSession)
        }
      case .craplessCraps:
        pageSessions[i] = allSessions.filter { $0.isCraplessCrapsSession }
      case .baccarat:
        pageSessions[i] = allSessions.filter { $0.isBaccaratSession }
      }
      pageTableViews[i].reloadData()
    }
  }
}

// MARK: - GameCategoryTabBarDelegate

extension MainViewController: GameCategoryTabBarDelegate {
  func tabBar(_ tabBar: GameCategoryTabBar, didSelectTabAt index: Int) {
    let offsetX = pagingScrollView.bounds.width * CGFloat(index)
    isUpdatingFromScroll = true
    pagingScrollView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: true)
  }

  func tabBar(_ tabBar: GameCategoryTabBar, didScrollToPageProgress progress: CGFloat) {
    let width = pagingScrollView.bounds.width
    guard width > 0 else { return }
    let offsetX = progress * width
    isUpdatingFromScroll = true
    pagingScrollView.contentOffset.x = offsetX
  }

  func tabBarDidEndScrolling(_ tabBar: GameCategoryTabBar) {
    isUpdatingFromScroll = false
  }
}

// MARK: - UIScrollViewDelegate

extension MainViewController: UIScrollViewDelegate {
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard scrollView === pagingScrollView else { return }
    let width = scrollView.bounds.width
    guard width > 0 else { return }
    let progress = scrollView.contentOffset.x / width
    if !isUpdatingFromScroll {
      tabBar.setPageProgress(progress, animated: false)
    }
  }

  func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
    if scrollView === pagingScrollView {
      isUpdatingFromScroll = false
    }
  }

  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    if scrollView === pagingScrollView {
      isUpdatingFromScroll = false
    }
  }
}

// MARK: - UITableViewDataSource

extension MainViewController: UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    let pageIndex = tableView.tag
    return pageSessions[pageIndex].count
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell =
      tableView.dequeueReusableCell(withIdentifier: "SessionCell", for: indexPath)
      as! SessionTableViewCell
    let pageIndex = tableView.tag
    cell.configure(with: pageSessions[pageIndex][indexPath.row])
    return cell
  }
}

// MARK: - UITableViewDelegate

extension MainViewController: UITableViewDelegate {
  func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    return 80
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let pageIndex = tableView.tag
    let session = pageSessions[pageIndex][indexPath.row]
    let detailViewController = GameDetailViewController(session: session, canContinueSession: true)

    detailViewController.onContinueSession = { [weak self] in
      guard let self = self,
        let navController = self.navigationController
      else { return }

      let gameplayVC: UIViewController
      if session.isBlackjackSession {
        gameplayVC = BlackjackGameplayViewController(resumingSession: session)
      } else if session.isBaccaratSession {
        gameplayVC = BaccaratGameplayViewController(resumingSession: session)
      } else if session.isCraplessCrapsSession {
        gameplayVC = CrapsGameplayViewController(variant: .crapless, resumingSession: session)
      } else {
        gameplayVC = CrapsGameplayViewController(resumingSession: session)
      }

      navController.popViewController(animated: false)
      navController.pushViewController(gameplayVC, animated: true)
    }

    navigationController?.pushViewController(detailViewController, animated: true)
  }
}

// MARK: - Horizontal Paging Scroll View

/// A paging scroll view that only claims the gesture when it is clearly
/// horizontal. This prevents the underlying table views from bouncing or
/// scrolling vertically when the user begins a horizontal swipe between pages.
final class HorizontalPagingScrollView: UIScrollView {

  override init(frame: CGRect) {
    super.init(frame: frame)
    commonInit()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    commonInit()
  }

  private func commonInit() {
    isPagingEnabled = true
    showsHorizontalScrollIndicator = false
    showsVerticalScrollIndicator = false
    alwaysBounceVertical = false
    alwaysBounceHorizontal = true
    bounces = true
    contentInsetAdjustmentBehavior = .never
  }

  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
      pan === panGestureRecognizer
    else {
      return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
    let translation = pan.translation(in: self)
    // Require the gesture to be predominantly horizontal before claiming it.
    // Vertical and ambiguous gestures fall through to the table view's pan.
    return abs(translation.x) > abs(translation.y)
  }
}

// MARK: - Session Table View Cell

class SessionTableViewCell: UITableViewCell {

  private let gameTypeLabel = UILabel()
  private let dateLabel = UILabel()
  private let durationLabel = UILabel()
  private let playerTypeLabel = UILabel()
  private let resultLabel = UILabel()
  private let netResultLabel = UILabel()
  private let stackView = UIStackView()
  private let rightStackView = UIStackView()

  override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
    super.init(style: style, reuseIdentifier: reuseIdentifier)
    setupCell()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupCell() {
    backgroundColor = .black
    contentView.backgroundColor = .black
    selectionStyle = .none

    gameTypeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
    gameTypeLabel.textColor = HardwayColors.yellow
    gameTypeLabel.numberOfLines = 1

    dateLabel.font = .systemFont(ofSize: 12, weight: .regular)
    dateLabel.textColor = .lightGray
    dateLabel.numberOfLines = 1

    durationLabel.font = .systemFont(ofSize: 16, weight: .medium)
    durationLabel.textColor = .white
    durationLabel.numberOfLines = 1

    resultLabel.font = .systemFont(ofSize: 16, weight: .medium)
    resultLabel.textAlignment = .right

    netResultLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    netResultLabel.textAlignment = .right

    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .vertical
    stackView.distribution = .fill
    stackView.spacing = 4
    stackView.alignment = .leading
    stackView.addArrangedSubview(gameTypeLabel)
    stackView.addArrangedSubview(dateLabel)
    stackView.addArrangedSubview(durationLabel)

    rightStackView.translatesAutoresizingMaskIntoConstraints = false
    rightStackView.axis = .vertical
    rightStackView.distribution = .fill
    rightStackView.spacing = 2
    rightStackView.alignment = .trailing
    rightStackView.addArrangedSubview(resultLabel)
    rightStackView.addArrangedSubview(netResultLabel)

    contentView.addSubview(stackView)
    contentView.addSubview(rightStackView)

    NSLayoutConstraint.activate([
      stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      stackView.trailingAnchor.constraint(
        lessThanOrEqualTo: rightStackView.leadingAnchor, constant: -16),

      rightStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
      rightStackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      rightStackView.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
    ])
  }

  func configure(with session: GameSession) {
    // Distinguish between game types
    if session.isBlackjackSession {
      gameTypeLabel.text = session.isMultiplayerSession ? "MULTIPLAYER BLACKJACK" : "SOLO BLACKJACK"
    } else if session.isBaccaratSession {
      gameTypeLabel.text = "BACCARAT"
    } else {
      if session.isCrapsSession {
        gameTypeLabel.text = "CRAPS"
      } else {
        gameTypeLabel.text = "CRAPLESS"
      }
    }

    dateLabel.text = session.formattedDate
    let durationPart = session.formattedDurationWithRolls
    let playerType = session.playerType

    durationLabel.text = "\(durationPart), \(playerType.rawValue)"

    let startingBalance = session.startingBalance
    let endingBalance = session.endingBalance
    resultLabel.text = "$\(startingBalance) → $\(endingBalance)"

    let net = session.trueNetResult
    if net > 0 {
      resultLabel.textColor = .systemGreen
    } else if net < 0 {
      resultLabel.textColor = .systemRed
    } else {
      resultLabel.textColor = .white
    }
    resultLabel.backgroundColor = .clear

    if session.totalATMAmount > 0 {
      let sign = net >= 0 ? "+" : "-"
      netResultLabel.text = "Net: \(sign)$\(abs(net))"
      netResultLabel.textColor = net > 0 ? .systemGreen : net < 0 ? .systemRed : .white
      netResultLabel.isHidden = false
    } else {
      netResultLabel.text = nil
      netResultLabel.isHidden = true
    }

    gameTypeLabel.isHidden = false
    dateLabel.isHidden = false
    durationLabel.isHidden = false
    resultLabel.isHidden = false
  }
}
