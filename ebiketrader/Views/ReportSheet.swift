//
//  ReportSheet.swift
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

/// The reason picker, the notes field and the write to `reports`, shared by
/// every kind of report. Flagging objectionable content is required for apps
/// with user-generated content (App Store guideline 1.2), and reports land in
/// the same collection the website writes to, so they appear in the existing
/// admin queue and trigger the same notification email.
///
/// `identity` is whatever names the thing being reported. Every report carries
/// a non-empty listingId whatever its kind, because firestore.rules requires
/// one on create — a conversation is always about a listing, so that costs
/// nothing and meant reporting a thread needed no rules change.
struct ReportSheet: View {
    let title: String
    let footnote: String
    let identity: [String: Any]

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
                    Text(footnote)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() {
        // firestore.rules refuses a report whose reporterId isn't the caller,
        // so a signed-out submit would fail anyway — this just says why.
        guard auth.uid != nil else {
            errorMessage = "You need to be signed in to send a report."
            return
        }

        isSending = true
        errorMessage = nil

        var data = identity
        data["reason"] = reason.rawValue
        data["details"] = details.trimmingCharacters(in: .whitespacesAndNewlines)
        // firestore.rules requires exactly "open" on create.
        data["status"] = "open"
        data["createdAt"] = FieldValue.serverTimestamp()

        Task {
            do {
                try await Firestore.firestore().collection("reports").addDocument(data: data)
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
