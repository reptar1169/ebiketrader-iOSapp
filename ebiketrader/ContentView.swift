//
//  ContentView.swift
//  ebiketrader
//

import SwiftUI

struct ContentView: View {
    // Owned here and handed down through the environment, so every tab reads
    // the same session, the same saved-listing set, and the same inbox.
    @StateObject private var auth = AuthStore()
    @StateObject private var favorites = FavoriteStore()
    @StateObject private var conversations = ConversationStore()
    @StateObject private var push = PushService.shared

    @State private var selectedTab = Tab.browse

    private enum Tab: Hashable {
        case browse, saved, sell, messages, account
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            BrowseView()
                .tabItem { Label("Browse", systemImage: "bicycle") }
                .tag(Tab.browse)

            SavedView()
                .tabItem { Label("Saved", systemImage: "heart") }
                .tag(Tab.saved)

            SellTabView()
                .tabItem { Label("Sell", systemImage: "plus.circle") }
                .tag(Tab.sell)

            InboxView()
                .tabItem { Label("Messages", systemImage: "bubble.left") }
                .badge(conversations.unreadCount())
                .tag(Tab.messages)

            AccountView()
                .tabItem { Label("Account", systemImage: "person") }
                .tag(Tab.account)
        }
        .tint(Theme.brand)
        .environmentObject(auth)
        .environmentObject(favorites)
        .environmentObject(conversations)
        .environmentObject(push)
        // Favorites, conversations and the device's push registration are all
        // per-user, so they get re-pointed whenever the signed-in user changes
        // (including to nil on sign-out, which clears them).
        .onAppear {
            favorites.bind(to: auth.uid)
            conversations.bind(to: auth.uid)
            push.bind(uid: auth.uid)
        }
        .onChange(of: auth.uid) { _, uid in
            favorites.bind(to: uid)
            conversations.bind(to: uid)
            push.bind(uid: uid)
        }
        // A tapped notification lands on PushService; switching tabs here
        // lets the inbox pick it up and push the thread.
        .onChange(of: push.pendingConversationId) { _, id in
            if id != nil { selectedTab = .messages }
        }
    }
}

#Preview {
    ContentView()
}
