import AuthenticationServices
import CryptoKit
import Supabase
import SwiftUI
import OnyxUI

/// Sign-in. One screen, seen once per install.
///
/// ── NO CREDENTIAL IS BAKED INTO THIS BUILD ──────────────────────────────────
/// The web app shipped `NEXT_PUBLIC_DEV_EMAIL` / `NEXT_PUBLIC_DEV_PASSWORD`
/// behind a single "Continue as Michael" button, which inlined the account
/// password into every client bundle it served. That is the thing this screen
/// exists not to do. The fields carry `.username` and `.password` content types,
/// so iOS Password AutoFill offers the saved credential as one tap — the same
/// convenience, from the Keychain rather than from the binary.
///
/// The session then persists in the Keychain (`KeychainAuthStorage`), not in
/// UserDefaults, which is the other half of the same argument.
///
/// ── WHAT AUTOFILL NEEDS, AND WHERE BOTH HALVES NOW ARE ──────────────────────
/// The content types above are enough for iOS to OFFER to save a credential and
/// to fill one already associated with this app. Filling the credential saved
/// against the WEBSITE — the one the browser holds — needs two more things, and
/// only ONE of them is in the repo right now: the `apple-app-site-association`
/// file at `site/.well-known/`, which names this App ID under
/// `webcredentials`. The other half — the `Associated Domains` entitlement —
/// is PARKED in `native/project.yml` (see the comment where it used to be),
/// because a free Personal Development Team cannot sign it and Xcode refuses
/// the profile outright. So website-credential fill does nothing until the
/// paid Developer Program lands and the key goes back.
///
/// When it does go back, the capability also has to be enabled on the App ID
/// in the developer portal, or signing fails on the entitlement. If AutoFill
/// offers nothing from the website, check the portal before checking this file
/// — the two sides fail silently when they disagree.
struct SignInView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?
    /// Counts ATTEMPTS, not messages. Keying the haptic on the error string
    /// means two identical failures in a row buzz once.
    @State private var attempt = 0
    /// Sign-up is a sheet rather than a push: this screen has no navigation
    /// stack (RootView switches on `auth`, it does not navigate), and a modal
    /// is also the honest shape — creating an account is a detour off signing
    /// in, not a place further along the same path.
    @State private var showSignUp = false
    /// The RAW nonce of the Apple request in flight. Apple gets its SHA-256;
    /// Supabase gets this and hashes it itself to check the token's claim.
    @State private var appleNonce = ""
    /// One height for both provider buttons, grown with Dynamic Type. Apple's
    /// button sizes its title off its HEIGHT and ignores Dynamic Type, so a
    /// fixed 50 left it small at AX5 beside a Google label that had tripled
    /// and clipped — the opposite of the parity 4.8 asks for.
    @ScaledMetric(relativeTo: .title3) private var providerHeight: CGFloat = 50
    /// Sized to Apple's glyph, not to the title beside it: at 18 the colour
    /// mark read larger than the monochrome one it stands under.
    @ScaledMetric(relativeTo: .title3) private var googleMark: CGFloat = 15
    @FocusState private var focused: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && !isWorking
    }

    var body: some View {
        // A `VStack` with two `Spacer`s cannot scroll, and at the largest
        // accessibility size with the keyboard up it pushes the password field
        // and the button off the bottom with no way to reach them.
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(OnyxSpace.xl)
                    // The two `Spacer`s centre the card only when the stack has
                    // a height to fill; inside a scroll view they would collapse
                    // to nothing and the form would sit under the status bar.
                    // This gives it the screen's height as a FLOOR, so it centres
                    // when it fits and scrolls when it does not.
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onyxScreen(.train)
        // ── NO FOCUS ON APPEAR (App Store W7) ──────────────────────────────
        // The email field used to take focus here, to raise the QuickType bar
        // with the AutoFill suggestion. With three doors that keyboard covered
        // Apple and Google on arrival — choosing email for the user and hiding
        // the button 4.8 says must be no less prominent. A tap on the field
        // raises the same bar.
        .sensoryFeedback(.error, trigger: attempt) { _, _ in error != nil }
        .sheet(isPresented: $showSignUp) { SignUpView() }
    }

    private var content: some View {
        VStack(spacing: OnyxSpace.xl) {
            Spacer()

            VStack(spacing: 8) {
                // The mark itself, not a stand-in symbol: this is the one
                // screen with room for it at full size, and `OnyxMark` already
                // carries the Lunar → Ion ramp the app icon is lit with.
                OnyxMark(size: 44, opacity: 1)
                OnyxWordmark(role: .hero)
                    .accessibilityAddTraits(.isHeader)
                Text("Engineer Your Ascent.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.onyx.textSecondary)
            }

            VStack(spacing: 0) {
                field("Email") {
                    TextField("you@example.com", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                }
                Divider().overlay(Color.onyx.hairline)
                field("Password") {
                    SecureField("Required", text: $password)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .focused($focused, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                }
            }
            .onyxGlass(.tile)

            Button(action: submit) {
                Group {
                    if isWorking {
                        ProgressView().tint(Color.onyx.base)
                    } else {
                        Text("Sign in").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(OnyxDomain.train.accent)
            // Obsidian on the accent reads; obsidian on the DISABLED fill was
            // about 1.2:1 — a button nobody could read the name of.
            .foregroundStyle(canSubmit || isWorking ? Color.onyx.base : Color.onyx.textSecondary)
            .controlSize(.large)
            .disabled(!canSubmit)

            // Reserved space, not a conditional row: a message that appears by
            // pushing the button down moves the control the user is aiming at,
            // which on a failed attempt is the moment they are most likely to
            // tap again.
            Text(error ?? " ")
                .font(.footnote)
                .foregroundStyle(Color.onyx.danger)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .top)
                .accessibilityHidden(error == nil)

            // ── THE OTHER TWO DOORS (App Store W7) ─────────────────────────
            // Beside email, never instead of it. Apple is first and the same
            // height as Google (4.8: Google makes Apple mandatory, and HIG
            // wants it no less prominent than any other sign-in button). Both
            // white on this dark ground — the pair reads as one row of choices.
            VStack(spacing: OnyxSpace.m) {
                Text("or")
                    .font(.footnote)
                    .foregroundStyle(Color.onyx.textTertiary)
                SignInWithAppleButton(.signIn) { request in
                    appleNonce = Self.randomNonce()
                    request.requestedScopes = [.email]
                    request.nonce = Self.sha256(appleNonce)
                } onCompletion: { result in
                    signInWithApple(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: providerHeight)
                .clipShape(Capsule())
                Button {
                    run { try await environment.signInWithGoogle() }
                } label: {
                    HStack(spacing: OnyxSpace.s) {
                        Image("GoogleG")
                            .resizable()
                            .frame(width: googleMark, height: googleMark)
                            .accessibilityHidden(true)
                        // `.title3` is ~20 pt, which is what Apple's button
                        // sets at this height; `.body` read a size smaller.
                        Text("Sign in with Google")
                            .font(.title3.weight(.medium))
                            // Shrinks to the width, as Apple's title does.
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .padding(.horizontal, OnyxSpace.l)
                    .frame(maxWidth: .infinity, minHeight: providerHeight)
                    .foregroundStyle(Color.onyx.base)
                    .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .disabled(isWorking)
            // Capped at AX1: Apple's title never follows Dynamic Type, and past
            // AX1 Google's had to shrink to fit the width. Capped together they
            // stay one size — and still grow well past the default.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            Button("Create an account") { showSignUp = true }
                .font(.footnote.weight(.medium))
                .foregroundStyle(OnyxDomain.train.accent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())

            Spacer()

            Text("You stay signed in on this device.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.onyx.textTertiary)
        }
    }

    /// A labelled row. `LabeledContent` is the stock answer and it is the wrong
    /// one here: it puts the label and the field on one line and hands the field
    /// whatever width is left, which at AX5 leaves about four characters.
    @ViewBuilder
    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.onyx.textSecondary)
            content()
                .foregroundStyle(Color.onyx.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func submit() {
        guard canSubmit else { return }
        run { [email, password] in try await environment.signIn(email: email, password: password) }
    }

    /// Apple's sheet has closed. Its identity token goes to Supabase with the
    /// raw nonce whose hash went out in the request.
    private func signInWithApple(_ result: Result<ASAuthorization, any Error>) {
        run { [appleNonce] in
            guard let credential = try result.get().credential as? ASAuthorizationAppleIDCredential,
                  let token = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) })
            else { throw AppleSignInError.noToken }
            try await environment.signInWithApple(idToken: token, nonce: appleNonce)
        }
    }

    /// One attempt through any of the three doors: the same busy state, the
    /// same reserved error band, the same haptic and announcement.
    private func run(_ attemptSignIn: @escaping @MainActor () async throws -> Void) {
        // `.disabled` lands a frame late; a double tap would start two OAuth
        // flows, and the second overwrites the first's PKCE verifier.
        guard !isWorking else { return }
        isWorking = true
        error = nil
        Task {
            do {
                try await attemptSignIn()
                // No navigation here on purpose. `AppEnvironment` observes the
                // auth stream and `RootView` switches on it, so the screen
                // changes because the session changed — never because a button
                // decided it had.
                attempt += 1
            } catch where Self.isCancel(error) {
                // Closing Apple's sheet or Google's page is a choice, not a
                // failure: no message, no buzz.
            } catch {
                attempt += 1
                // `String(describing:)` on a Supabase error prints the enum case
                // and its associated values, which is a stack trace to a person
                // trying to log in. The underlying text is kept for the one case
                // that is actionable — a wrong password says so.
                let message = Self.message(for: error)
                self.error = message
                // The message appears in a reserved band that VoiceOver is not
                // looking at, so a failed sign-in was silent to it.
                AccessibilityNotification.Announcement(message).post()
            }
            isWorking = false
        }
    }

    private static func message(for error: any Error) -> String {
        // The system's own text for these two is an NSError domain and code.
        if error is ASAuthorizationError { return "Sign in with Apple didn't finish. Try again, or use your email." }
        if error is ASWebAuthenticationSessionError { return "Google sign-in didn't finish. Try again, or use your email." }
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return text.isEmpty ? "Sign-in failed. Check the email and password." : text
    }

    /// Closing the sheet, or Cancel on Google's own consent page — which comes
    /// back through the callback as `access_denied`. "Sign-ups are disabled"
    /// arrives the same way and must stay visible.
    private static func isCancel(_ error: any Error) -> Bool {
        if case let .pkceGrantCodeExchange(_, kind, code) = error as? AuthError {
            return kind == "access_denied" && code != "signup_disabled"
        }
        return (error as? ASAuthorizationError)?.code == .canceled
            || (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
    }

    /// 32 random bytes as hex. `UInt8.random` draws from the system CSPRNG.
    private static func randomNonce() -> String {
        (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private enum AppleSignInError: LocalizedError {
        case noToken
        var errorDescription: String? { "Apple did not return a sign-in token. Try again, or use your email." }
    }
}

#if DEBUG
#Preview("Sign in") {
    SignInView().environment(AppEnvironment.preview)
}
#endif
