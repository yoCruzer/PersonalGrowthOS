import UIKit
import UniformTypeIdentifiers

// Standalone synthetic host exercises the extension from a separate app.
@main
final class CaptureHostApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Fixture", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = CaptureHostScene.self
        return configuration
    }
}

final class CaptureHostScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = CaptureHostController()
        window.makeKeyAndVisible()
        self.window = window
    }
}

final class CaptureHostController: UIViewController {
    private let callbackLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        callbackLabel.frame = CGRect(x: 40, y: 500, width: 300, height: 60)
        callbackLabel.accessibilityIdentifier = "delayed-provider-finished"
        callbackLabel.isHidden = true
        view.addSubview(callbackLabel)
        for (index, mode) in ["mixed", "partial", "delayed", "retry"].enumerated() {
            let button = UIButton(type: .system)
            button.setTitle("Share \(mode) Fixture", for: .normal)
            button.accessibilityIdentifier = mode == "mixed" ? "capture-provider-host" : "capture-provider-\(mode)"
            button.tag = index
            button.frame = CGRect(x: 40, y: 160 + index * 80, width: 300, height: 60)
            button.addTarget(self, action: #selector(share(_:)), for: .touchUpInside)
            view.addSubview(button)
        }
    }

    @objc private func share(_ sender: UIButton) {
        let source = NSItemProvider(object: NSURL(string: "http://127.0.0.1:18763/capture.html")!)
        source.registerDataRepresentation(forTypeIdentifier: "com.example.capture-auxiliary", visibility: .all) { completion in
            completion(Data("Auxiliary representation".utf8), nil)
            return nil
        }
        let text = sender.tag == 2 ? "Cancelled session quote" : "Public host fixture quote"
        let quote = NSItemProvider(object: text as NSString)
        var providers = [source, quote]
        if sender.tag == 3 {
            let recovered = NSItemProvider()
            let attempts = RetryAttempts()
            recovered.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
                if attempts.next() == 1 {
                    completion(nil, CocoaError(.fileReadNoSuchFile))
                } else {
                    completion(Data("Recovered second passage".utf8), nil)
                }
                return nil
            }
            providers.append(recovered)
        } else if sender.tag != 0 {
            let photo = NSItemProvider()
            let delayed = sender.tag == 2
            photo.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
                let progress = Progress(totalUnitCount: 1)
                if delayed {
                    // Deliberately uncooperative fixture: a late callback even after Progress.cancel.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 12) {
                        progress.completedUnitCount = 1
                        completion(nil, false, CocoaError(.fileReadNoSuchFile))
                        DispatchQueue.main.async {
                            self.callbackLabel.text = "Delayed provider finished"
                            self.callbackLabel.isHidden = false
                        }
                    }
                } else {
                    progress.completedUnitCount = 1
                    completion(nil, false, CocoaError(.fileReadNoSuchFile))
                }
                return progress
            }
            providers.append(photo)
        }
        let activity = UIActivityViewController(activityItemsConfiguration: UIActivityItemsConfiguration(itemProviders: providers))
        present(activity, animated: true)
    }
}

private final class RetryAttempts: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        count += 1
        return count
    }
}
