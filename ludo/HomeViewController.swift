//
//  HomeViewController.swift
//  ludo
//

import UIKit

/// App entry: title and **Start** to open play-mode setup, then the game board.
final class HomeViewController: UIViewController {

    private let backgroundColorGame = UIColor(red: 0.22, green: 0.32, blue: 0.24, alpha: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = backgroundColorGame

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Ludo"
        titleLabel.font = UIFont.systemFont(ofSize: 44, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.accessibilityTraits = .header

        let subtitle = UILabel()
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.text = "Idea"
        subtitle.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        subtitle.textColor = UIColor(white: 1, alpha: 0.72)
        subtitle.textAlignment = .center

        let start = UIButton(type: .system)
        start.translatesAutoresizingMaskIntoConstraints = false
        start.setTitle("Start", for: .normal)
        start.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .semibold)
        start.setTitleColor(UIColor(red: 0.12, green: 0.22, blue: 0.14, alpha: 1), for: .normal)
        start.backgroundColor = UIColor(white: 0.96, alpha: 1)
        start.layer.cornerRadius = 14
        start.contentEdgeInsets = UIEdgeInsets(top: 16, left: 48, bottom: 16, right: 48)
        start.addTarget(self, action: #selector(didTapStart), for: .touchUpInside)
        start.accessibilityIdentifier = "home_start"

        view.addSubview(titleLabel)
        view.addSubview(subtitle)
        view.addSubview(start)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -72),

            subtitle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitle.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

            start.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            start.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 56),
        ])
    }

    @objc private func didTapStart() {
        let setup = GameSetupFlowViewController()
        setup.onStartGame = { [weak self] playerCount in
            guard let self else { return }
            self.dismiss(animated: true) {
                let game = GameViewController(playerCount: playerCount)
                game.modalPresentationStyle = .fullScreen
                self.present(game, animated: true)
            }
        }
        setup.modalPresentationStyle = .pageSheet
        if let sheet = setup.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(setup, animated: true)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        }
        return .all
    }

    override var prefersStatusBarHidden: Bool { true }
}
