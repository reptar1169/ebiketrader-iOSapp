//
//  SellTabView.swift
//  ebiketrader
//

import SwiftUI

struct SellTabView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var postedListingId: String?
    /// Bumped after a successful post so the form rebuilds empty — the tab
    /// root can't dismiss itself the way a pushed or sheeted form would.
    @State private var formToken = UUID()

    var body: some View {
        NavigationStack {
            Group {
                if auth.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if auth.isSignedIn {
                    ListingFormView(existing: nil) { id in
                        postedListingId = id
                        formToken = UUID()
                    }
                    .id(formToken)
                } else {
                    signedOut
                }
            }
        }
        .alert(
            "Listing posted",
            isPresented: Binding(
                get: { postedListingId != nil },
                set: { if !$0 { postedListingId = nil } }
            )
        ) {
            Button("Done") { postedListingId = nil }
        } message: {
            Text("Your bike is live. You'll find it under Account → My listings.")
        }
    }

    private var signedOut: some View {
        ScrollView {
            VStack(spacing: 16) {
                ContentUnavailableView {
                    Label("Sign in to list your bike", systemImage: "camera")
                } description: {
                    Text("You'll need an account so buyers can message you.")
                }
                NavigationLink {
                    SignInView()
                        .navigationTitle("Sign in")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Text("Sign in or create an account")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 40)
        }
        .navigationTitle("Sell")
    }
}
