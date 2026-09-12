//
//  SignInView.swift
//  ebiketrader
//

import AuthenticationServices
import SwiftUI

extension View {
    /// The sign-in sheet used by every tab that needs an account.
    ///
    /// A sheet rather than a pushed screen on purpose: these tabs swap their
    /// own root the moment sign-in succeeds, and a pushed screen survives
    /// that swap — leaving the person staring at a form they already
    /// completed, with no sign that it worked.
    func signInSheet(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) {
            NavigationStack {
                SignInView(dismissOnSignIn: true)
                    .navigationTitle("Sign in")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

/// Sign-in and sign-up. Offers the same providers as the website
/// (email/password and Google) plus Sign in with Apple, which the App Store
/// requires whenever a third-party login is present.
///
/// Note for anyone testing with an existing web account: Firebase keeps one
/// account per email address and does *not* auto-link providers, so sign in
/// with whichever method that account was created with.
struct SignInView: View {
    /// Set when this is shown as a sheet (from "Message the seller"), so it
    /// can close itself once sign-in succeeds.
    var dismissOnSignIn = false

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var resetSent = false

    private enum Mode: String, CaseIterable {
        case signIn = "Sign in"
        case signUp = "Create account"
    }

    private var canSubmit: Bool {
        guard !email.isEmpty, password.count >= 6 else { return false }
        if mode == .signUp, name.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return !auth.isWorking
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                fields

                if let error = auth.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if resetSent {
                    Text("Password reset email sent.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                submitButton
                dividerRow
                providerButtons

                Text("By continuing you agree to the Terms of Use, and confirm you are 18 or older.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                LegalLinksRow()
            }
            .padding(20)
            .readableWidth(480)
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn && dismissOnSignIn { dismiss() }
        }
        .onChange(of: mode) { _, _ in
            auth.errorMessage = nil
            resetSent = false
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "bicycle")
                .font(.system(size: 40))
                .foregroundStyle(Theme.brand)
            Text("eBikeTrader")
                .font(.title2.bold())
            Text("Save listings, message sellers, and list your own bike.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var fields: some View {
        VStack(spacing: 12) {
            if mode == .signUp {
                TextField("Your name", text: $name)
                    .textContentType(.name)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $password)
                .textContentType(mode == .signUp ? .newPassword : .password)
                .textFieldStyle(.roundedBorder)

            if mode == .signIn {
                Button("Forgot password?") {
                    Task {
                        await auth.sendPasswordReset(to: email)
                        if auth.errorMessage == nil { resetSent = true }
                    }
                }
                .font(.footnote)
                .disabled(email.isEmpty || auth.isWorking)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var submitButton: some View {
        Button {
            Task {
                resetSent = false
                if mode == .signIn {
                    await auth.signIn(email: email, password: password)
                } else {
                    await auth.signUp(email: email, password: password, displayName: name)
                }
            }
        } label: {
            Group {
                if auth.isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(mode.rawValue).font(.subheadline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canSubmit ? Theme.brand : Color.gray.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(.white)
        }
        .disabled(!canSubmit)
    }

    private var dividerRow: some View {
        HStack {
            VStack { Divider() }
            Text("or").font(.caption).foregroundStyle(.secondary)
            VStack { Divider() }
        }
    }

    private var providerButtons: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn) { request in
                auth.prepareAppleRequest(request)
            } onCompletion: { result in
                auth.handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if AuthStore.googleSignInAvailable {
                Button {
                    Task { await auth.signInWithGoogle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "g.circle.fill")
                        Text("Continue with Google").font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(.separator))
                    }
                    .foregroundStyle(.primary)
                }
                .disabled(auth.isWorking)
            }
        }
    }
}
