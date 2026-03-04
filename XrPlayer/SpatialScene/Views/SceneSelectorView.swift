import SwiftUI

public struct SceneSelectorView: View {
    @State private var selectedEnvironmentIndex: Int?

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
                    Button {
                        selectedEnvironmentIndex = index
                    } label: {
                        VStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedEnvironmentIndex == index ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.3))
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

            if let selectedEnvironmentIndex {
                Text("Selected Environment \(selectedEnvironmentIndex + 1)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle("Scenes")
    }
}
