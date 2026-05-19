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

  /// Continuous page index (0…count−1) driving tab scroll position. Kept in sync with the pager and with
  /// user drags on this bar. `layoutSubviews` restores `contentOffset` from this value instead of snapping
  /// to `selectedIndex`, so mid-swipe fractional positions are preserved and categories keep sliding with
  /// the page view.
  private var pageProgressTracking: CGFloat = 0

  /// Stationary pill at the visual center. Its width morphs with the centered tab; labels in the
  /// horizontally scrolling collection view slide over it.
  private let pillBackground: UIView = {
    let v = UIView()
    v.layer.cornerRadius = 18
    v.clipsToBounds = true
    v.isUserInteractionEnabled = false
    v.backgroundColor = HardwayColors.surfaceGray
    return v
  }()

  private static let pillHeight: CGFloat = 36

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
    // Pill goes behind the collection view so labels slide on top of it.
    addSubview(pillBackground)
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
    // Re-apply horizontal offset from continuous progress. Do not use `scrollToItem(selectedIndex)` here:
    // that snaps to whole tabs and destroys fractional alignment while the pager is mid-swipe.
    if collectionView.numberOfItems(inSection: 0) > 0, titles.count > 0 {
      let p = max(0, min(pageProgressTracking, CGFloat(titles.count - 1)))
      setPageProgress(p, animated: false)
    }
    updatePillAndLabels(progress: pageProgressFromContentOffset())
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func selectTab(at index: Int, animated: Bool) {
    guard index >= 0, index < titles.count, index != selectedIndex else { return }
    selectedIndex = index
    pageProgressTracking = CGFloat(index)

    HapticsHelper.lightHaptic()

    // Scroll to center the selected tab; the scroll itself drives pill width and label color
    // updates via `scrollViewDidScroll`, so no explicit per-cell animation is needed.
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
      updatePillAndLabels(progress: CGFloat(index))
    }
  }

  /// Sync tab bar scroll position to a continuous page progress (0...titles.count-1). Used when the underlying page view is scrolled.
  func setPageProgress(_ progress: CGFloat, animated: Bool) {
    guard titles.count > 0, let range = contentOffsetRangeX() else { return }
    let clamped = max(0, min(progress, CGFloat(titles.count - 1)))
    pageProgressTracking = clamped
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

    selectedIndex = roundedIndex

    isProgrammaticScroll = true
    suspendSelectionSyncFromScroll = true
    setPageProgress(CGFloat(roundedIndex), animated: true)
    delegate?.tabBar(self, didSelectTabAt: roundedIndex)
  }

  /// Sync the stationary pill's width and every visible label's color to the given page progress.
  /// The pill stays centered in the bar; its width interpolates between the current and next tab's
  /// widths so it appears to morph in place as labels slide beneath it.
  private func updatePillAndLabels(progress: CGFloat) {
    guard !titles.isEmpty, bounds.width > 0 else { return }
    let count = titles.count
    let clamped = max(0, min(progress, CGFloat(count - 1)))

    let widths = titles.map { cellWidth(for: $0) }
    let i = min(Int(clamped), count - 1)
    let t = clamped - CGFloat(i)
    let pillWidth: CGFloat
    if i >= count - 1 || t <= 0 {
      pillWidth = widths[i]
    } else {
      pillWidth = widths[i] + t * (widths[i + 1] - widths[i])
    }

    let height = Self.pillHeight
    pillBackground.bounds = CGRect(x: 0, y: 0, width: pillWidth, height: height)
    pillBackground.center = CGPoint(x: bounds.midX, y: bounds.midY)

    for cell in collectionView.visibleCells {
      guard
        let tabCell = cell as? TabCell,
        let indexPath = collectionView.indexPath(for: cell)
      else { continue }
      tabCell.setSelectedness(selectedness(forItem: indexPath.item, progress: clamped))
    }
  }

  /// 1.0 when this item is fully centered, 0.0 when it's a full tab away.
  private func selectedness(forItem item: Int, progress: CGFloat) -> CGFloat {
    let distance = abs(CGFloat(item) - progress)
    return max(0, min(1, 1 - distance))
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
    let progress = pageProgressFromContentOffset()
    cell.setSelectedness(selectedness(forItem: indexPath.item, progress: progress))
    return cell
  }
}

// MARK: - UICollectionViewDelegate (and UIScrollViewDelegate for the collection view)

extension GameCategoryTabBar: UICollectionViewDelegate {
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard scrollView === collectionView else { return }
    let progress = pageProgressFromContentOffset()
    let clampedProgress = max(0, min(progress, CGFloat(titles.count - 1)))
    pageProgressTracking = clampedProgress

    // Continuously drive pill width and label colors so the pill appears stationary at center
    // while text labels slide horizontally beneath it.
    updatePillAndLabels(progress: clampedProgress)

    let newIndex = Int(round(clampedProgress))
    let clamped = max(0, min(newIndex, titles.count - 1))
    if !suspendSelectionSyncFromScroll, clamped != selectedIndex {
      selectedIndex = clamped
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
    selectedIndex = indexPath.item
    pageProgressTracking = CGFloat(indexPath.item)

    HapticsHelper.lightHaptic()

    // Prevent scrollViewDidScroll from reporting progress during this animation (avoids fight
    // with page view). The animated scroll itself drives pill width and label color updates.
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

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    contentView.backgroundColor = .clear
    contentView.addSubview(titleLabel)
    NSLayoutConstraint.activate([
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

  /// `amount` is 1.0 when this cell is fully centered (and so sits inside the stationary pill),
  /// fading to 0.0 as the cell scrolls a full tab-width away from center.
  func setSelectedness(_ amount: CGFloat) {
    let clamped = max(0, min(1, amount))
    titleLabel.textColor = TabCell.blend(
      from: HardwayColors.label,
      to: .white,
      t: clamped
    )
  }

  private static func blend(from a: UIColor, to b: UIColor, t: CGFloat) -> UIColor {
    var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
    var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
    a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
    b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
    return UIColor(
      red: ar + (br - ar) * t,
      green: ag + (bg - ag) * t,
      blue: ab + (bb - ab) * t,
      alpha: aa + (ba - aa) * t
    )
  }
}
