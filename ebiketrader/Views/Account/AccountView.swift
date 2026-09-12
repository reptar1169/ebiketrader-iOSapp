//
//  AccountView.swift
//  ebiketrader
//

import SwiftUI
import UserNotifications

struct AccountView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var push: PushService

    var body: some View {
        NavigationStack {
            Group {
                if auth.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if auth.isSignedIn {
                    signedIn
                } else {
                    SignInView()
                }
            }
            .navigationTitle("Account")
        }
    }

    private var signedIn: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.displayName)
                        .font(.headline)
                    if !auth.email.isEmpty {
                        Text(auth.email)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                NavigationLink {
                    MyListingsView()
                } label: {
                    Label("My listings", systemImage: "list.bullet.rectangle")
                }

                Link(destination: URL(string: "https://ebiketrader.net")!) {
                    Label("Open ebiketrader.net", systemImage: "safari")
                }
            }

            Section {
                notificationsRow
            } header: {
                Text("Notifications")
            } footer: {
                Text("Get a push when someone messages you about a listing.")
            }

            Section {
                Button("Sign out", role: .destructive) {
                    Task {
                        // Detach this device first — once signed out,
                        // firestore.rules won't allow writing to the user's
                        // document to remove the token.
                        if let uid = auth.uid {
                            await push.unregister(uid: uid)
                        }
                        auth.signOut()
                    }
                }
            }
        }
        .task { await push.refreshAuthorizationStatus() }
    }

    @ViewBuilder
    private var notificationsRow: some View {
        switch push.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            Label("Message notifications are on", systemImage: "bell.badge")
                .foregroundStyle(.secondary)
        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Turn on in Settings", systemImage: "bell.slash")
            }
        default:
            Button {
                Task { await push.requestAuthorization() }
            } label: {
                Label("Turn on message notifications", systemImage: "bell")
            }
        }
    }
}
