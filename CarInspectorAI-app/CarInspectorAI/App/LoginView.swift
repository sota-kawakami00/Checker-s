import SwiftUI
import Core
import DesignSystem

/// ログイン（FR-101/105）
struct LoginView: View {
    let onSignedIn: (Staff) -> Void

    @Environment(\.appContainer) private var container
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var resetMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: CIToken.Space.l) {
                VStack(spacing: CIToken.Space.s) {
                    Image(systemName: "car.side.and.exclamationmark")
                        .font(.system(size: 52))
                        .foregroundStyle(CIToken.Colors.primary)
                    Text("app.name")
                        .font(CIToken.Fonts.titleL)
                    Text("login.subtitle")
                        .font(CIToken.Fonts.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, CIToken.Space.xl)

                GlassCard {
                    VStack(spacing: CIToken.Space.m) {
                        TextField("login.email", text: $email)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(CIToken.Space.s)
                            .background(CIToken.Colors.bgBase, in: RoundedRectangle(cornerRadius: CIToken.Radius.button))

                        SecureField("login.password", text: $password)
                            .textContentType(.password)
                            .padding(CIToken.Space.s)
                            .background(CIToken.Colors.bgBase, in: RoundedRectangle(cornerRadius: CIToken.Radius.button))

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(CIToken.Fonts.caption)
                                .foregroundStyle(CIToken.Colors.danger)
                        }
                        if let resetMessage {
                            Label(resetMessage, systemImage: "envelope.fill")
                                .font(CIToken.Fonts.caption)
                                .foregroundStyle(CIToken.Colors.accent)
                        }

                        PrimaryButton(
                            String(localized: "login.signIn"),
                            isLoading: isLoading,
                            isEnabled: !email.isEmpty && !password.isEmpty
                        ) {
                            Task { await signIn() }
                        }

                        Button("login.forgotPassword") {
                            Task { await sendReset() }
                        }
                        .font(CIToken.Fonts.caption)
                    }
                }
                .padding(.horizontal, CIToken.Space.m)

                GlassCard {
                    VStack(alignment: .leading, spacing: CIToken.Space.xs) {
                        Text("login.demo.title")
                            .font(CIToken.Fonts.caption.bold())
                        Text("login.demo.body")
                            .font(CIToken.Fonts.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, CIToken.Space.m)
            }
        }
        .background(CIToken.Colors.bgBase)
    }

    private func signIn() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let staff = try await container.authService.signIn(email: email, password: password)
            onSignedIn(staff)
        } catch {
            errorMessage = String(localized: "login.error")
        }
    }

    private func sendReset() async {
        resetMessage = nil
        errorMessage = nil
        do {
            try await container.authService.sendPasswordReset(email: email)
            resetMessage = String(localized: "login.resetSent")
        } catch {
            errorMessage = String(localized: "login.resetFailed")
        }
    }
}
