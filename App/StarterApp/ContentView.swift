import StarterKit
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hammer")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(Greeting.message(for: "world"))
                .font(.title2)
            Text("If you can read this on a phone, the pipeline works.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
