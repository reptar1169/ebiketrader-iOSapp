//
//  FilterSheet.swift
//  ebiketrader
//

import SwiftUI

/// The filter controls the website keeps inline above the grid. On a phone
/// there isn't room for that, so they live in a sheet and the toolbar button
/// shows whether any are on.
struct FilterSheet: View {
    @Binding var filters: ListingFilters
    /// Brands present in the current feed — same idea as the homepage's
    /// "Shop by brand" row, which is built from real inventory rather than a
    /// hardcoded list that drifts out of date.
    let availableBrands: [String]

    @Environment(\.dismiss) private var dismiss

    @State private var minPriceText = ""
    @State private var maxPriceText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Condition") {
                    Picker("Condition", selection: $filters.condition) {
                        Text("Any").tag(Condition?.none)
                        ForEach(Condition.allCases) { condition in
                            Text(condition.label).tag(Condition?.some(condition))
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                if !availableBrands.isEmpty {
                    Section("Brand") {
                        Picker("Brand", selection: $filters.brand) {
                            Text("Any").tag(String?.none)
                            ForEach(availableBrands, id: \.self) { brand in
                                Text(brand).tag(String?.some(brand))
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                Section("Price") {
                    HStack {
                        Text("Min")
                        Spacer()
                        TextField("Any", text: $minPriceText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Max")
                        Spacer()
                        TextField("Any", text: $maxPriceText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Button("Clear all filters", role: .destructive) {
                        filters.clear()
                        minPriceText = ""
                        maxPriceText = ""
                    }
                    .disabled(!filters.isActive && minPriceText.isEmpty && maxPriceText.isEmpty)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyPrices()
                        dismiss()
                    }
                }
            }
            .onAppear {
                minPriceText = filters.minPrice.map { String(Int($0)) } ?? ""
                maxPriceText = filters.maxPrice.map { String(Int($0)) } ?? ""
            }
        }
    }

    private func applyPrices() {
        filters.minPrice = Double(minPriceText.filter(\.isNumber))
        filters.maxPrice = Double(maxPriceText.filter(\.isNumber))
    }
}
