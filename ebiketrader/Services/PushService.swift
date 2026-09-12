//
//  PushService.swift
//  ebiketrader
//

import Combine
import Foundation
import UIKit
import UserNotifications
import FirebaseFirestore
import FirebaseMessaging

/// Push registration and routing.
///
/// Device tokens are stored as an `fcmTokens` array on the user's own
/// users/{uid} document rather than in a subcollection — firestore.rules
/// already grants the owner full write access to that document, and Firestore
/// rules don't cascade into subcollections, so this needs no rules change at
/// all. A person has a handful of devices, not thousands, so an array is the
/// right shape.
@MainActor
final class PushService: ObservableObject {
    /// Set when a notification is tapped; the inbox watches this and opens
    /// the thread. Cleared once it's been handled.
    @Published var pendingConversationId: String?
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private var currentToken: String?
    private var boundUid: String?

    static let shared = PushService()

    private init() {}

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Asks for permission, then registers with APNs. Worth calling at a
    /// moment the request makes obvious sense (opening Messages), not at
    /// launch — iOS only ever shows this prompt once.
    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            // Denied or unavailable — nothing to recover from.
        }
        await refreshAuthorizationStatus()
    }

    /// Called by the messaging delegate whenever FCM issues or rotates a
    /// token. It can arrive before or after sign-in, so both this and
    /// bind(uid:) attempt the write.
    func updateToken(_ token: String?) {
        currentToken = token
        persistToken()
    }

    /// Re-points at the signed-in user. Call on sign-in and on user change.
    func bind(uid: String?) {
        guard uid != boundUid else { return }
        boundUid = uid
        persistToken()
    }

    /// Detaches this device from a user's push list. Must run *before* the
    /// sign-out itself — once signed out, firestore.rules won't permit
    /// writing to that user's document any more.
    func unregister(uid: String) async {
        guard let currentToken else { return }
        do {
            try await Firestore.firestore().collection("users").document(uid).updateData([
                "fcmTokens": FieldValue.arrayRemove([currentToken]),
            ])
        } catch {
            // Best-effort. A token left behind gets pruned by the Cloud
            // Function the first time a send to it fails.
        }
    }

    private func persistToken() {
        guard let boundUid, let currentToken else { return }
        Firestore.firestore().collection("users").document(boundUid).setData(
            ["fcmTokens": FieldValue.arrayUnion([currentToken])],
            merge: true
        )
    }
}
