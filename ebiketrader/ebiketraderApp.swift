//
//  ebiketraderApp.swift
//  ebiketrader
//

import SwiftUI
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

@main
struct ebiketraderApp: App {
    // Push needs real UIApplicationDelegate callbacks (APNs token delivery,
    // notification taps), which SwiftUI's App protocol doesn't expose.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Reads GoogleService-Info.plist from the bundle — the app talks to
        // the same Firebase project (ebiketrader-12409) as ebiketrader.net,
        // so listings, accounts and messages are shared, and the existing
        // firestore.rules apply unchanged.
        FirebaseApp.configure()

        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        return true
    }

    /// APNs hands back the device token; FCM needs it to mint its own.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Push registration failed: \(error.localizedDescription)")
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            PushService.shared.updateToken(fcmToken)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show the banner even when the app is open — but the thread the user is
    /// already reading is handled on the receiving side, where the live
    /// Firestore listener has already put the message on screen.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    /// Notification tapped — hand the conversation id to the inbox.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let conversationId = info["conversationId"] as? String else { return }
        await MainActor.run {
            PushService.shared.pendingConversationId = conversationId
        }
    }
}
