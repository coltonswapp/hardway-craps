//
//  GameCategoryTabBar.swift
//  hardway-craps
//
//  Created by Colton Swapp on 3/6/26.
//

import UIKit

protocol GameCategoryTabBarDelegate: AnyObject {
  func tabBar(_ tabBar: GameCategoryTabBar, didSelectTabAt index: Int)
  /// Called as the user scrolls the tab bar; progress is the continuous page index (0...count-1).
  func tabBar(_ tabBar: GameCategoryTabBar, didScrollToPageProgress progress: CGFloat)
  /// Called when the user finishes scrolling the tab bar (finger up, deceleration ended).
  func tabBarDidEndScrolling(_ tabBar: GameCategoryTabBar)
}

class GameCategoryTabBar: UIView {

  weak var delegate: GameCategoryTabBarDelegate?

  private(set) var selectedIndex: Int = 0
  private var titles: [String] = []
  /// When true, we're updating contentOffset from setPageProgress; don't report back to delegate.
  private var isProgrammaticScroll = false
  /// When true, `selectedIndex` and pill styling are driven only by explicit selection APIs — not by
  /// `scrollViewDidScroll`. Prevents intermediate scroll positions during `scrollToItem` animations from
  /// briefly selecting the wrong tab (visible flashing).
  private var suspendSelectionSyncFromScroll = false

  private lazy var collectionView: UICollectionView = {
    let layout = UICollectionViewFlowLayout()
    layout.scrollDirection = .horizontal
    layout.minimumInteritemSpacing = 8
    let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
    cv.translatesAutoresizingMaskIntoConstraints = false
    cv.backgroundColor = .clear
    cv.showsHorizontalScrollIndicator = false
    cv.isScrollEnabled = true
    cv.delegate = self
    cv.dataSource = self
    cv.register(TabCell.self, forCellWithReuseIdentifier: TabCell.reuseID)
    return cv
  }()

  init(titles: [String]) {
    self.titles = titles
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    addSubview(collectionView)
    NSLayoutConstraint.activate([
      collectionView.topAnchor.constraint(equalTo: topAnchor),
      collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
      collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
      heightAnchor.constraint(equalToConstant: 44),
    ])
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // Center the selected tab after layout
    if collectionView.numberOfItems(inSection: 0) > 0 {
      collectionView.scrollToItem(
        at: IndexPath(item: selectedIndex, section: 0),
        at: .centeredHorizontally,
        animated: false
      )
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func selectTab(at index: Int, animated: Bool) {
    guard index >= 0, index < titles.count, index != selectedIndex else { return }
    let previousIndex = selectedIndex
    selectedIndex = index

    HapticsHelper.lightHaptic()

    let duration: TimeInterval = animated ? 0.25 : 0
    UIView.animate(withDuration: duration, delay: 0, options: .curveEaseInOut) {
      if let prev = self.collectionView.cellForItem(at: IndexPath(item: previousIndex, section: 0))
        as? TabCell
      {
        prev.setSelected(false)
      }
      if let curr = self.collectionView.cellForItem(at: IndexPath(item: index, section: 0))
        as? TabCell
      {
        curr.setSelected(true)
      }
    }

    // Scroll to center the selected tab
    if animated {
      suspendSelectionSyncFromScroll = true
    }
    collectionView.scrollToItem(
      at: IndexPath(item: index, section: 0),
      at: .centeredHorizontally,
      animated: animated
    )
    if !animated {
      suspendSelectionSyncFromScroll = false
    }
  }

  /// Sync tab bar scroll position to a continuous page progress (0...titles.count-1). Used when the underlying page view is scrolled.
  func setPageProgress(_ progress: CGFloat, animated: Bool) {
    guard titles.count > 0, let range = contentOffsetRangeX() else { return }
    let clamped = max(0, min(progress, CGFloat(titles.count - 1)))
    let centerX = centerXInContent(forPageProgress: clamped)
    let cv = collectionView
    let offsetX = centerX - cv.bounds.width / 2
    let clampedOffset = min(max(range.min, offsetX), range.max)
    isProgrammaticScroll = true
    let offsetChanged = abs(cv.contentOffset.x - clampedOffset) > 0.5
    let actuallyAnimate = animated && offsetChanged
    cv.setContentOffset(CGPoint(x: clampedOffset, y: 0), animated: actuallyAnimate)
    if !actuallyAnimate {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.isProgrammaticScroll = false
        self.suspendSelectionSyncFromScroll = false
      }
    }
  }

  /// Content-space X coordinate of the center of the given page progress (0...count-1).
  /// Uses same inset as layout: first cell centered at bounds.width/2 when offset=0.
  private func centerXInContent(forPageProgress progress: CGFloat) -> CGFloat {
    let count = titles.count
    guard count > 0 else { return 0 }
    let widths = titles.map { cellWidth(for: $0) }
    let leftInset = collectionView.bounds.width / 2 - widths[0] / 2
    let spacing: CGFloat = 8
    func centerOfItem(_ i: Int) -> CGFloat {
      var x = leftInset
      for j in 0..<i { x += widths[j] + spacing }
      return x + widths[i] / 2
    }
    let idx = min(Int(progress), count - 1)
    let t = progress - CGFloat(idx)
    if idx >= count - 1 || t <= 0 {
      return centerOfItem(idx)
    }
    let c0 = centerOfItem(idx)
    let c1 = centerOfItem(idx + 1)
    return c0 + t * (c1 - c0)
  }

  private func cellWidth(for title: String) -> CGFloat {
    let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
    return (title as NSString).size(withAttributes: [.font: font]).width + 32
  }

  /// Content offset X range: with our insets, 0 = first tab centered, max = last tab centered. Bounce happens past 0 and max.
  private func contentOffsetRangeX() -> (min: CGFloat, max: CGFloat)? {
    let cv = collectionView
    guard titles.count > 0, cv.bounds.width > 0 else { return nil }
    let maxOffset = max(0, cv.contentSize.width - cv.bounds.width)
    return (0, maxOffset)
  }

  /// When user stops scrolling the tab bar, snap to the nearest page so we're never between pages.
  private func snapToNearestPage() {
    guard titles.count > 0 else { return }
    let progress = pageProgressFromContentOffset()
    let clampedProgress = max(0, min(progress, CGFloat(titles.count - 1)))
    let index = Int(round(clampedProgress))
    let roundedIndex = max(0, min(index, titles.count - 1))

    if roundedIndex != selectedIndex {
      let previousIndex = selectedIndex
      selectedIndex = roundedIndex
      UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseInOut) {
        if let prev = self.collectionView.cellForItem(at: IndexPath(item: previousIndex, section: 0)) as? TabCell {
          prev.setSelected(false)
        }
        if let curr = self.collectionView.cellForItem(at: IndexPath(item: roundedIndex, section: 0)) as? TabCell {
          curr.setSelected(true)
        }
      }
    }

    isProgrammaticScroll = true
    suspendSelectionSyncFromScroll = true
    setPageProgress(CGFloat(roundedIndex), animated: true)
    delegate?.tabBar(self, didSelectTabAt: roundedIndex)
  }

  /// From current contentOffset, compute which page progress is at the visible center.
  /// Uses same left inset as layout.
  private func pageProgressFromContentOffset() -> CGFloat {
    let cv = collectionView
    let centerX = cv.contentOffset.x + cv.bounds.width / 2
    let widths = titles.map { cellWidth(for: $0) }
    guard !widths.isEmpty else { return 0 }
    let leftInset = cv.bounds.width / 2 - widths[0] / 2
    let spacing: CGFloat = 8
    func centerOfItem(_ i: Int) -> CGFloat {
      var x = leftInset
      for j in 0..<i { x += widths[j] + spacing }
      return x + widths[i] / 2
    }
    if centerX <= centerOfItem(0) { return 0 }
    for i in 0..<(widths.count - 1) {
      let c0 = centerOfItem(i)
      let c1 = centerOfItem(i + 1)
      if centerX <= c1 {
        let t = (centerX - c0) / (c1 - c0)
        return CGFloat(i) + max(0, min(1, t))
      }
    }
    return CGFloat(widths.count - 1)
  }
}

// MARK: - UICollectionViewDataSource

extension GameCategoryTabBar: UICollectionViewDataSource {
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int)
    -> Int
  {
    titles.count
  }

  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
    -> UICollectionViewCell
  {
    let cell =
      collectionView.dequeueReusableCell(withReuseIdentifier: TabCell.reuseID, for: indexPath)
      as! TabCell
    cell.configure(title: titles[indexPath.item])
    cell.setSelected(indexPath.item == selectedIndex)
    return cell
  }
}

// MARK: - UICollectionViewDelegate (and UIScrollViewDelegate for the collection view)

extension GameCategoryTabBar: UICollectionViewDelegate {
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard scrollView === collectionView else { return }
    let progress = pageProgressFromContentOffset()
    let clampedProgress = max(0, min(progress, CGFloat(titles.count - 1)))
    let newIndex = Int(round(clampedProgress))
    let clamped = max(0, min(newIndex, titles.count - 1))
    if !suspendSelectionSyncFromScroll, clamped != selectedIndex {
      let previousIndex = selectedIndex
      selectedIndex = clamped
      UIView.animate(withDuration: 0.15, delay: 0, options: .curveEaseInOut) {
        if let prev = self.collectionView.cellForItem(at: IndexPath(item: previousIndex, section: 0)) as? TabCell {
          prev.setSelected(false)
        }
        if let curr = self.collectionView.cellForItem(at: IndexPath(item: clamped, section: 0)) as? TabCell {
          curr.setSelected(true)
        }
      }
    }
    if !isProgrammaticScroll {
      delegate?.tabBar(self, didScrollToPageProgress: clampedProgress)
    }
  }

  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    if scrollView === collectionView {
      isProgrammaticScroll = false
    }
  }

  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    if scrollView === collectionView, !decelerate {
      snapToNearestPage()
    }
  }

  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    if scrollView === collectionView {
      snapToNearestPage()
    }
  }

  func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
    if scrollView === collectionView {
      isProgrammaticScroll = false
      suspendSelectionSyncFromScroll = false
      delegate?.tabBarDidEndScrolling(self)
    }
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard indexPath.item != selectedIndex else { return }
    let previousIndex = selectedIndex
    selectedIndex = indexPath.item

    HapticsHelper.lightHaptic()

    UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
      if let prev = collectionView.cellForItem(at: IndexPath(item: previousIndex, section: 0))
        as? TabCell
      {
        prev.setSelected(false)
      }
      if let curr = collectionView.cellForItem(at: indexPath) as? TabCell {
        curr.setSelected(true)
      }
    }

    // Prevent scrollViewDidScroll from reporting progress during this animation (avoids fight with page view).
    isProgrammaticScroll = true
    suspendSelectionSyncFromScroll = true
    collectionView.scrollToItem(
      at: indexPath,
      at: .centeredHorizontally,
      animated: true
    )

    delegate?.tabBar(self, didSelectTabAt: indexPath.item)
  }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension GameCategoryTabBar: UICollectionViewDelegateFlowLayout {
  func collectionView(
    _ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
    sizeForItemAt indexPath: IndexPath
  ) -> CGSize {
    let title = titles[indexPath.item]
    let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
    let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
    return CGSize(width: textWidth + 32, height: 36)
  }

  func collectionView(
    _ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
    insetForSectionAt section: Int
  ) -> UIEdgeInsets {
    // So that at contentOffset.x = 0 the first tab is centered, and at contentOffset.x = max the last tab is centered.
    // That gives a fixed scroll range with native bounce at both ends.
    guard !titles.isEmpty, collectionView.bounds.width > 0 else {
      return UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
    }
    let w0 = cellWidth(for: titles[0])
    let wLast = cellWidth(for: titles[titles.count - 1])
    let half = collectionView.bounds.width / 2
    let leftInset = half - w0 / 2
    let rightInset = half - wLast / 2
    return UIEdgeInsets(top: 4, left: leftInset, bottom: 4, right: rightInset)
  }
}

// MARK: - Tab Cell

private class TabCell: UICollectionViewCell {
  static let reuseID = "GameCategoryTabCell"

  private let titleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .semibold)
    label.textAlignment = .center
    return label
  }()

  private let pillBackground: UIView = {
    let v = UIView()
    v.translatesAutoresizingMaskIntoConstraints = false
    v.layer.cornerRadius = 18
    v.clipsToBounds = true
    return v
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.addSubview(pillBackground)
    contentView.addSubview(titleLabel)
    NSLayoutConstraint.activate([
      pillBackground.topAnchor.constraint(equalTo: contentView.topAnchor),
      pillBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      pillBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      pillBackground.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(title: String) {
    titleLabel.text = title
  }

  func setSelected(_ selected: Bool) {
    pillBackground.backgroundColor = selected ? HardwayColors.surfaceGray : .clear
    titleLabel.textColor = selected ? .white : HardwayColors.label
  }
}
