//
//  PhotoSourceButtons.swift
//  ebiketrader
//

import PhotosUI
import SwiftUI

/// The "Choose photos" / "Camera" pair. Shared by the listing form's photo row
/// and by PhotoOrganizerView, so photos can be added from either place without
/// the two copies drifting apart.
struct PhotoSourceButtons: View {
    @Binding var plan: [PhotoPlanItem]

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false

    private var remainingSlots: Int { max(0, ListingWriter.maxPhotos - plan.count) }

    var body: some View {
        // .borderless on both is load-bearing, not cosmetic: a Form row
        // holding more than one control collapses them into a single tap
        // target, and a tap on either one then fires the wrong action.
        HStack(spacing: 12) {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: remainingSlots,
                matching: .images
            ) {
                Label("Choose photos", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.borderless)
            .disabled(remainingSlots == 0)

            if CameraPicker.isAvailable {
                Spacer()
                Button {
                    showCamera = true
                } label: {
                    Label("Camera", systemImage: "camera")
                }
                .buttonStyle(.borderless)
                .disabled(remainingSlots == 0)
            }
        }
        .font(.subheadline)
        .sheet(isPresented: $showCamera) {
            if CameraPicker.isAvailable {
                CameraPicker { image in
                    plan.appendPhoto(image)
                }
                .ignoresSafeArea()
            } else {
                // The simulator has no camera; presenting one there shows a
                // black screen at best.
                ContentUnavailableView(
                    "No camera",
                    systemImage: "camera",
                    description: Text("This device doesn't have a camera available.")
                )
            }
        }
        .onChange(of: pickerItems) { _, items in
            loadPicked(items)
        }
    }

    private func loadPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }

        Task {
            for item in items {
                guard plan.count < ListingWriter.maxPhotos else { break }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    plan.appendPhoto(image)
                }
            }
            pickerItems = []
        }
    }
}

/// One photo from a form's photo plan, whether it is already uploaded or was
/// picked a second ago. Fills whatever frame it is given, so give it one.
struct PhotoPlanThumbnail: View {
    let item: PhotoPlanItem

    var body: some View {
        Group {
            if let image = item.newImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let url = item.existingURL {
                ListingPhoto(url: URL(string: url))
            } else {
                Theme.placeholder
            }
        }
    }
}
