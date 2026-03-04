import SwiftUI

public struct ScreenPositionControlView: View {
    @State private var distance: Double = 8.0
    @State private var verticalOffset: Double = 0.0
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            Text("Screen Position")
                .font(.headline)
            
            VStack {
                Text("Distance: \(distance, specifier: "%.1f")m")
                Picker("Distance Preset", selection: $distance) {
                    Text("Near").tag(4.0)
                    Text("Comfort").tag(8.0)
                    Text("Cinema").tag(14.0)
                }
                .pickerStyle(.segmented)
                
                Slider(value: $distance, in: 2.0...20.0)
            }
            
            VStack {
                Text("Vertical: \(verticalOffset, specifier: "%.1f")m")
                Slider(value: $verticalOffset, in: -2.0...2.0)
            }
        }
        .padding()
        .frame(width: 400)
        .glassBackgroundEffect()
    }
}
