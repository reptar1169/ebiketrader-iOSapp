//
//  ListingPhoto.swift
//  ebiketrader
//

import SwiftUI

/// One photo from Firebase Storage. AsyncImage is backed by URLSession's
/// shared cache, which is enough for a feed this size — no third-party image
/// library, and repeat scrolls don't re-download.
struct ListingPhoto: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                fallback(icon: "photo")
            case .empty:
                ZStack {
                    Theme.placeholder
                    ProgressView()
                }
            @unknown default:
                fallback(icon: "photo")
            }
        }
    }

    private func fallback(icon: String) -> some View {
        ZStack {
            Theme.placeholder
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

/// A photo cropped to the 4:3 box the listing grid and gallery both use.
/// Sizing via a clear spacer and an overlay keeps the frame fixed regardless
/// of the image's own dimensions, so cards in a row never end up ragged.
struct ListingPhotoBox: View {
    let url: URL?
    var cornerRadius: CGFloat = 12

    var body: some View {
        Color.clear
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .overlay { ListingPhoto(url: url) }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
