//
//  GameSetupFlowViewController.swift
//  ludo
//

import UIKit

/// Sheet: choose **Pass and Play** (only active mode for now), then player count 2–4.
final class GameSetupFlowViewController: UIViewController {

    var onStartGame: ((Int) -> Void)?

    private let scroll = UIScrollView()
    private let content = UIStackView()

    private lazy var modeTitle: UILabel = makeHeading("How do you want to play?")
    private lazy var passAndPlayButton = makePrimaryButton(title: "Pass and Play", action: #selector(didTapPassAndPlay))
    private lazy var localButton = makeSecondaryDisabledButton(title: "Local Multiplayer")
    private lazy var onlineButton = makeSecondaryDisabledButton(title: "Online")

    private lazy var playersTitle: UILabel = makeHeading("How many players?")
    private lazy var playersRow: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.spacing = 12
        s.distribution = .fillEqually
        s.alignment = .fill
        return s
    }()

    private lazy var backButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Back", for: .normal)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        b.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)
        b.accessibilityIdentifier = "setup_back"
        return b
    }()

    private lazy var modeStack: UIStackView = {
        let s = UIStackView(arrangedSubviews: [modeTitle, passAndPlayButton, localButton, onlineButton])
        s.axis = .vertical
        s.spacing = 14
        s.alignment = .fill
        return s
    }()

    private lazy var playersStack: UIStackView = {
        let top = UIStackView(arrangedSubviews: [backButton, UIView()])
        top.axis = .horizontal
        top.alignment = .center

        let s = UIStackView(arrangedSubviews: [top, playersTitle, playersRow])
        s.axis = .vertical
        s.spacing = 20
        s.alignment = .fill
        s.isHidden = true
        return s
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 24
        content.alignment = .fill

        view.addSubview(scroll)
        scroll.addSubview(content)
        content.addArrangedSubview(modeStack)
        content.addArrangedSubview(playersStack)

        for n in 2...4 {
            let b = makePlayerCountButton(n)
            playersRow.addArrangedSubview(b)
        }

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -28),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40),
        ])

        passAndPlayButton.accessibilityIdentifier = "setup_pass_and_play"
        localButton.accessibilityIdentifier = "setup_local_multiplayer"
        onlineButton.accessibilityIdentifier = "setup_online"
    }

    private func makeHeading(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        l.textColor = .label
        l.numberOfLines = 0
        return l
    }

    private func makePrimaryButton(title: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        b.setTitleColor(UIColor(red: 0.12, green: 0.22, blue: 0.14, alpha: 1), for: .normal)
        b.backgroundColor = UIColor(red: 0.55, green: 0.78, blue: 0.45, alpha: 1)
        b.layer.cornerRadius = 12
        b.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    private func makeSecondaryDisabledButton(title: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        b.setTitleColor(.secondaryLabel, for: .normal)
        b.backgroundColor = UIColor.secondarySystemFill
        b.layer.cornerRadius = 12
        b.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        b.alpha = 0.45
        b.isEnabled = false
        return b
    }

    private func makePlayerCountButton(_ n: Int) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle("\(n)", for: .normal)
        b.titleLabel?.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = UIColor(red: 0.18, green: 0.42, blue: 0.28, alpha: 1)
        b.layer.cornerRadius = 12
        b.tag = n
        b.addTarget(self, action: #selector(didPickPlayerCount(_:)), for: .touchUpInside)
        b.accessibilityIdentifier = "setup_players_\(n)"
        return b
    }

    @objc private func didTapPassAndPlay() {
        UIView.transition(with: content, duration: 0.25, options: .transitionCrossDissolve) {
            self.modeStack.isHidden = true
            self.playersStack.isHidden = false
        }
    }

    @objc private func didTapBack() {
        UIView.transition(with: content, duration: 0.25, options: .transitionCrossDissolve) {
            self.playersStack.isHidden = true
            self.modeStack.isHidden = false
        }
    }

    @objc private func didPickPlayerCount(_ sender: UIButton) {
        let n = sender.tag
        guard (2...4).contains(n) else { return }
        onStartGame?(n)
    }
}
