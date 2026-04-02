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
                .padding(.vertical, 24)
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 32) { // Increased breathing room
                    ForEach(0..<4) { index in
                        Button {
                            selectedEnvironmentIndex = index
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(.clear)
                                    .aspectRatio(16/9, contentMode: .fill)
                                    .glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                                    .overlay {
                                        ZStack {
                                            if selectedEnvironmentIndex == index {
                                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                                    .stroke(Color.accentColor, lineWidth: 3)
                                                    .blur(radius: 2)
                                            }
                                            
                                            Image(systemName: "moon.stars")
                                                .font(.system(size: 44))
                                                .foregroundStyle(selectedEnvironmentIndex == index ? Color.accentColor : .primary)
                                        }
                                    }
                                    .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                    .hoverEffect()
                                
                                Text("Environment \(index + 1)")
                                    .font(.headline)
                                    .padding(.leading, 8)
                                    .foregroundStyle(selectedEnvironmentIndex == index ? Color.accentColor : .primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(selectedEnvironmentIndex == index ? 1.02 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedEnvironmentIndex)
                    }
                }
                .padding(32)
            }

            if let selectedEnvironmentIndex {
                Text("Selected Environment \(selectedEnvironmentIndex + 1)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 20)
            }
        }
        .navigationTitle("Scenes")
    }
}
