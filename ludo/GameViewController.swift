//
//  GameViewController.swift
//  ludo
//
//  Created by Hardit Sabharwal on 2026-05-14.
//

import UIKit
import SpriteKit

final class GameViewController: UIViewController {

    private let playerCount: Int

    init(playerCount: Int) {
        self.playerCount = min(4, max(2, playerCount))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used; create GameViewController(playerCount:) in code.")
    }

    override func loadView() {
        view = SKView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let view = view as? SKView else { return }
        let scene = GameScene(size: view.bounds.size, playerCount: playerCount)
        scene.scaleMode = .resizeFill
        scene.onRequestMenu = { [weak self] in
            self?.dismiss(animated: true)
        }
        view.presentScene(scene)

        view.ignoresSiblingOrder = true
        view.showsFPS = true
        view.showsNodeCount = true
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        guard let view = view as? SKView else { return }
        if let scene = view.scene as? GameScene {
            scene.size = view.bounds.size
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
