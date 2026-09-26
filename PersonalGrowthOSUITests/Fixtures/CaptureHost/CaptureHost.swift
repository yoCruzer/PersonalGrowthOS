import UIKit

// Standalone synthetic host exercises the extension from a separate app.
@main
final class CaptureHostApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = CaptureHostController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class CaptureHostController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let button = UIButton(type: .system)
        button.setTitle("Share Mixed Fixture", for: .normal)
        button.accessibilityIdentifier = "capture-provider-host"
        button.frame = CGRect(x: 40, y: 160, width: 300, height: 60)
        button.addTarget(self, action: #selector(share), for: .touchUpInside)
        view.addSubview(button)
    }

    @objc private func share() {
        let source = NSItemProvider(object: NSURL(string: "http://127.0.0.1:18763/capture.html")!)
        source.registerDataRepresentation(forTypeIdentifier: "com.example.capture-auxiliary", visibility: .all) { completion in
            completion(Data("Auxiliary representation".utf8), nil)
            return nil
        }
        let quote = NSItemProvider(object: "Public host fixture quote" as NSString)
        let activity = UIActivityViewController(activityItemsConfiguration: UIActivityItemsConfiguration(itemProviders: [source, quote]))
        present(activity, animated: true)
    }
}
