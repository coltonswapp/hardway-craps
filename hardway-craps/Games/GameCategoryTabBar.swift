//
//  GameCategoryTabBar.swift
//  hardway-craps
//
//  Created by Colton Swapp on 3/6/26.
//

import UIKit

protocol GameCategoryTabBarDelegate: AnyObject {
  func tabBar(_ tabBar: GameCategoryTabBar, didSelectTabAt index: Int)
}

class GameCategoryTabBar: UIView {

  weak var delegate: GameCategoryTabBarDelegate?

  private(set) var selectedIndex: Int = 0
  private var titles: [String] = []

  private lazy var collectionView: UICollectionView = {
    let layout = UICollectionViewFlowLayout()
    layout.scrollDirection = .horizontal
    layout.minimumInteritemSpacing = 8
    let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
    cv.translatesAutoresizingMaskIntoConstraints = false
    cv.backgroundColor = .clear
    cv.showsHorizontalScrollIndicator = false
    cv.isScrollEnabled = false
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
    collectionView.scrollToItem(
      at: IndexPath(item: index, section: 0),
      at: .centeredHorizontally,
      animated: animated
    )
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

// MARK: - UICollectionViewDelegate

extension GameCategoryTabBar: UICollectionViewDelegate {
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

    // Scroll to center the selected tab
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
    // Add horizontal insets equal to half the screen width to allow centering
    let horizontalInset = collectionView.bounds.width / 2
    return UIEdgeInsets(top: 4, left: horizontalInset, bottom: 4, right: horizontalInset)
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
