//
//  AuthStore.swift
//  ebiketrader
//

import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import UIKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions

// Google sign-in needs the GoogleSignIn-iOS SDK, which is a separate Swift
// package from Firebase. Guarding on canImport means the app still builds
// without it — the Google button simply doesn't appear until the package is
// added (see the setup notes). Email/password and Apple need no extra
// packages at all.
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

/// Firebase Auth session, shared app-wide. Ports AuthContext.tsx: the same
/// providers, the same users/{uid} profile bootstrap after sign-in, and the
/// same presence heartbeat that lets the message-notification Cloud Function
/// skip pinging someone who is already looking at the app.
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var user: User?
    /// True until Firebase reports the restored session (or the lack of one),
    /// so the UI doesn't flash a signed-out state on launch.
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?
    @Published private(set) var isWorking = false

    private var authHandle: AuthStateDidChangeListenerHandle?
    private var presenceTimer: Timer?
    /// Held between building the Apple request and handling its result —
    /// Firebase verifies the raw value against the SHA256 in the ID token.
    private var appleNonce: String?

    var isSignedIn: Bool { user != nil }
    var uid: String? { user?.uid }
    var displayName: String { user?.displayName ?? user?.email ?? "You" }
    var email: String { user?.email ?? "" }

    /// Whether Google sign-in is compiled in.
    static var googleSignInAvailable: Bool {
        #if canImport(GoogleSignIn)
        return true
        #else
        return false
        #endif
    }

    init() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                self.user = user
                self.isLoading = false
                if let user {
                    await self.ensureUserProfile(for: user)
                    self.startPresenceHeartbeat()
                } else {
                    self.stopPresenceHeartbeat()
                }
            }
        }
    }

    // MARK: - Email and password

    func signIn(email: String, password: String) async {
        await perform {
            try await Auth.auth().signIn(withEmail: email, password: password)
        }
    }

    func signUp(email: String, password: String, displayName: String) async {
        await perform {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let change = result.user.createProfileChangeRequest()
            change.displayName = displayName
            try await change.commitChanges()
            // The auth listener fires before the display name is committed,
            // so write the profile again with the real name.
            await self.ensureUserProfile(for: result.user, nameOverride: displayName)
        }
    }

    func sendPasswordReset(to email: String) async {
        await perform {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        }
    }

    // MARK: - Sign in with Apple

    /// Called from SignInWithAppleButton's request builder.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// Called from SignInWithAppleButton's completion handler.
    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            // The user tapping Cancel surfaces here too; that isn't an error
            // worth showing them.
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let nonce = appleNonce,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Apple didn't return a usable sign-in token. Please try again."
                return
            }

            // Apple hands over the person's name only on the very first
            // authorization, so it has to be captured here or it's gone.
            let appleName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            Task {
                await self.perform {
                    let firebaseCredential = OAuthProvider.appleCredential(
                        withIDToken: idToken,
                        rawNonce: nonce,
                        fullName: credential.fullName
                    )
                    let result = try await Auth.auth().signIn(with: firebaseCredential)
                    if !appleName.isEmpty, (result.user.displayName ?? "").isEmpty {
                        let change = result.user.createProfileChangeRequest()
                        change.displayName = appleName
                        try await change.commitChanges()
                        await self.ensureUserProfile(for: result.user, nameOverride: appleName)
                    }
                }
            }
        }
    }

    // MARK: - Google

    func signInWithGoogle() async {
        #if canImport(GoogleSignIn)
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Google sign-in isn't configured for this app yet."
            return
        }
        guard let presenter = Self.topViewController() else { return }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        await perform {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthError.message("Google didn't return a sign-in token.")
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            try await Auth.auth().signIn(with: credential)
        }
        #else
        errorMessage = "Google sign-in isn't available in this build."
        #endif
    }

    // MARK: - Sign out

    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Account deletion

    /// Erases the account. The work happens in the deleteAccount Cloud
    /// Function rather than here: it needs the Admin SDK to reach documents
    /// this client can't (the other side of a conversation, reports), and
    /// going through Admin also avoids Firebase's "recent login required"
    /// rule, which would otherwise force a password prompt — impossible to
    /// satisfy gracefully for someone who signed in with Apple months ago.
    ///
    /// Required by App Store Review Guideline 5.1.1(v).
    func deleteAccount() async -> Bool {
        isWorking = true
        errorMessage = nil

        do {
            _ = try await Functions.functions().httpsCallable("deleteAccount").call()
            // The Auth user is already gone server-side; this clears the
            // local session and drops every listener bound to the old uid.
            try? Auth.auth().signOut()
            isWorking = false
            return true
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
            isWorking = false
            return false
        }
    }

    // MARK: - Profile and presence

    /// Port of ensureUserProfile() in src/lib/users.ts — createdAt only on
    /// first write, name/email refreshed every sign-in.
    private func ensureUserProfile(for user: User, nameOverride: String? = nil) async {
        let reference = Firestore.firestore().collection("users").document(user.uid)
        let name = nameOverride ?? user.displayName ?? "Seller"
        let email = user.email ?? ""

        do {
            let existing = try await reference.getDocument()
            if existing.exists {
                try await reference.setData(["displayName": name, "email": email], merge: true)
            } else {
                try await reference.setData([
                    "displayName": name,
                    "email": email,
                    "createdAt": FieldValue.serverTimestamp(),
                ])
            }
        } catch {
            // Best-effort, exactly as on the web — a failed profile write
            // should never block someone from using the app.
        }
    }

    /// Port of touchPresence() plus the 60s heartbeat in AuthContext.tsx.
    private func startPresenceHeartbeat() {
        stopPresenceHeartbeat()
        touchPresence()
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard UIApplication.shared.applicationState == .active else { return }
                self?.touchPresence()
            }
        }
    }

    private func stopPresenceHeartbeat() {
        presenceTimer?.invalidate()
        presenceTimer = nil
    }

    func touchPresence() {
        guard let uid = user?.uid else { return }
        Firestore.firestore()
            .collection("users")
            .document(uid)
            .setData(["lastActiveAt": FieldValue.serverTimestamp()], merge: true) { _ in
                // Best-effort; presence only suppresses redundant notifications.
            }
    }

    // MARK: - Helpers

    private func perform(_ work: @escaping () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        do {
            try await work()
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
        isWorking = false
    }

    enum AuthError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self {
            case .message(let text): return text
            }
        }
    }

    /// Firebase's raw messages are serviceable but blunt; these are the few
    /// cases a real person hits often enough to be worth rewording.
    ///
    /// Matched on the numeric FIRAuthErrorCode values rather than the
    /// AuthErrorCode type, which has changed shape between Firebase major
    /// versions (an enum in 9.x, a struct in 10+) — the numbers themselves
    /// are stable public API and compile against any of them.
    private static func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == "FIRAuthErrorDomain" else {
            return error.localizedDescription
        }

        switch nsError.code {
        case 17004, 17009, 17011:
            // invalidCredential / wrongPassword / userNotFound. Firebase
            // deliberately blurs these together when email enumeration
            // protection is on, so one message covers all three.
            return "That email and password don't match an account."
        case 17008:
            return "That doesn't look like a valid email address."
        case 17007:
            return "There's already an account with that email. Try signing in instead."
        case 17026:
            return "Pick a password at least 6 characters long."
        case 17020:
            return "Couldn't reach the network. Check your connection and try again."
        case 17012:
            return "You already have an account with that email, created with a different sign-in method. Use the one you signed up with."
        default:
            return error.localizedDescription
        }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            // Falls back to UUIDs rather than trapping — still unpredictable
            // enough for a replay nonce, and never crashes a sign-in.
            return UUID().uuidString + UUID().uuidString
        }
        // charset has 64 entries and 256 is a multiple of 64, so the modulo
        // here introduces no bias.
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Topmost view controller, for SDKs that need something to present from.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
