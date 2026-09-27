//
//  AccountView.swift
//  ebiketrader
//

import SwiftUI
import UserNotifications

struct AccountView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var push: PushService
    @EnvironmentObject private var blocks: BlockStore

    @State private var confirmDelete = false

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

                NavigationLink {
                    BlockedUsersView()
                } label: {
                    HStack {
                        Label("Blocked users", systemImage: "hand.raised.slash")
                        if !blocks.blocked.isEmpty {
                            Spacer()
                            Text("\(blocks.blocked.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Link(destination: URL(string: "https://ebiketrader.net")!) {
                    Label("Open ebiketrader.net", systemImage: "safari")
                }
            }

            // Spelled out as header: rather than Section("Legal") because
            // there is no Section initialiser taking a string title *and* a
            // footer — the title shorthand only supplies a header.
            Section {
                Link(destination: Legal.support) {
                    Label("Help & support", systemImage: "questionmark.circle")
                }
                Link(destination: Legal.privacy) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                Link(destination: Legal.terms) {
                    Label("Terms of Use", systemImage: "doc.text")
                }
            } header: {
                Text("Legal")
            } footer: {
                Text("City suggestions use place-name data from GeoNames, licensed under CC BY 4.0.")
            }

            Section {
                notificationsRow
            } header: {
                Text("Notifications")
            } footer: {
                Text("Get a push when someone messages you about a listing.")
            }

            Section {
                Button("Delete account", role: .destructive) {
                    confirmDelete = true
                }
                .disabled(auth.isWorking)

                // Deletion is an Apple-required flow, so a failure must not
                // be silent: without this the spinner just vanishes and the
                // account is still there, with no explanation.
                if let error = auth.errorMessage {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text(error)
                        Spacer(minLength: 8)
                        Button("Dismiss") { auth.errorMessage = nil }
                            .font(.caption.weight(.medium))
                    }
                    .font(.footnote)
                    .foregroundStyle(.red)
                }
            } footer: {
                Text("Permanently removes your account, your listings and their photos, and your saved listings. Conversations stay visible to the other person, with your name removed. This can't be undone.")
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
        .confirmationDialog(
            "Delete your account?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete my account", role: .destructive) {
                Task {
                    if let uid = auth.uid {
                        await push.unregister(uid: uid)
                    }
                    await auth.deleteAccount()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account and your listings. It can't be undone.")
        }
        .progressOverlay(auth.isWorking, title: "Deleting your account…")
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
