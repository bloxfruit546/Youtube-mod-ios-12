import UIKit
import AVFoundation

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        CrashCatcher.install()
        AppLogger.shared.info("LiteTube5s launched. RAM: \(MemoryMonitor.formattedUsage())")

        // Keep URLCache tightly bounded on 1GB RAM iPhone 5s
        URLCache.shared = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 20 * 1024 * 1024, diskPath: "LiteTube5sHTTP")

        configureAudioSession()

        let win = UIWindow(frame: UIScreen.main.bounds)
        win.rootViewController = RootContainerViewController()
        win.makeKeyAndVisible()
        self.window = win

        return true
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            AppLogger.shared.error("AVAudioSession config failed: \(error.localizedDescription)")
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        PlayerManager.shared.handleEnterBackground()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        PlayerManager.shared.handleEnterForeground()
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        ImageLoader.shared.clearMemoryCache()
        URLCache.shared.removeAllCachedResponses()
        AppLogger.shared.warn("didReceiveMemoryWarning! Cleared caches. RAM: \(MemoryMonitor.formattedUsage())")
    }
}
