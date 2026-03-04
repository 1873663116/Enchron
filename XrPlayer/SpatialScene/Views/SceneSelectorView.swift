import SwiftUI

public struct SceneSelectorView: View {
    let columns = [
        GridItem(.adaptive(minimum: 200))
    ]
    
    public init() {}
    
    public var body: some View {
        VStack {
            ToggleImmersiveSpaceButton()
                .padding()
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                ForEach(0..<4) { index in
                    Button(action: {}) {
                        VStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.secondary.opacity(0.3))
                                .aspectRatio(16/9, contentMode: .fill)
                                .overlay {
                                    Image(systemName: "moon.stars")
                                        .font(.largeTitle)
                                }
                            Text("Environment \(index + 1)")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            }
        }
        .navigationTitle("Scenes")
    }
}
