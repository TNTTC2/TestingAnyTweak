import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)
                
                Text("👍")
                    .font(.title)
                    .bold()
                
                Text("🤫")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("🤯")
        }
    }
}

#Preview {
    ContentView()
}
