import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(SessionModel.self) private var session
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.open.fill")
                .font(.system(size: 64))
                .foregroundStyle(.indigo)
            VStack(spacing: 8) {
                Text("QuestLock").font(.largeTitle.bold())
                Text("Your apps stay locked until you've been outside and found today's quest. Your friends see if you made it.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SignInWithAppleButton(.signIn) { request in
                session.prepare(request)
            } onCompletion: { result in
                session.complete(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            Text("We only use your name, so friends know who you are.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(24)
    }
}
