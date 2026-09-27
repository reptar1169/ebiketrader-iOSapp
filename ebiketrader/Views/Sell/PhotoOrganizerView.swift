//
//  PhotoOrganizerView.swift
//  ebiketrader
//

import SwiftUI

/// Arranges a listing's photos on a screen of their own.
///
/// This replaced a strip of 90pt thumbnails inside the form with a pair of
/// 12pt arrow buttons under each one. Three things were wrong with that:
/// the arrows were roughly a third of Apple's 44pt minimum touch target in
/// each dimension; the arrows swapped one position per tap, so moving the
/// last of eight photos to the front took seven taps on the smallest control
/// on the screen; and the horizontal strip only showed three and a half
/// photos at a time, so there was no way to see the order you were arranging.
///
/// Here the whole set is visible at once, dragging moves a photo straight to
/// where it belongs, and "Make cover photo" does the one reorder people
/// actually want in a single tap.
struct PhotoOrganizerView: View {
    @Binding var plan: [PhotoPlanItem]

    /// Which cell the drag is currently hovering, for the insertion ring.
    @State private var targetedId: String?
    @State private var viewerStart: ViewerStart?

    /// fullScreenCover(item:) needs something Identifiable; the start index
    /// on its own isn't.
    private struct ViewerStart: Identifiable {
        let id: Int
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if plan.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(plan) { item in
                            cell(for: item)
                        }
                    }
                    // Keyed on the order, so a reorder animates and a photo
                    // load does not.
                    .animation(.snappy(duration: 0.25), value: plan.map(\.id))

                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Divider()

                PhotoSourceButtons(plan: $plan)

                if plan.count >= ListingWriter.maxPhotos {
                    Text("That's the maximum of \(ListingWriter.maxPhotos) photos. Remove one to add another.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .readableWidth()
        }
        .navigationTitle("Photos")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewerStart) { start in
            PhotoPlanViewer(plan: plan, startIndex: start.id)
        }
    }

    private var hint: String {
        plan.count > 1
            ? "Drag a photo to reorder, or use \u{00B7}\u{00B7}\u{00B7} for one-tap options."
            : "The first photo is the one buyers see in search results."
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No photos yet")
                .font(.headline)
            Text("Bikes with clear photos of the frame, drivetrain and battery sell faster.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Cell

    @ViewBuilder
    private func cell(for item: PhotoPlanItem) -> some View {
        // Looked up rather than captured, so a removal mid-animation can never
        // index past the end of the array.
        let index = plan.firstIndex(of: item)

        ZStack(alignment: .topTrailing) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { PhotoPlanThumbnail(item: item) }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.brand, lineWidth: targetedId == item.id ? 3 : 0)
                }
                .overlay(alignment: .bottomLeading) {
                    if index == 0 { coverBadge }
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture {
                    if let index { viewerStart = ViewerStart(id: index) }
                }

            deleteButton(for: item)
        }
        .overlay(alignment: .bottomTrailing) {
            optionsMenu(for: item, index: index)
        }
        .draggable(item.id) {
            // Without a preview the system lifts the whole cell, delete button
            // and all, which looks like you are dragging a control.
            PhotoPlanThumbnail(item: item)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .dropDestination(for: String.self) { ids, _ in
            move(ids.first, to: item)
        } isTargeted: { targeted in
            targetedId = targeted ? item.id : nil
        }
    }

    private var coverBadge: some View {
        Text("COVER")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.brand, in: Capsule())
            .padding(8)
    }

    private func deleteButton(for item: PhotoPlanItem) -> some View {
        Button {
            plan.removeAll { $0 == item }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.55))
                .font(.title2)
                // The glyph is ~22pt. The frame takes it to Apple's 44pt
                // minimum, and contentShape makes the added space actually
                // tappable rather than decorative.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Reordering and delete live behind a visible button rather than a
    /// .contextMenu, because .contextMenu and .draggable both claim the
    /// long-press and the menu wins — attaching both means the drag never
    /// starts. This also gives the actions a real 44pt target instead of the
    /// 12pt arrows they replaced.
    private func optionsMenu(for item: PhotoPlanItem, index: Int?) -> some View {
        Menu {
            menuItems(for: item, index: index)
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.55))
                .font(.title2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
    }

    @ViewBuilder
    private func menuItems(for item: PhotoPlanItem, index: Int?) -> some View {
        if let index {
            if index != 0 {
                Button {
                    makeCover(index)
                } label: {
                    Label("Make cover photo", systemImage: "star")
                }
            }

            if index > 0 {
                Button {
                    plan.swapAt(index, index - 1)
                } label: {
                    Label("Move earlier", systemImage: "arrow.up")
                }
            }

            if index < plan.count - 1 {
                Button {
                    plan.swapAt(index, index + 1)
                } label: {
                    Label("Move later", systemImage: "arrow.down")
                }
            }

            Divider()
        }

        Button(role: .destructive) {
            plan.removeAll { $0 == item }
        } label: {
            Label("Delete photo", systemImage: "trash")
        }
    }

    // MARK: - Reordering

    /// Moves the dragged photo into `target`'s slot.
    ///
    /// remove-then-insert rather than move(fromOffsets:toOffset:) because
    /// toOffset counts positions in the array *before* the removal, which is
    /// off by one whenever you drag a photo forwards.
    ///
    /// The id is checked against the plan because .dropDestination(for:
    /// String.self) will happily hand over text dragged in from another app.
    private func move(_ draggedId: String?, to target: PhotoPlanItem) -> Bool {
        guard let draggedId,
              let from = plan.firstIndex(where: { $0.id == draggedId }),
              let to = plan.firstIndex(of: target),
              from != to
        else { return false }

        let moved = plan.remove(at: from)
        plan.insert(moved, at: to)
        return true
    }

    private func makeCover(_ index: Int) {
        guard plan.indices.contains(index), index != 0 else { return }
        let moved = plan.remove(at: index)
        plan.insert(moved, at: 0)
    }
}
