import UIKit
import UniformTypeIdentifiers

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
        for (index, mode) in ["mixed", "partial", "delayed"].enumerated() {
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
        if sender.tag != 0 {
            let photo = NSItemProvider()
            let delayed = sender.tag == 2
            photo.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
                let progress = Progress(totalUnitCount: 1)
                if delayed {
                    // Deliberately uncooperative fixture: a late callback even after Progress.cancel.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
                        progress.completedUnitCount = 1
                        completion(nil, false, CocoaError(.fileReadNoSuchFile))
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
