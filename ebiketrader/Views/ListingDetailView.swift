//
//  ListingDetailView.swift
//  ebiketrader
//

import SwiftUI

struct ListingDetailView: View {
    @StateObject private var store: ListingDetailStore

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var favorites: FavoriteStore
    @EnvironmentObject private var blocks: BlockStore

    @State private var showSignIn = false
    @State private var openThread: ConversationSummary?
    @State private var isStartingThread = false
    @State private var threadError: String?

    @State private var showEdit = false
    @State private var confirmDelete = false
    /// nil when idle; otherwise what to show in the progress overlay. A Bool
    /// could not distinguish marking sold from deleting.
    @State private var busyTitle: String?
    @State private var showReport = false
    @State private var confirmBlock = false

    @Environment(\.dismiss) private var dismiss

    init(listing: Listing) {
        _store = StateObject(wrappedValue: ListingDetailStore(listing: listing))
    }

    private var listing: Listing { store.listing }
    private var isOwner: Bool { auth.uid == listing.sellerId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PhotoGalleryView(photos: listing.photos, isSold: listing.status == .sold)

                VStack(alignment: .leading, spacing: 16) {
                    header
                    specs

                    if !listing.listingDescription.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Description")
                                .font(.subheadline.weight(.semibold))
                            // Sellers routinely put a serial number, a spec
                            // sheet link or a phone number in here, so this
                            // is a real UITextView (see SelectableText) and
                            // you can drag-select part of it.
                            SelectableText(
                                text: listing.listingDescription,
                                color: .secondaryLabel
                            )
                        }
                    }

                    seller

                    if let threadError {
                        Text(threadError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    contactSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .readableWidth()
        }
        .navigationTitle(listing.makeModel.isEmpty ? "Listing" : listing.makeModel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if auth.isSignedIn {
                        favorites.toggle(listing.id)
                    } else {
                        showSignIn = true
                    }
                } label: {
                    Image(systemName: favorites.isFavorite(listing.id) ? "heart.fill" : "heart")
                        .foregroundStyle(favorites.isFavorite(listing.id) ? .red : .primary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if let url = listing.webURL {
                    ShareLink(item: url, subject: Text(listing.title)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !isOwner {
                    Menu {
                        Button {
                            if auth.isSignedIn { showReport = true } else { showSignIn = true }
                        } label: {
                            Label("Report listing", systemImage: "flag")
                        }
                        Button(role: .destructive) {
                            if auth.isSignedIn { confirmBlock = true } else { showSignIn = true }
                        } label: {
                            Label("Block this seller", systemImage: "hand.raised.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .progressOverlay(busyTitle != nil, title: busyTitle ?? "")
        .onAppear { store.startIfNeeded() }
        .sheet(isPresented: $showReport) {
            ReportListingSheet(listing: listing)
        }
        .confirmationDialog(
            "Block \(listing.sellerName)?",
            isPresented: $confirmBlock,
            titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) { blockSeller() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their listings will stop appearing for you, and neither of you will be able to message the other. You can undo this under Account → Blocked users.")
        }
        .sheet(isPresented: $showEdit) {
            NavigationStack {
                // Cancel lives inside the form now: it is the only thing that
                // knows whether there are unsaved changes to warn about.
                ListingFormView(existing: listing, showsCancelButton: true)
            }
        }
        .confirmationDialog(
            "Delete this listing?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete listing", role: .destructive) { deleteListing() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. Its photos are removed too.")
        }
        .sheet(isPresented: $showSignIn) {
            NavigationStack {
                SignInView(dismissOnSignIn: true)
                    .navigationTitle("Sign in")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .navigationDestination(item: $openThread) { conversation in
            ThreadView(conversation: conversation)
        }
        .overlay {
            if store.wasRemoved {
                ContentUnavailableView(
                    "Listing removed",
                    systemImage: "trash",
                    description: Text("The seller took this listing down.")
                )
                .background(.background)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Format.price(listing.price))
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.brandDark)

            Text(listing.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                Text(listing.locationLine)
                if let posted = listing.createdAt, !Format.relativeTime(posted).isEmpty {
                    Text("· Listed \(Format.relativeTime(posted))")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            if listing.favoriteCount > 0 {
                Text("\(listing.favoriteCount) \(listing.favoriteCount == 1 ? "person has" : "people have") saved this")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Same rows, same order, same "hide it when it's blank" behavior as the
    /// Spec component in ListingDetailClient.tsx.
    private var specs: some View {
        VStack(spacing: 0) {
            SpecRow(label: "Brand", value: listing.brand)
            SpecRow(label: "Model", value: listing.model)
            SpecRow(label: "Year", value: listing.year.map(String.init))
            SpecRow(label: "Condition", value: listing.condition.label)
            SpecRow(label: "Mileage", value: listing.mileageMiles.map { "\($0) mi" })
            SpecRow(label: "Battery health", value: listing.batteryHealthPct.map { "\($0)%" })
            SpecRow(label: "Motor", value: listing.motorType)
            SpecRow(label: "Frame size", value: listing.frameSize)
            SpecRow(label: "Wheel size", value: listing.wheelSize)
            SpecRow(label: "Color", value: listing.color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(Theme.placeholder, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var seller: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Seller")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(listing.sellerName)
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.placeholder, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var contactSection: some View {
        if isOwner {
            VStack(alignment: .leading, spacing: 10) {
                Text("This is your listing")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Edit") { showEdit = true }
                        .buttonStyle(.bordered)

                    Button(listing.status == .sold ? "Mark active" : "Mark sold") {
                        toggleSold()
                    }
                    .buttonStyle(.bordered)

                    Button("Delete", role: .destructive) { confirmDelete = true }
                        .buttonStyle(.bordered)
                }
                .disabled(busyTitle != nil)
            }
        } else {
            Button {
                startConversation()
            } label: {
                Group {
                    if isStartingThread {
                        ProgressView().tint(.white)
                    } else {
                        Text("Message the seller")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white)
            }
            .disabled(isStartingThread)
        }
    }

    private func blockSeller() {
        Task {
            do {
                try await blocks.block(userId: listing.sellerId, displayName: listing.sellerName)
                // The feed filters on the block, so there's nothing sensible
                // left on this screen.
                dismiss()
            } catch {
                threadError = error.localizedDescription
            }
        }
    }

    private func toggleSold() {
        let next: ListingStatus = listing.status == .sold ? .active : .sold
        busyTitle = next == .sold ? "Marking as sold…" : "Marking as active…"
        Task {
            do {
                try await ListingWriter.setStatus(listingId: listing.id, status: next)
            } catch {
                threadError = error.localizedDescription
            }
            busyTitle = nil
        }
    }

    private func deleteListing() {
        // Slower than it looks: the document, then every photo out of
        // Storage one by one.
        busyTitle = "Deleting your listing…"
        Task {
            do {
                try await ListingWriter.delete(listingId: listing.id, photoURLs: listing.photos)
                dismiss()
            } catch {
                threadError = error.localizedDescription
                busyTitle = nil
            }
        }
    }

    /// Creates the thread if it doesn't exist yet (idempotent, exactly like
    /// the website's getOrCreateConversation) and pushes it.
    private func startConversation() {
        guard let uid = auth.uid else {
            showSignIn = true
            return
        }

        isStartingThread = true
        threadError = nil

        Task {
            do {
                _ = try await ChatService.getOrCreateConversation(
                    listing: listing,
                    buyerId: uid,
                    buyerName: auth.displayName
                )
                openThread = ChatService.localSummary(
                    listing: listing,
                    buyerId: uid,
                    buyerName: auth.displayName
                )
            } catch {
                threadError = error.localizedDescription
            }
            isStartingThread = false
        }
    }
}

private struct SpecRow: View {
    let label: String
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                SelectableText(
                    text: value,
                    font: .preferredFont(forTextStyle: .subheadline).withWeight(.medium),
                    alignment: .right,
                    hugsContent: true
                )
            }
            .font(.subheadline)
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
    }
}
