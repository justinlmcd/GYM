import SwiftUI

// One-time sign-in with the same email and password as the GYM web app.
struct SignInView: View {
    @Environment(Store.self) private var store
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("GYM")
                    .font(.system(.title2, design: .rounded, weight: .heavy))
                Text("Sign in with your GYM login.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("Email", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                Button {
                    busy = true
                    Task {
                        await store.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
                        password = ""
                        busy = false
                    }
                } label: {
                    if busy { ProgressView() } else { Text("Sign in").bold() }
                }
                .tint(.orange)
                .disabled(busy || email.isEmpty || password.isEmpty)
                if let error = store.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
