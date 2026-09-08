import SwiftUI

/// The screen a password reset link lands on.
///
/// Before this existed the flow stopped here: the email link authenticated the
/// user and then handed them an app with no way to actually choose a password.
/// The recovery session is held back by `AppEnvironment` until this screen
/// finishes, so nobody reaches the shell mid-reset.
///
/// On success the user is simply signed in. Asking them to sign in again with
/// the password they just set would be a second dead end wearing a different
/// hat.
struct ChooseNewPasswordView: View {
    @Environment(AppEnvironment.self) private var env
    @FocusState private var focus: Field?
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isRevealed = false

    private enum Field { case password, confirmation }

    /// Supabase's own minimum. Stated up front rather than discovered by being
    /// rejected.
    private let minimumLength = 8

    private var meetsLength: Bool { password.count >= minimumLength }
    private var matches: Bool { !confirmation.isEmpty && password == confirmation }
    private var canSubmit: Bool { meetsLength && matches && !env.isCompletingPasswordReset }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    fields
                    requirements
                    if let error = env.passwordResetError { errorNotice(error) }
                    submit
                    cancel
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 40)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear { focus = .password }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "lock.rotation")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Theme.primary)
                .frame(width: 60, height: 60)
                .background(Theme.primaryTint)
                .clipShape(.rect(cornerRadius: 16))
                .padding(.bottom, 4)

            Text("Choose a new password")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.ink)

            if let email = env.pendingPasswordReset?.email, !email.isEmpty {
                Text("For \(email)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }

            Text("Once it's saved you'll be signed straight in — there's nothing else to do.")
                .font(.footnote)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fields: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Group {
                    if isRevealed {
                        TextField("New password", text: $password)
                    } else {
                        SecureField("New password", text: $password)
                    }
                }
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .password)
                .submitLabel(.next)
                .onSubmit { focus = .confirmation }

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.footnote)
                        .foregroundStyle(Theme.meta)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: Theme.minTap)

            Divider().padding(.leading, 14)

            Group {
                if isRevealed {
                    TextField("Confirm password", text: $confirmation)
                } else {
                    SecureField("Confirm password", text: $confirmation)
                }
            }
            .textContentType(.newPassword)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focus, equals: .confirmation)
            .submitLabel(.done)
            .onSubmit { if canSubmit { Task { await submitPassword() } } }
            .padding(.horizontal, 14)
            .frame(minHeight: Theme.minTap)
        }
        .cardSurface()
    }

    /// Live requirements, so the user is never rejected for something they
    /// could have been told before pressing the button.
    private var requirements: some View {
        VStack(alignment: .leading, spacing: 6) {
            requirement("At least \(minimumLength) characters", met: meetsLength)
            requirement(
                "Both entries match",
                met: matches,
                pending: confirmation.isEmpty
            )
        }
    }

    private func requirement(_ text: String, met: Bool, pending: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: pending ? "circle" : (met ? "checkmark.circle.fill" : "xmark.circle.fill"))
                .font(.caption)
                .foregroundStyle(pending ? Theme.meta : (met ? Theme.green : Theme.red))
            Text(text)
                .font(.caption)
                .foregroundStyle(pending ? Theme.meta : (met ? Theme.secondary : Theme.red))
        }
    }

    private func errorNotice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.red.opacity(0.08))
        .clipShape(.rect(cornerRadius: Theme.buttonRadius))
    }

    private var submit: some View {
        Button {
            Task { await submitPassword() }
        } label: {
            HStack(spacing: 8) {
                if env.isCompletingPasswordReset {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text(env.isCompletingPasswordReset ? "Saving" : "Save and sign in")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: Theme.minTap)
            .background(canSubmit ? Theme.primary : Theme.primary.opacity(0.4))
            .clipShape(.rect(cornerRadius: Theme.buttonRadius))
        }
        .buttonStyle(PressableTileStyle())
        .disabled(!canSubmit)
    }

    private var cancel: some View {
        Button {
            Task { await env.cancelPasswordReset() }
        } label: {
            Text("Cancel and sign in another way")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(env.isCompletingPasswordReset)
    }

    private func submitPassword() async {
        focus = nil
        _ = await env.completePasswordReset(newPassword: password)
    }
}
