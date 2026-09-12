//
//  PhotoGalleryView.swift
//  ebiketrader
//

import SwiftUI

/// Swipeable gallery at the top of a listing. Mirrors ListingGallery.tsx.
struct PhotoGalleryView: View {
    let photos: [String]
    let isSold: Bool

    @State private var index = 0
    @State private var showViewer = false

    var body: some View {
        Group {
            if photos.isEmpty {
                Color.clear
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .overlay {
                        ZStack {
                            Theme.placeholder
                            Image(systemName: "bicycle")
                                .font(.system(size: 44))
                                .foregroundStyle(.secondary)
                        }
                    }
            } else {
                TabView(selection: $index) {
                    ForEach(photos.indices, id: \.self) { photoIndex in
                        ListingPhoto(url: URL(string: photos[photoIndex]))
                            .clipped()
                            .tag(photoIndex)
                            .onTapGesture { showViewer = true }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
            }
        }
        // Opens on whichever photo is showing, so the viewer continues from
        // where the gallery was rather than starting over.
        .fullScreenCover(isPresented: $showViewer) {
            PhotoViewer(photos: photos, startIndex: index)
        }
        .overlay(alignment: .bottomTrailing) {
            if !photos.isEmpty {
                // Tap-to-expand is a familiar affordance but an invisible
                // one; this is the hint that it exists.
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if isSold {
                Text("SOLD")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.75), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(12)
            }
        }
    }
}
