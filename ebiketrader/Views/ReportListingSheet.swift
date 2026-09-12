//
//  ReportListingSheet.swift
//  ebiketrader
//

import SwiftUI
import FirebaseFirestore

/// Mirrors REPORT_REASONS / REPORT_REASON_LABELS in the website's
/// src/lib/types.ts. Raw values are the strings stored in Firestore and read
/// back by the admin reports queue, so they must not drift.
enum ReportReason: String, CaseIterable, Identifiable {
    case spam
    case scam
    case soldElsewhere = "sold-elsewhere"
    case inappropriate
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spam: return "Spam"
        case .scam: return "Scam or fraud"
        case .soldElsewhere: return "Already sold elsewhere"
        case .inappropriate: return "Inappropriate content"
        case .other: return "Other"
        }
    }
}

/// Flagging objectionable content is required for apps with user-generated
/// content (App Store guideline 1.2). Reports land in the same `reports`
/// collection the website writes to, so they show up in the existing admin
/// queue and trigger the same notification email to admins.
struct ReportListingSheet: View {
    let listing: Listing

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var reason: ReportReason = .spam
    @State private var details = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Why are you reporting this?") {
                    Picker("Reason", selection: $reason) {
                        ForEach(ReportReason.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Anything else we should know?") {
                    TextField("Optional details", text: $details, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Spacer()
                            if isSending {
                                ProgressView()
                            } else {
                                Text(sent ? "Report sent" : "Send report").fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isSending || sent)
                } footer: {
                    Text("We review every report. You can also block this seller so their listings stop appearing for you.")
                }
            }
            .navigationTitle("Report listing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() {
        guard let uid = auth.uid else {
            errorMessage = "You need to be signed in to report a listing."
            return
        }

        isSending = true
        errorMessage = nil

        Task {
            do {
                try await Firestore.firestore().collection("reports").addDocument(data: [
                    "listingId": listing.id,
                    "listingTitle": listing.title,
                    "listingSellerId": listing.sellerId,
                    "reporterId": uid,
                    "reason": reason.rawValue,
                    "details": details.trimmingCharacters(in: .whitespacesAndNewlines),
                    // firestore.rules requires exactly "open" on create.
                    "status": "open",
                    "createdAt": FieldValue.serverTimestamp(),
                ])
                sent = true
                isSending = false
                try? await Task.sleep(for: .milliseconds(600))
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSending = false
            }
        }
    }
}
