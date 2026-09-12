//
//  ListingFormView.swift
//  ebiketrader
//

import PhotosUI
import SwiftUI

/// Post a new listing, or edit one you already own. Mirrors the website's
/// ListingForm: same required fields, same 8-photo cap, same reorderable
/// photo plan.
struct ListingFormView: View {
    /// nil posts a new listing; non-nil edits that one.
    var existing: Listing?
    var onSaved: ((String) -> Void)?

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var input = ListingInput()
    @State private var plan: [PhotoPlanItem] = []
    @State private var pickerItems: [PhotosPickerItem] = []

    // Numeric fields are held as text so a half-typed value doesn't fight the
    // formatter; they're parsed into `input` on save.
    @State private var priceText = ""
    @State private var yearText = ""
    @State private var mileageText = ""
    @State private var batteryText = ""

    @State private var showCamera = false
    @State private var isSaving = false
    @State private var uploadedCount = 0
    @State private var uploadTotal = 0
    @State private var errorMessage: String?
    @State private var didSeed = false

    private var isEditing: Bool { existing != nil }
    private var remainingPhotoSlots: Int { max(0, ListingWriter.maxPhotos - plan.count) }

    var body: some View {
        Form {
            photosSection
            basicsSection
            detailsSection
            locationSection

            Section("Description") {
                TextField(
                    "Anything a buyer should know — upgrades, wear, why you're selling.",
                    text: $input.listingDescription,
                    axis: .vertical
                )
                .lineLimit(4...10)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(action: save) {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(isEditing ? "Save changes" : "Post listing")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(isSaving)
            } footer: {
                if isSaving && uploadTotal > 0 {
                    Text("Uploading photo \(min(uploadedCount + 1, uploadTotal)) of \(uploadTotal)…")
                }
            }
        }
        .navigationTitle(isEditing ? "Edit listing" : "List your ebike")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showCamera) {
            if CameraPicker.isAvailable {
                CameraPicker { image in
                    appendImage(image)
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
            loadPickedPhotos(items)
        }
        .onAppear(perform: seedIfNeeded)
    }

    // MARK: - Sections

    private var photosSection: some View {
        Section {
            if !plan.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(plan) { item in
                            photoThumbnail(for: item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // .borderless on both is load-bearing, not cosmetic: a Form row
            // holding more than one control collapses them into a single tap
            // target, and a tap on either one fires the wrong action.
            HStack(spacing: 12) {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: remainingPhotoSlots,
                    matching: .images
                ) {
                    Label("Choose photos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderless)
                .disabled(remainingPhotoSlots == 0)

                if CameraPicker.isAvailable {
                    Spacer()
                    Button {
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    .buttonStyle(.borderless)
                    .disabled(remainingPhotoSlots == 0)
                }
            }
            .font(.subheadline)
        } header: {
            Text("Photos (up to \(ListingWriter.maxPhotos))")
        } footer: {
            Text("The first photo is the one buyers see in search results.")
        }
    }

    @ViewBuilder
    private func photoThumbnail(for item: PhotoPlanItem) -> some View {
        // Looked up rather than passed in, so a removal mid-animation can
        // never index past the end of the array.
        let index = plan.firstIndex(of: item)

        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image = item.newImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if let url = item.existingURL {
                        ListingPhoto(url: URL(string: url))
                    }
                }
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    plan.removeAll { $0 == item }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .font(.title3)
                }
                .padding(3)
            }

            if plan.count > 1 {
                HStack(spacing: 14) {
                    Button {
                        if let index, index > 0 { plan.swapAt(index, index - 1) }
                    } label: {
                        Image(systemName: "arrow.left")
                    }
                    .disabled((index ?? 0) == 0)

                    Button {
                        if let index, index < plan.count - 1 { plan.swapAt(index, index + 1) }
                    } label: {
                        Image(systemName: "arrow.right")
                    }
                    .disabled((index ?? 0) >= plan.count - 1)
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Theme.brandDark)
            }
        }
    }

    private var basicsSection: some View {
        Section("The basics") {
            TextField("Title — e.g. 2022 Rad Power RadCity 5 Plus", text: $input.title)
            TextField("Brand", text: $input.brand)
            TextField("Model", text: $input.model)
            TextField("Year", text: $yearText).keyboardType(.numberPad)

            HStack {
                Text("$")
                    .foregroundStyle(.secondary)
                TextField("Price", text: $priceText)
                    .keyboardType(.numberPad)
            }

            Picker("Condition", selection: $input.condition) {
                ForEach(Condition.allCases) { condition in
                    Text(condition.label).tag(condition)
                }
            }
        }
    }

    private var detailsSection: some View {
        Section("Details (optional)") {
            TextField("Mileage in miles", text: $mileageText).keyboardType(.numberPad)
            TextField("Battery health %", text: $batteryText).keyboardType(.numberPad)

            Picker("Motor", selection: $input.motorType) {
                Text("Not specified").tag("")
                ForEach(motorTypes, id: \.self) { motor in
                    Text(motor).tag(motor)
                }
            }

            TextField("Frame size", text: $input.frameSize)
            TextField("Wheel size", text: $input.wheelSize)
            TextField("Color", text: $input.color)
        }
    }

    private var locationSection: some View {
        Section {
            TextField("City", text: $input.city)
            TextField("State", text: $input.state)
        } header: {
            Text("Location")
        } footer: {
            Text("Used to place your bike on the map. Only the city and state are shown — never an address.")
        }
    }

    // MARK: - Actions

    private func seedIfNeeded() {
        guard !didSeed else { return }
        didSeed = true

        guard let existing else { return }
        input = ListingInput(from: existing)
        plan = existing.photos.map { PhotoPlanItem.existing(url: $0) }
        priceText = String(Int(existing.price))
        yearText = existing.year.map(String.init) ?? ""
        mileageText = existing.mileageMiles.map(String.init) ?? ""
        batteryText = existing.batteryHealthPct.map(String.init) ?? ""
    }

    private func appendImage(_ image: UIImage) {
        guard plan.count < ListingWriter.maxPhotos else { return }
        plan.append(.new(id: UUID(), image: image))
    }

    private func loadPickedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }

        Task {
            for item in items {
                guard plan.count < ListingWriter.maxPhotos else { break }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    appendImage(image)
                }
            }
            pickerItems = []
        }
    }

    private func save() {
        guard let uid = auth.uid else {
            errorMessage = "You need to be signed in to post a listing."
            return
        }

        input.price = Double(priceText.filter(\.isNumber))
        input.year = Int(yearText.filter(\.isNumber))
        input.mileageMiles = Int(mileageText.filter(\.isNumber))
        input.batteryHealthPct = Int(batteryText.filter(\.isNumber))

        if let problem = input.validationError {
            errorMessage = problem
            return
        }

        errorMessage = nil
        isSaving = true
        uploadedCount = 0
        uploadTotal = plan.filter { $0.newImage != nil }.count

        Task {
            do {
                let onProgress: (Int, Int) -> Void = { done, total in
                    Task { @MainActor in
                        uploadedCount = done
                        uploadTotal = total
                    }
                }

                let listingId: String
                if let existing {
                    try await ListingWriter.update(
                        listingId: existing.id,
                        uid: uid,
                        input: input,
                        plan: plan,
                        progress: onProgress
                    )
                    listingId = existing.id
                } else {
                    listingId = try await ListingWriter.create(
                        input: input,
                        sellerId: uid,
                        sellerName: auth.displayName,
                        sellerEmail: auth.email,
                        plan: plan,
                        progress: onProgress
                    )
                }

                isSaving = false
                onSaved?(listingId)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}
