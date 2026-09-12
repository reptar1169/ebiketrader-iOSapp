//
//  PhotoViewer.swift
//  ebiketrader
//

import SwiftUI
import UIKit

/// Full-screen photo viewer: swipe between a listing's photos, pinch or
/// double-tap to zoom, drag to pan while zoomed.
struct PhotoViewer: View {
    let photos: [String]

    @State private var index: Int
    @Environment(\.dismiss) private var dismiss

    init(photos: [String], startIndex: Int) {
        self.photos = photos
        _index = State(initialValue: min(max(0, startIndex), max(0, photos.count - 1)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(photos.indices, id: \.self) { photoIndex in
                    ZoomablePhoto(url: URL(string: photos[photoIndex]))
                        .tag(photoIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            HStack {
                if photos.count > 1 {
                    Text("\(index + 1) of \(photos.count)")
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.45), in: Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .statusBarHidden()
    }
}

/// Loads the photo, then hands it to a UIScrollView to do the zooming.
private struct ZoomablePhoto: View {
    let url: URL?

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                ZoomableScrollView(image: image)
            } else if failed {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task {
            guard image == nil, let url else { return }
            // URLSession's shared cache is the same one AsyncImage used to
            // draw the gallery thumbnail, so this usually resolves from disk
            // rather than re-downloading.
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                image = UIImage(data: data)
                failed = image == nil
            } catch {
                failed = true
            }
        }
    }
}

/// Pinch-zoom is UIScrollView's job. Rebuilding it from SwiftUI gestures
/// means reimplementing momentum, rubber-banding, double-tap-to-zoom and
/// centring, and then fighting the paging TabView for the same drag.
private struct ZoomableScrollView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ZoomingImageView {
        let view = ZoomingImageView()
        view.setImage(image)
        return view
    }

    func updateUIView(_ view: ZoomingImageView, context: Context) {
        view.setImage(image)
    }
}

/// A scroll view that fits its photo to the viewport and zooms from there.
///
/// The fitting deliberately happens in layoutSubviews rather than in the
/// representable's updateUIView. SwiftUI calls updateUIView immediately after
/// makeUIView, while bounds are still zero, and then never again unless some
/// state changes — so a frame computed there stays wrong forever. Since
/// UIImageView(image:) sizes itself to the image's pixel dimensions, "wrong"
/// meant a 1:1 crop of a 12-megapixel photo that minimumZoomScale refused to
/// shrink.
final class ZoomingImageView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    /// The viewport size the photo is currently fitted to.
    private var fittedSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)

        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = .black
        contentInsetAdjustmentBehavior = .never

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        // While fully zoomed out the pan recogniser would swallow the
        // horizontal drag the paging TabView needs, so swiping to the next
        // photo would stop working. Switched back on once there is something
        // to pan (see scrollViewDidZoom).
        panGestureRecognizer.isEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ZoomingImageView is created in code only")
    }

    func setImage(_ image: UIImage) {
        guard imageView.image !== image else { return }
        imageView.image = image
        // Force the next layout pass to refit.
        fittedSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Refits on the first real layout pass and on rotation, and nothing
        // else. Zooming changes the image view's frame but not the scroll
        // view's bounds, so this cannot reset a pinch in progress.
        guard bounds.width > 0, bounds.size != fittedSize else { return }
        fittedSize = bounds.size

        zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: bounds.size)
        contentSize = bounds.size
        panGestureRecognizer.isEnabled = false
        centerContent()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent()
        panGestureRecognizer.isEnabled = zoomScale > minimumZoomScale * 1.01
    }

    /// Keeps the photo centred rather than pinned to the top-left whenever it
    /// is smaller than the viewport.
    private func centerContent() {
        let horizontal = max(0, (bounds.width - imageView.frame.width) / 2)
        let vertical = max(0, (bounds.height - imageView.frame.height) / 2)
        contentInset = UIEdgeInsets(
            top: vertical, left: horizontal, bottom: vertical, right: horizontal
        )
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            // Zoom toward whatever was tapped, not the middle.
            let scale: CGFloat = 3
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(
                to: CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                ),
                animated: true
            )
        }
    }
}
