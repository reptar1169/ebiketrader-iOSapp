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
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .aspectRatio(4.0 / 3.0, contentMode: .fit)
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
