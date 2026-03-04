import SwiftUI

public struct PlaylistView: View {
    public init() {}
    
    public var body: some View {
        List(0..<10) { index in
            Button(action: {}) {
                HStack {
                    Image(systemName: "play.circle")
                    Text("Episode \(index + 1)")
                    Spacer()
                    Text("45:00")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 300)
    }
}
