import Foundation
import Observation
import SwiftUI
import SwiftData
import UIKit
import UserNotifications

enum ImportantDayRouteSource: Sendable { case widget, notification }
struct ImportantDayExternalRoute: Identifiable, Equatable, Sendable {
    let id: UUID
    let source: ImportantDayRouteSource
}
@MainActor @Observable
final class ImportantDayExternalRouter {
    static let shared = ImportantDayExternalRouter()
    var pending: ImportantDayExternalRoute?
    func receive(id: UUID, source: ImportantDayRouteSource) { pending = .init(id: id, source: source) }
    static func hasPresentedController() -> Bool {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).filter(\.isKeyWindow).contains { $0.rootViewController?.presentedViewController != nil }
    }
}

final class ImportantDayNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self; return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let text = response.notification.request.content.userInfo["importantDayID"] as? String, let id = UUID(uuidString: text) {
            Task { @MainActor in ImportantDayExternalRouter.shared.receive(id: id, source: .notification) }
        }
        if let day = response.notification.request.content.userInfo["sleepWakeDay"] as? String {
            Task { @MainActor in SleepExternalRouter.shared.receive(day: day) }
        }
        completionHandler()
    }
}

struct ImportantDayRoutedView: View {
    let route: ImportantDayExternalRoute
    let mediaStore: MediaStore
    let thumbnailStore: ThumbnailStore
    @Query private var days: [ImportantDay]
    var body: some View {
        if let day = days.first(where: { $0.id == route.id }), !day.isArchived,
           route.source == .notification || (try? day.preferences().desktopVisible) == true {
            ImportantDayDetailView(dayID: day.id, mediaStore: mediaStore, thumbnailStore: thumbnailStore)
        } else {
            ContentUnavailableView("Day unavailable", systemImage: "calendar.badge.exclamationmark", description: Text("This day was removed, archived or is no longer authorized for desktop display."))
                .accessibilityIdentifier("important-day-route-unavailable")
        }
    }
}
