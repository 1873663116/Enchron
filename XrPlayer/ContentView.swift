//
//  ContentView.swift
//  XrPlayer
//
//  Created by 熊志鹏 on 2026/3/3.
//

import SwiftUI
import RealityKit

struct ContentView: View {

    var body: some View {
        VStack {
            ToggleImmersiveSpaceButton()
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
