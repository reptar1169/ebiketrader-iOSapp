//
//  ListingFormView.swift
//  ebiketrader
//

import SwiftUI

/// Post a new listing, or edit one you already own. Mirrors the website's
/// ListingForm: same required fields, same 8-photo cap, same reorderable
/// photo plan.
struct ListingFormView: View {
    /// nil posts a new listing; non-nil edits that one.
    var existing: Listing?
    var onSaved: ((String) -> Void)?
    /// Set when presented as a sheet. The Cancel button lives here rather
    /// than with the presenter because only the form knows whether there are
    /// unsaved changes worth warning about.
    var showsCancelButton = false

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var input = ListingInput()
    @State private var plan: [PhotoPlanItem] = []

    // Numeric fields are held as text so a half-typed value doesn't fight the
    // formatter; they're parsed into `input` on save.
    @State private var priceText = ""
    @State private var yearText = ""
    @State private var mileageText = ""
    @State private var batteryText = ""

    @State private var isSaving = false
    @State private var uploadedCount = 0
    @State private var uploadTotal = 0
    @State private var errorMessage: String?
    @State private var didSeed = false

    @FocusState private var cityFieldFocused: Bool

    /// The form exactly as it was loaded, for comparison against now.
    @State private var seededSnapshot: FormSnapshot?
    @State private var confirmDiscard = false

    /// Everything the person can change. The numeric fields are held as text
    /// until save, so comparing `input` alone would miss an edited price.
    private struct FormSnapshot: Equatable {
        var input: ListingInput
        /// Identities in order, so an added, removed or reordered photo counts.
        var planIds: [String]
        var priceText: String
        var yearText: String
        var mileageText: String
        var batteryText: String
    }

    private var snapshot: FormSnapshot {
        FormSnapshot(
            input: input,
            planIds: plan.map(\.id),
            priceText: priceText,
            yearText: yearText,
            mileageText: mileageText,
            batteryText: batteryText
        )
    }

    private var isDirty: Bool {
        guard let seededSnapshot else { return false }
        return seededSnapshot != snapshot
    }

    private var isEditing: Bool { existing != nil }

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
            }
        }
        .readableWidth()
        .progressOverlay(
            isSaving,
            title: isEditing ? "Saving changes…" : "Posting your listing…",
            detail: uploadTotal > 0
                ? "Photo \(min(uploadedCount + 1, uploadTotal)) of \(uploadTotal)"
                : nil
        )
        .navigationTitle(isEditing ? "Edit listing" : "List your ebike")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        // Suggestion rows rendered inside the Form sat directly under the
        // city field, which is precisely where the keyboard is — and eight
        // rows plus a keyboard do not fit on a small phone whatever you do
        // with scrolling. The keyboard accessory bar cannot be occluded by
        // the keyboard, so they live there, where QuickType would be.
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if cityFieldFocused, !citySuggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(citySuggestions, id: \.self) { name in
                                Button {
                                    input.city = name
                                    // Dismissing confirms the choice landed.
                                    cityFieldFocused = false
                                } label: {
                                    Text(name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Theme.brand.opacity(0.15), in: Capsule())
                                        .foregroundStyle(Theme.brandDark)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }

            if showsCancelButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty {
                            confirmDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        // Only while there is something to lose — a clean form still closes
        // with a swipe, so this never nags.
        .interactiveDismissDisabled(isDirty && !isSaving)
        .confirmationDialog(
            "Discard your changes?",
            isPresented: $confirmDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .onAppear(perform: seedIfNeeded)
    }

    // MARK: - Sections

    private var photosSection: some View {
        Section {
            NavigationLink {
                PhotoOrganizerView(plan: $plan)
            } label: {
                HStack(spacing: 12) {
                    if plan.isEmpty {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    } else {
                        HStack(spacing: 4) {
                            ForEach(plan.prefix(4)) { item in
                                PhotoPlanThumbnail(item: item)
                                    .frame(width: 42, height: 42)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.isEmpty
                             ? "Add photos"
                             : "\(plan.count) photo\(plan.count == 1 ? "" : "s")")
                        Text(plan.isEmpty ? "Tap to choose or shoot some" : "Tap to reorder or remove")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Photos (up to \(ListingWriter.maxPhotos))")
        } footer: {
            Text("The first photo is the one buyers see in search results.")
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

    /// State first, then city with suggestions — the same order and the same
    /// data as the website's form.
    private var locationSection: some View {
        Section {
            Picker("State", selection: $input.state) {
                Text("Select a state").tag("")
                ForEach(usStates, id: \.self) { code in
                    Text(code).tag(code)
                }
            }
            // 51 entries is too many for a wheel; this pushes a searchable
            // list instead.
            .pickerStyle(.navigationLink)

            TextField("City", text: $input.city)
                .focused($cityFieldFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
        } header: {
            Text("Location")
        } footer: {
            Text(input.state.isEmpty
                 ? "Pick a state first and the city field will suggest matches as you type."
                 : "Used to place your bike on the map. Only the city and state are shown — never an address.")
        }
    }

    /// Shown while the city field has focus and the text is not already an
    /// exact match — otherwise the list would sit there after you have
    /// chosen, which reads as though the choice did not register.
    private var citySuggestions: [String] {
        guard cityFieldFocused, !input.state.isEmpty else { return [] }
        guard !CityCatalog.isKnown(input.city, in: input.state) else { return [] }
        return CityCatalog.suggestions(for: input.city, in: input.state, limit: 6)
    }

    // MARK: - Actions

    private func seedIfNeeded() {
        guard !didSeed else { return }
        didSeed = true

        guard let existing else {
            // A blank new-listing form: anything typed counts as a change.
            seededSnapshot = FormSnapshot(
                input: ListingInput(),
                planIds: [],
                priceText: "",
                yearText: "",
                mileageText: "",
                batteryText: ""
            )
            return
        }

        let seededInput = ListingInput(from: existing)
        let seededPlan = existing.photos.map { PhotoPlanItem.existing(url: $0) }
        let seededPrice = String(Int(existing.price))
        let seededYear = existing.year.map(String.init) ?? ""
        let seededMileage = existing.mileageMiles.map(String.init) ?? ""
        let seededBattery = existing.batteryHealthPct.map(String.init) ?? ""

        input = seededInput
        plan = seededPlan
        priceText = seededPrice
        yearText = seededYear
        mileageText = seededMileage
        batteryText = seededBattery

        // Built from the locals rather than read back out of @State, so the
        // baseline can't depend on when SwiftUI applies those writes.
        seededSnapshot = FormSnapshot(
            input: seededInput,
            planIds: seededPlan.map(\.id),
            priceText: seededPrice,
            yearText: seededYear,
            mileageText: seededMileage,
            batteryText: seededBattery
        )
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
